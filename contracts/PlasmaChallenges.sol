pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

contract PlasmaChallenges {
    using BankexPlasmaTransaction for BankexPlasmaTransaction.PlasmaTransaction;

// begining of storage declaration

    bool public plasmaErrorFound;
    uint32 public lastValidBlock;
    uint256 public operatorsBond;

    PriorityQueueInterface public exitQueue;
    PlasmaBlockStorageInterface public blockStorage;
    address public challengesContract;
    address public buyoutsContract;
    address public owner = msg.sender;

    int256 public totalAmountDeposited;
    int256 public amountPendingExit;

    uint256 public depositCounter;

    uint256 public DepositWithdrawCollateral = 50000000000000000;
    uint256 public WithdrawCollateral = 50000000000000000;
    uint256 public constant DepositWithdrawDelay = (72 hours);
    uint256 public constant InputChallangesDelay = (168 hours);
    uint256 public constant OutputChallangesDelay = (168 hours);
    uint256 public constant ExitDelay = (336 hours);

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    // deposits

    uint8 constant DepositStatusNoRecord = 0; // no deposit
    uint8 constant DepositStatusDeposited = 1; // deposit has happened
    uint8 constant DepositStatusWithdrawStarted = 2; // user withdraws a deposit
    uint8 constant DepositStatusWithdrawCompleted = 3; // used has withdrawn a deposit
    uint8 constant DepositStatusDepositConfirmed = 4; // a transaction with a deposit was posted


    struct DepositRecord {
        address from;
        uint8 status;
        bool hasCollateral;
        uint256 amount;
        uint256 withdrawStartedAt;
    }

    event ErrorFoundEvent(uint256 indexed _lastValidBlockNumber);

    event DepositEvent(address indexed _from, uint256 indexed _amount, uint256 indexed _depositIndex);
    event DepositWithdrawStartedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawChallengedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawCompletedEvent(uint256 indexed _depositIndex);

    mapping(uint256 => DepositRecord) public depositRecords;
    mapping(address => uint256[]) public allDepositRecordsForUser;

    struct ExitBuyoutOffer {
        uint256 amount;
        address from;
        bool accepted;
    }

    event WithdrawRequestAcceptedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawChallengedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawFinalizedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event ExitStartedEvent(address indexed _from,
                            uint256 indexed _priority,
                            uint256 indexed _withdrawIndex);
    event WithdrawBuyoutOffered(uint256 indexed _withdrawIndex,
                                address indexed _from,
                                uint256 indexed _buyoutAmount);
    event WithdrawBuyoutAccepted(uint256 indexed _withdrawIndex,
                                address indexed _from);    

    mapping(address => uint256[]) public allExitsForUser;
    mapping(uint72 => ExitBuyoutOffer) public exitBuyoutOffers;

    uint8 constant UTXOstatusNull = 0;
    uint8 constant UTXOstatusUnspent = 1;
    uint8 constant UTXOstatusSpent = 2;

    struct UTXO {
        uint32 originatingBlockNumber;
        uint32 originatingTransactionNumber;
        uint8 originatingOutputNumber;
        uint72 spendingTransactionIndex;
        uint8 utxoStatus;
        bool amountAndOwnerConfirmed;
        bool pendingExit;
        bool succesfullyWithdrawn;
        address collateralHolder;
        address originalOwner;
        address boughtBy;
        uint256 value;
        uint64 dateExitAllowed;
    }

    uint8 constant PublishedTXstatusNull = 0;
    uint8 constant PublishedTXstatusWaitingForInputChallenges = 1;
    uint8 constant PublishedTXstatusWaitingForOutputChallenges = 2;

    struct Transaction {
        bool isCanonical;
        uint72 priority;
        uint8 status;
        uint32 blockNumber;
        uint32 transactionNumber;
        uint8 transactionType;
        uint72[] inputIndexes;
        uint72[] outputIndexes;
        uint64 datePublished;
        address sender;
    }

    mapping(uint72 => UTXO) public publishedUTXOs;
    mapping(uint72 => Transaction) public publishedTransactions;

    event InputIsPublished(uint72 indexed _index);
    event OutputIsPublished(uint72 indexed _index);
    event TransactionIsPublished(uint64 indexed _index);
// end of storage declarations ---------------------------


    constructor(address _priorityQueue, address _blockStorage) public payable {
        require(_priorityQueue != address(0));
        require(_blockStorage != address(0));
        exitQueue = PriorityQueueInterface(_priorityQueue);
        blockStorage = PlasmaBlockStorageInterface(_blockStorage);
        operatorsBond = msg.value;
    }

    function addTotalDeposited(int256 _am) internal {
        totalAmountDeposited = totalAmountDeposited + _am;
    }

    function addTotalPendingExit(int256 _am) internal {
        amountPendingExit = amountPendingExit + _am;
    }

    function setErrorAndLastFoundBlock(uint32 _invalidBlockNumber, bool _transferReward, address _payTo) internal returns (bool success) {
        if (!plasmaErrorFound) {
            plasmaErrorFound = true;
        }
        if (lastValidBlock == 0) {
            lastValidBlock = _invalidBlockNumber-1;
        } else {
            if(lastValidBlock >= _invalidBlockNumber) {
                lastValidBlock = _invalidBlockNumber-1;
            }
        }
        blockStorage.incrementWeekOldCounter();
        emit ErrorFoundEvent(lastValidBlock);
        if (operatorsBond != 0) {
            uint256 bond = operatorsBond;
            operatorsBond = 0;
            if (_transferReward) {
                address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF).transfer(bond / 2);
                _payTo.transfer(bond / 2);
            }
        }
        return true;
    }
