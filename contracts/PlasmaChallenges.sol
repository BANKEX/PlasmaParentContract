pragma solidity ^0.4.21;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

contract PlasmaChallenges {
    using BankexPlasmaTransaction for BankexPlasmaTransaction.PlasmaTransaction;

    bool public plasmaErrorFound = false;
    uint256 public lastValidBlock = 0;

    PriorityQueueInterface public exitQueue;
    PlasmaBlockStorageInterface public blockStorage;
    address public challengesContract;
    address public owner = msg.sender;

    mapping(address => bool) public operators;
    uint32 public blockHeaderLength = 137;

    bytes32 public hashOfLastSubmittedBlock = keccak256("BankexFoundation");
    uint256 public lastEthBlockNumber = block.number;
    uint256 public depositCounterInBlock = 0;

    uint256 public DepositWithdrawCollateral = 0;
    uint256 public WithdrawCollateral = 0;
    uint256 public constant DepositWithdrawDelay = (72 hours);
    uint256 public constant WithdrawDelay = (168 hours);
    uint256 public constant ExitDelay = (336 hours);

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    uint256 constant SignatureLength = 65;
    uint256 constant BlockNumberLength = 4;
    uint256 constant TxNumberLength = 4;
    uint256 constant TxTypeLength = 1;
    uint256 constant TxOutputNumberLength = 1;
    uint256 constant PreviousHashLength = 32;
    uint256 constant MerkleRootHashLength = 32;
    bytes constant PersonalMessagePrefixBytes = "\x19Ethereum Signed Message:\n";
    uint256 constant PreviousBlockPersonalHashLength = BlockNumberLength +
                                                    TxNumberLength +
                                                    PreviousHashLength +
                                                    MerkleRootHashLength +
                                                    SignatureLength;
    uint256 constant NewBlockPersonalHashLength = BlockNumberLength +
                                                    TxNumberLength +
                                                    PreviousHashLength +
                                                    MerkleRootHashLength;

    mapping (uint256 => uint256) public transactionsSpendingRecords;

    event Debug(bool indexed _success, bytes32 indexed _b, address indexed _signer);
    event DebugUint(uint256 indexed _1, uint256 indexed _2, uint256 indexed _3);
    event SigEvent(address indexed _signer, bytes32 indexed _r, bytes32 indexed _s);

    function PlasmaChallenges(address _priorityQueue, address _blockStorage) public {
        require(_priorityQueue != address(0));
        require(_blockStorage != address(0));
        exitQueue = PriorityQueueInterface(_priorityQueue);
        blockStorage = PlasmaBlockStorageInterface(_blockStorage);
        operators[msg.sender] = true;
    }

    function setOperator(address _op, bool _status) public returns (bool success) {
        require(msg.sender == owner);
        operators[_op] = _status;
        return true;
    }

    function setChallenger(address _challenger) public returns (bool success) {
        require(msg.sender == owner);
        require(_challenger != address(0));
        challengesContract = _challenger;
        return true;
    }

// ----------------------------------
// Deposit related functions

    uint8 constant DepositStatusNoRecord = 0;
    uint8 constant DepositStatusDeposited = 1;
    uint8 constant DepositStatusWithdrawStarted = 2;
    uint8 constant DepositStatusWithdrawCompleted = 3;
    uint8 constant DepositStatusDepositConfirmed = 4;


    struct DepositRecord {
        address from;
        uint8 status;
        bool hasCollateral;
        uint256 amount;
        uint256 withdrawStartedAt;
    }

    event DepositEvent(address indexed _from, uint256 indexed _amount, uint256 indexed _depositIndex);
    event DepositWithdrawStartedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawChallengedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawCompletedEvent(uint256 indexed _depositIndex);

    mapping(uint256 => DepositRecord) public depositRecords;
    mapping(address => uint256[]) public allDepositRecordsForUser;

// ----------------------------------
// Withdraw related functions

    uint8 constant WithdrawStatusNoRecord = 0;
    uint8 constant WithdrawStatusStarted = 1;
    uint8 constant WithdrawStatusChallenged = 2;
    uint8 constant WithdrawStatusCompleted = 3;
    uint8 constant WithdrawStatusRejected = 4;

    struct WithdrawRecord {
        uint32 blockNumber;
        uint32 txNumberInBlock;
        uint8 outputNumberInTX;
        uint8 status;
        bool isExpress;
        bool hasCollateral;
        address beneficiary;
        uint256 amount;
        uint256 timestamp;
    }

    event WithdrawStartedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event WithdrawRequestAcceptedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawFinalizedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event ExitStartedEvent(address indexed _from,
                            uint256 indexed _priority);

    mapping(uint256 => WithdrawRecord) public withdrawRecords;
    mapping(address => uint256[]) public allWithdrawRecordsForUser;

    function populateWithdrawRecordFromOutput(BankexPlasmaTransaction.TransactionOutput memory _output, uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX, bool _setCollateral) internal returns (WithdrawRecord storage record, uint256 withdrawIndex) {
        withdrawIndex = BankexPlasmaTransaction.makeTransactionIndex(_blockNumber, _txNumberInBlock, _outputNumberInTX);
        // withdrawIndex = withdrawIndex + (block.number << 128);
        record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusNoRecord);
        record.status = WithdrawStatusStarted;
        record.isExpress = false;
        record.hasCollateral = _setCollateral;
        record.beneficiary = _output.recipient;
        record.amount = _output.amount;
        record.timestamp = now;
        record.blockNumber = _blockNumber;
        record.txNumberInBlock = _txNumberInBlock;
        record.outputNumberInTX = _outputNumberInTX;
        return (record, withdrawIndex);
    }