// ----------------------------------

    function startDepositWithdraw(uint256 depositIndex) public payable returns (bool success) {
        //require(block.number >= (depositIndex >> 32) + 500);
        require(msg.value == DepositWithdrawCollateral);
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusDeposited);
        require(record.from == msg.sender);
        record.status = DepositStatusWithdrawStarted;
        record.withdrawStartedAt = block.timestamp;
        record.hasCollateral = true;
        addTotalPendingExit(int256(record.amount));
        emit DepositWithdrawStartedEvent(depositIndex);
        return true;
    }

    function finalizeDepositWithdraw(uint256 depositIndex) public returns (bool success) {
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusWithdrawStarted);
        require(block.timestamp >= record.withdrawStartedAt + DepositWithdrawDelay);
        record.status = DepositStatusWithdrawCompleted;
        emit DepositWithdrawCompletedEvent(depositIndex);
        uint256 toSend = record.amount;
        if (record.hasCollateral) {
            toSend += DepositWithdrawCollateral;
        }
        addTotalDeposited(-int256(record.amount));
        addTotalPendingExit(-int256(record.amount));
        record.from.transfer(toSend);
        return true;
    }

    function challengeDepositWithdraw(
        uint256 depositIndex,
        uint32 _plasmaBlockNumber,
        bytes _plasmaTransaction,
        bytes _merkleProof) 
        public 
        returns (bool success) {
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusWithdrawStarted);
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(TX.txType == TxTypeFund);
        require(blockStorage.isOperator(TX.sender));
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[0];
        BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[0];
        require(output.recipient == record.from);
        require(output.amount == record.amount);
        require(input.amount == depositIndex);
        record.status = DepositStatusDepositConfirmed;
        emit DepositWithdrawChallengedEvent(depositIndex);
        addTotalPendingExit(-int256(record.amount));
        if (record.hasCollateral) {
            msg.sender.transfer(DepositWithdrawCollateral);
        }
        return true;
    }

// ----------------------------------


// ----------------------------------
// Double-spend related functions

// two transactions spend the same output
    function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint8 _inputNumber1,
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint8 _inputNumber2,
                            bytes _plasmaTransaction2,
                            bytes _merkleProof2) public returns (bool success) {
        uint256 index1;
        uint256 index2;
        address signer1;
        address signer2;
        BankexPlasmaTransaction.TransactionInput memory input1;
        BankexPlasmaTransaction.TransactionInput memory input2;
        (signer1, input1, index1) = getTXinputDetailsFromProof(_plasmaBlockNumber1, _inputNumber1, _plasmaTransaction1, _merkleProof1);
        (signer2, input2, index2) = getTXinputDetailsFromProof(_plasmaBlockNumber2, _inputNumber2, _plasmaTransaction2, _merkleProof2);
        require(index1 != index2);
        require(signer1 != address(0));
        require(signer1 == signer2);
        require(input1.blockNumber == input2.blockNumber);
        require(input1.txNumberInBlock == input2.txNumberInBlock);
        require(input1.outputNumberInTX == input2.outputNumberInTX);
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            setErrorAndLastFoundBlock(_plasmaBlockNumber2, true, msg.sender);
        } else {
            setErrorAndLastFoundBlock(_plasmaBlockNumber1, true, msg.sender);
        }
        return true;
    }

// transaction output is withdrawn and spent in Plasma chain
    // function proveSpendAndWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
    //                         uint8 _inputNumber,
    //                         bytes _plasmaTransaction,
    //                         bytes _merkleProof,
    //                         uint256 _withdrawIndex //references withdraw
    //                         ) public returns (bool success) {
    //     // uint256 txIndex = BankexPlasmaTransaction.makeInputOrOutputIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
    //     WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
    //     require(record.status == WithdrawStatusCompleted);
    //     address signer;
    //     BankexPlasmaTransaction.TransactionInput memory input;
    //     uint256 index;
    //     (signer, input, index) = getTXinputDetailsFromProof(_plasmaBlockNumber, _inputNumber, _plasmaTransaction, _merkleProof);
    //     require(signer != address(0));
    //     require(input.blockNumber == record.blockNumber);
    //     require(input.txNumberInBlock == record.txNumberInBlock);
    //     require(input.outputNumberInTX == record.outputNumberInTX);
    //     setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
    //     return true;
    // }

function proveInvalidDeposit(uint32 _plasmaBlockNumber, //references and proves transaction
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
        require(TX.txType == TxTypeFund);
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[0];
        BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[0];
        uint256 depositIndex = input.amount;
        // uint256 transactionIndex = BankexPlasmaTransaction.makeInputOrOutputIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        DepositRecord storage record = depositRecords[depositIndex];
        if (record.status == DepositStatusNoRecord || record.amount != output.amount || record.from != output.recipient) {
            setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
            return true;
        }
        revert();
        return false;
    }

    //prove double funding of the same

    function proveDoubleFunding(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            bytes _plasmaTransaction2,
                            bytes _merkleProof2) public returns (bool success) {
        address signer1;
        uint256 depositIndex1;
        uint256 transactionIndex1;
        address signer2;
        uint256 depositIndex2;
        uint256 transactionIndex2;
        (signer1, depositIndex1, transactionIndex1) = getFundingTXdetailsFromProof(_plasmaBlockNumber1, _plasmaTransaction1, _merkleProof1);
        (signer2, depositIndex2, transactionIndex2) = getFundingTXdetailsFromProof(_plasmaBlockNumber2, _plasmaTransaction2, _merkleProof2);
        require(blockStorage.isOperator(signer1));
        require(blockStorage.isOperator(signer2));
        require(depositIndex1 == depositIndex2);
        require(transactionIndex1 != transactionIndex2);
        // require(checkDoubleFundingFromInternal(signer1, depositIndex1, transactionIndex1, signer2, depositIndex2, transactionIndex2));
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            setErrorAndLastFoundBlock(_plasmaBlockNumber2, true, msg.sender);
        } else {
            setErrorAndLastFoundBlock(_plasmaBlockNumber1, true, msg.sender);
        }
        return true;
    }

    // function checkDoubleFundingFromInternal(address signer1,
    //                                         uint256 depositIndex1,
    //                                         uint256 transactionIndex1,
    //                                         address signer2,
    //                                         uint256 depositIndex2,
    //                                         uint256 transactionIndex2) internal view returns (bool) {
    //     require(blockStorage.isOperator(signer1));
    //     require(blockStorage.isOperator(signer2));
    //     require(depositIndex1 == depositIndex2);
    //     require(transactionIndex1 != transactionIndex2);
    //     return true;
    // }