// ----------------------------------
// Double-spend related functions

    event DoubleSpendProovedEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);
    event SpendAndWithdrawProovedEvent(uint256 indexed _txIndex, uint256 indexed _withdrawIndex);

// two transactions spend the same output
    function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1,
                            uint8 _inputNumber1,
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2,
                            uint8 _inputNumber2,
                            bytes _plasmaTransaction2,
                            bytes _merkleProof2) public returns (bool success) {
        require(!plasmaErrorFound);
        uint256 index1 = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _inputNumber1);
        uint256 index2 = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _inputNumber2);
        require(index1 != index2);
        require(checkActualDoubleSpendProof(_plasmaBlockNumber1,
                            _plasmaTxNumInBlock1,
                            _inputNumber1,
                            _plasmaTransaction1,
                            _merkleProof1,
                            _plasmaBlockNumber2,
                            _plasmaTxNumInBlock2,
                            _inputNumber2,
                            _plasmaTransaction2,
                            _merkleProof2));
        plasmaErrorFound = true;
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            lastValidBlock = uint256(_plasmaBlockNumber2);
        } else {
            lastValidBlock = uint256(_plasmaBlockNumber1);
        }
        return true;
    }

    function checkActualDoubleSpendProof(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1,
                            uint8 _inputNumber1,
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2,
                            uint8 _inputNumber2,
                            bytes _plasmaTransaction2,
                            bytes _merkleProof2) public view returns (bool success) {
        var (signer1, input1) = getTXinputDetailsFromProof(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _inputNumber1, _plasmaTransaction1, _merkleProof1);
        var (signer2, input2) = getTXinputDetailsFromProof(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _inputNumber2, _plasmaTransaction2, _merkleProof2);
        require(signer1 != address(0));
        require(signer2 != address(0));
        require(signer1 == signer2);
        require(input1.blockNumber == input2.blockNumber);
        require(input1.txNumberInBlock == input2.txNumberInBlock);
        require(input1.outputNumberInTX == input2.outputNumberInTX);
        return true;
    }

// transaction output is withdrawn and spent in Plasma chain
    function proveSpendAndWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock,
                            uint8 _inputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof,
                            uint256 _withdrawIndex //references withdraw
                            ) public returns (bool success) {
        require(!plasmaErrorFound);
        uint256 txIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusCompleted);
        var (signer, input) = getTXinputDetailsFromProof(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber, _plasmaTransaction, _merkleProof);
        require(signer != address(0));
        require(input.blockNumber == record.blockNumber);
        require(input.txNumberInBlock == record.txNumberInBlock);
        require(input.outputNumberInTX == record.outputNumberInTX);
        SpendAndWithdrawProovedEvent(txIndex, _withdrawIndex);
        plasmaErrorFound = true;
        lastValidBlock = uint256(_plasmaBlockNumber);
        return true;
    }

// ----------------------------------
// Prove unlawful funding transactions on Plasma

    event FundingWithoutDepositEvent(uint256 indexed _txIndex, uint256 indexed _depositIndex);
    event DoubleFundingEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);

function proveFundingWithoutDeposit(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(!plasmaErrorFound);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        require(operators[TX.sender]);
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[0];
        BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[0];
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        uint256 depositIndex = input.amount;
        uint256 transactionIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        DepositRecord storage record = depositRecords[depositIndex];
        if (record.status == DepositStatusNoRecord) {
            plasmaErrorFound = true;
            lastValidBlock = uint256(_plasmaBlockNumber);
            return true;
        } else if (record.amount != output.amount || record.from != output.recipient) {
            plasmaErrorFound = true;
            lastValidBlock = uint256(_plasmaBlockNumber);
            return true;
        }
        revert();
        return false;
    }

    //prove double funding of the same

    function proveDoubleFunding(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1,
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2,
                            bytes _plasmaTransaction2,
                            bytes _merkleProof2) public returns (bool success) {
        require(!plasmaErrorFound);
        var (signer1, depositIndex1, transactionIndex1) = getFundingTXdetailsFromProof(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _plasmaTransaction1, _merkleProof1);
        var (signer2, depositIndex2, transactionIndex2) = getFundingTXdetailsFromProof(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _plasmaTransaction2, _merkleProof2);
        require(checkDoubleFundingFromInternal(signer1, depositIndex1, transactionIndex1, signer2, depositIndex2, transactionIndex2));
        plasmaErrorFound = true;
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            lastValidBlock = uint256(_plasmaBlockNumber2);
        } else {
            lastValidBlock = uint256(_plasmaBlockNumber1);
        }
        return true;
    }

    function checkDoubleFundingFromInternal(address signer1,
                                            uint256 depositIndex1,
                                            uint256 transactionIndex1,
                                            address signer2,
                                            uint256 depositIndex2,
                                            uint256 transactionIndex2) internal view returns (bool) {
        require(operators[signer1]);
        require(operators[signer2]);
        require(depositIndex1 == depositIndex2);
        require(transactionIndex1 != transactionIndex2);
        return true;
    }