// Prove invalid transaction (malformed) in the block
// Prove invalid ownership in split or merge, or balance breaking inside a signle transaction or between transactions

    function proveInvalidTransaction(uint32 _plasmaBlockNumber, //references and proves transaction
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(!isWellFormedTransaction(_plasmaTransaction));
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }

// Prove that transaction in block references a block in future

    function proveReferencingInvalidBlock(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            uint8 _plasmaInputNumberInTx,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.inputs[_plasmaInputNumberInTx].blockNumber >= _plasmaBlockNumber);
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }

// Prove referencing a transaction that has a number larger, than number of transactions in block being referenced

    function proveReferencingInvalidTransactionNumber(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            uint8 _plasmaInputNumberInTx,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
        BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[_plasmaInputNumberInTx];
        uint32 blockNumber = input.blockNumber;
        uint32 numberOfTransactionsInBlock = blockStorage.getNumberOfTransactions(blockNumber);
        require(input.txNumberInBlock >= numberOfTransactionsInBlock);
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }

// Prove that block inside itself has a transaction with a number larger, than number of transactions in block

    function proveBreakingTransactionNumbering(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
        uint32 numberOfTransactionsInBlock = blockStorage.getNumberOfTransactions(_plasmaBlockNumber);
        require(TX.txNumberInBlock >= numberOfTransactionsInBlock);
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }

// Prove two transactions in block with the same number

    function proveTwoTransactionsWithTheSameNumber(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            bytes _plasmaTransaction0,
                            bytes _merkleProof0,
                            bytes _plasmaTransaction1,
                            bytes _merkleProof1
                            ) public returns (bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction0, _merkleProof0));
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction1, _merkleProof1));
        BankexPlasmaTransaction.PlasmaTransaction memory TX0 = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction0);
        BankexPlasmaTransaction.PlasmaTransaction memory TX1 = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction1);
        require(isWellFormedDecodedTransaction(TX0));
        require(isWellFormedDecodedTransaction(TX1));
        require(TX0.txNumberInBlock == TX1.txNumberInBlock);
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }


// Prove that either amount of the input doesn't match the amount of the output, or spender of the output didn't have an ownership


// IMPORTANT Allow plasma operator to make merges on behalf of the users, in this case merge transaction MUST have 1 output that belongs to owner of original outputs
// Only operator have a power for such merges
    function proveBalanceOrOwnershipBreakingBetweenInputAndOutput(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            bytes _plasmaTransaction,
                            bytes _merkleProof,
                            uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
                            bytes _originatingPlasmaTransaction,
                            bytes _originatingMerkleProof,
                            uint256 _inputOfInterest
                            ) public returns(bool success) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_originatingPlasmaBlockNumber), _originatingPlasmaTransaction, _originatingMerkleProof));
        bool everythingIsFine = checkRightfulInputOwnershipAndBalance(_plasmaTransaction, _originatingPlasmaTransaction, _originatingPlasmaBlockNumber, _inputOfInterest);
        require(!everythingIsFine);
        setErrorAndLastFoundBlock(_plasmaBlockNumber, true, msg.sender);
        return true;
    }

    function checkRightfulInputOwnershipAndBalance(bytes _spendingTXbytes, bytes _originatingTXbytes, uint32 _originatingPlasmaBlockNumber, uint256 _inputNumber) internal view returns (bool isValid) {
        BankexPlasmaTransaction.PlasmaTransaction memory _spendingTX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_spendingTXbytes);
        BankexPlasmaTransaction.PlasmaTransaction memory _originatingTX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_originatingTXbytes);
        require(isWellFormedDecodedTransaction(_spendingTX));
        require(isWellFormedDecodedTransaction(_originatingTX));
        BankexPlasmaTransaction.TransactionInput memory input = _spendingTX.inputs[_inputNumber];
        require(input.blockNumber == _originatingPlasmaBlockNumber);
        require(input.txNumberInBlock == _originatingTX.txNumberInBlock);
        if (input.outputNumberInTX >= _originatingTX.outputs.length) {
            return false;
        }
        BankexPlasmaTransaction.TransactionOutput memory outputOfInterest = _originatingTX.outputs[uint256(input.outputNumberInTX)];
        if (outputOfInterest.amount != input.amount) {
            return false;
        }
        if (_spendingTX.txType == TxTypeSplit) {
            if (outputOfInterest.recipient != _spendingTX.sender) {
                return false;
            }
        } else if (_spendingTX.txType == TxTypeMerge) {
            if (outputOfInterest.recipient != _spendingTX.sender) {
                if (!blockStorage.isOperator(_spendingTX.sender)) {
                    return false;
                }
                if (_spendingTX.outputs.length != 1) {
                    return false;
                }
                if (outputOfInterest.recipient != _spendingTX.outputs[0].recipient) {
                    return false;
                }
                if (outputOfInterest.amount < _spendingTX.outputs[0].amount) {
                    return false;
                }
            }
            return true;
        } else if (_spendingTX.txType == TxTypeFund) {
            return true;
        }
        return true;
    }


// ----------------------------------
// Convenience functions

    function isWellFormedTransaction(bytes _plasmaTransaction) public view returns (bool isWellFormed) {
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        return isWellFormedDecodedTransaction(TX);
    }

    function isWellFormedDecodedTransaction(BankexPlasmaTransaction.PlasmaTransaction memory TX) internal view returns (bool isWellFormed) {
        if (TX.sender == address(0) || !TX.isWellFormed) {
            return false;
        }
        uint256 balance = 0;
        uint256 counter = 0;
        if (TX.txType == TxTypeFund) {
            if (TX.inputs.length != 1) {
                return false;
            }
            BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[0];
            return blockStorage.isOperator(TX.sender) && input.blockNumber == 0 && input.txNumberInBlock == 0 && input.outputNumberInTX == 0;
        } else if (TX.txType == TxTypeSplit || TX.txType == TxTypeMerge) {
            for (counter = 0; counter < TX.inputs.length; counter++) {
                balance += TX.inputs[counter].amount;
            }
            for (counter = 0; counter < TX.outputs.length; counter++) {
                balance -= TX.outputs[counter].amount;
            }
            if (balance != 0) {
                return false;
            }
            return true;
        }
        return false;
    }

    function getTXinputDetailsFromProof(uint32 _plasmaBlockNumber,
                            uint8 _inputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) internal view returns (address signer, BankexPlasmaTransaction.TransactionInput memory input, uint256 index) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
        require(TX.txType != TxTypeFund);
        require(TX.sender != address(0));
        require(TX.inputs.length > _inputNumber);
        input = TX.inputs[uint256(_inputNumber)];
        index = BankexPlasmaTransaction.makeInputOrOutputIndex(_plasmaBlockNumber, TX.txNumberInBlock, _inputNumber);
        return (TX.sender, input, index);
    }

    function getFundingTXdetailsFromProof(uint32 _plasmaBlockNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) internal view returns (address signer, uint256 depositIndex, uint256 outputIndex) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
        require(TX.txType == TxTypeFund);
        BankexPlasmaTransaction.TransactionInput memory auxInput = TX.inputs[0];
        require(auxInput.blockNumber == 0);
        require(auxInput.txNumberInBlock == 0);
        require(auxInput.outputNumberInTX == 0);
        depositIndex = auxInput.amount;
        outputIndex = BankexPlasmaTransaction.makeInputOrOutputIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        return (TX.sender, depositIndex, outputIndex);
    }
}