// Prove invalid ownership in split or merge, or balance breaking inside a signle transaction or between transactions

// Balance breaking in TX
    function proveBalanceBreaking(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(!plasmaErrorFound);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(!isWellFormedTransaction(_plasmaTransaction));
        plasmaErrorFound = true;
        lastValidBlock = _plasmaBlockNumber;
        return true;
    }

// Prove that either amount of the input doesn't match the amount of the output, or spender of the output didn't have an ownership


// IMPORTANT Allow plasma operator to make merges on behalf of the users, in this case merge transaction MUST have 1 output that belongs to owner of original outputs
// Only operator have a power for such merges
    function proveBalanceOrOwnershipBreakingBetweenInputAndOutput(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            uint32 _plasmaTxNumInBlock,
                            bytes _plasmaTransaction,
                            bytes _merkleProof,
                            uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint32 _originatingPlasmaTxNumInBlock,
                            bytes _originatingPlasmaTransaction,
                            bytes _originatingMerkleProof,
                            uint256 _inputOfInterest
                            ) public returns(bool success) {
        require(!plasmaErrorFound);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_originatingPlasmaBlockNumber), _originatingPlasmaTransaction, _originatingMerkleProof));
        bool breaking = checkRightfullInputOwnershipAndBalance(_plasmaTransaction, _originatingPlasmaTransaction, _originatingPlasmaBlockNumber, _inputOfInterest);
        require(breaking);
        plasmaErrorFound = true;
        lastValidBlock = _plasmaBlockNumber;
        return true;
    }

    function checkRightfullInputOwnershipAndBalance(bytes _spendingTXbytes, bytes _originatingTXbytes, uint32 _originatingPlasmaBlockNumber, uint256 _inputNumber) internal view returns (bool isValid) {
        BankexPlasmaTransaction.PlasmaTransaction memory _spendingTX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_spendingTXbytes);
        BankexPlasmaTransaction.PlasmaTransaction memory _originatingTX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_originatingTXbytes);
        require(_spendingTX.inputs[_inputNumber].blockNumber == _originatingPlasmaBlockNumber);
        require(_spendingTX.inputs[_inputNumber].txNumberInBlock == _originatingTX.txNumberInBlock);
        if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].amount != _spendingTX.inputs[0].amount) {
            return false;
        }
        if (_spendingTX.txType == TxTypeSplit) {
            if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.sender) {
                return false;
            }
        } else if (_spendingTX.txType == TxTypeSplit) {
            if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.sender) {
                if (!operators[_spendingTX.sender]) {
                    return false;
                }
                if (_spendingTX.outputs.length != 1) {
                    return false;
                }
                if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.outputs[0].recipient) {
                    return false;
                }
            }
        }
        return true;
    }


// ----------------------------------
// Convenience functions

    function isWellFormedTransaction(bytes _plasmaTransaction) public view returns (bool isWellFormed) {
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        if (TX.sender == address(0)) {
            return false;
        }
        uint256 balance = 0;
        uint8 counter = 0;
        if (TX.txType == TxTypeFund) {
            return true;
        } else if (TX.txType == TxTypeSplit || TX.txType == TxTypeMerge) {
            for (counter = 0; counter < TX.inputs.length; counter++) {
                balance += TX.inputs[counter].amount;
            }
            for (counter = 0; counter < TX.outputs.length; counter++) {
                balance += TX.outputs[counter].amount;
            }
            if (balance != 0) {
                return false;
            }
            return true;
        }
        return false;
    }

    function getTXinputDetailsFromProof(uint32 _plasmaBlockNumber,
                            uint32 _plasmaTxNumInBlock,
                            uint8 _inputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) internal view returns (address signer, BankexPlasmaTransaction.TransactionInput memory input) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType != TxTypeFund);
        require(TX.sender != address(0));
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        input = TX.inputs[uint256(_inputNumber)];
        return (TX.sender, input);
    }

    function getFundingTXdetailsFromProof(uint32 _plasmaBlockNumber,
                            uint32 _plasmaTxNumInBlock,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) internal view returns (address signer, uint256 depositIndex, uint256 transactionIndex) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        BankexPlasmaTransaction.TransactionInput memory auxInput = TX.inputs[0];
        require(auxInput.blockNumber == 0);
        require(auxInput.txNumberInBlock == 0);
        require(auxInput.outputNumberInTX == 0);
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        depositIndex = auxInput.amount;
        transactionIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        return (TX.sender, depositIndex, transactionIndex);
    }
}
