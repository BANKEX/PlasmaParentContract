pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

interface OperatorCheckingInterface {
    function isOperator(address _operator) external view returns (bool);
    function canSignBlocks(address _operator) external view returns (bool);
}

contract CommonParent {
    using BankexPlasmaTransaction for BankexPlasmaTransaction.PlasmaTransaction;

// begining of storage declaration

    bool public plasmaErrorFound;
    uint32 public lastValidBlock;
    uint256 public operatorsBond;

    PriorityQueueInterface public exitQueue;
    PlasmaBlockStorageInterface public blockStorage;
    address public challengesContract;
    address public owner = msg.sender;
    int256 public totalAmountDeposited;
    int256 public amountPendingExit;

    mapping(address => OperatorStatus) public operators;
    enum OperatorStatus {Null, CanSignTXes, CanSignBlocks}

    uint256 public lastEthBlockNumber = block.number;
    uint256 public depositCounterInBlock;

    uint256 public DepositWithdrawCollateral;
    uint256 public WithdrawCollateral;
    uint256 public constant DepositWithdrawDelay = (72 hours);
    uint256 public constant ShowMeTheInputChallengeDelay = (72 hours);
    uint256 public constant WithdrawDelay = (168 hours);
    uint256 public constant ExitDelay = (336 hours);

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    mapping (uint256 => uint256) public transactionsSpendingRecords; // input index => output index

    // deposits

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

    event ErrorFoundEvent(uint256 indexed _lastValidBlockNumber);

    event DepositEvent(address indexed _from, uint256 indexed _amount, uint256 indexed _depositIndex);
    event DepositWithdrawStartedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawChallengedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawCompletedEvent(uint256 indexed _depositIndex);

    mapping(uint256 => DepositRecord) public depositRecords;
    mapping(address => uint256[]) public allDepositRecordsForUser;

// withdrawals

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
        uint8 numInputs;
        bool hasCollateral;
        address beneficiary;
        uint256 amount;
        uint256 timestamp;
    }

    struct WithdrawBuyoutOffer {
        address from;
        uint256 amount;
    }

    event WithdrawRequestAcceptedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawChallengedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawFinalizedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event ExitStartedEvent(address indexed _from,
                            uint256 indexed _priority);
    event WithdrawBuyoutOffered(uint256 indexed _withdrawIndex,
                                address indexed _from,
                                uint256 indexed _buyoutAmount);
    event WithdrawBuyoutAccepted(uint256 indexed _withdrawIndex,
                                address indexed _from);                            
    mapping(uint256 => WithdrawRecord) public withdrawRecords;
    mapping(address => uint256[]) public allWithdrawRecordsForUser;
    mapping(uint256 => WithdrawBuyoutOffer) public withdrawBuyoutOffers;

// interactive "Show me the input!" challenge

    uint8 constant ShowInputChallengeNoRecord = 0;
    uint8 constant ShowInputChallengeStarted = 1;
    uint8 constant ShowInputChallengeResponded = 2;
    uint8 constant ShowInputChallengeCompleted = 3;


    struct ShowInputChallenge {
        address from;
        uint32 inputBlockNumber;
        uint32 inputTransactionNumber;
        uint8 inputInputNumber;
        uint8 status;
        uint64 timestamp;
    }

    mapping(uint256 => ShowInputChallenge) public showInputChallengeStatuses;
    event ShowInputChallengeInitiatedEvent(address indexed _from,
                                uint256 indexed _inputIndex,
                                uint256 indexed _outputIndex);
    event ShowInputChallengeRespondedEvent(address indexed _from,
                                uint256 indexed _inputIndex,
                                uint256 indexed _outputIndex);
// end of storage declarations --------------------------- 

    constructor(address _priorityQueue, address _blockStorage) public payable {
        require(_priorityQueue != address(0));
        require(_blockStorage != address(0));
        exitQueue = PriorityQueueInterface(_priorityQueue);
        blockStorage = PlasmaBlockStorageInterface(_blockStorage);
        operators[msg.sender] = OperatorStatus.CanSignBlocks;
        operatorsBond = msg.value;
    }

    function setOperator(address _op, uint256 _status) public returns (bool success) {
        require(msg.sender == owner);
        OperatorStatus stat = operators[_op];
        OperatorStatus newStat = OperatorStatus(_status);
        if (stat == OperatorStatus.Null) {
            operators[_op] = newStat;
            return true;
        } else if (stat == OperatorStatus.CanSignTXes) {
            require(newStat == OperatorStatus.CanSignBlocks);
            operators[_op] = newStat;
            return true;
        } else if (stat == OperatorStatus.CanSignBlocks) {
            require(newStat == OperatorStatus.CanSignTXes);
            operators[_op] = newStat;
            return true;
        }
        revert();
    }

    function setChallenger(address _challenger) public returns (bool success) {
        require(msg.sender == owner);
        require(_challenger != address(0));
        require(challengesContract == address(0));
        challengesContract = _challenger;
        return true;
    }

    function setErrorAndLastFoundBlock(uint32 _lastValidBlock, bool _transferReward, address _payTo) internal returns (bool success) {
        if (!plasmaErrorFound) {
            plasmaErrorFound = true;
        }
        if (lastValidBlock == 0) {
            lastValidBlock = _lastValidBlock;
        } else {
            if(lastValidBlock > _lastValidBlock) {
                lastValidBlock = _lastValidBlock;
            }
        }
        emit ErrorFoundEvent(lastValidBlock);
        if (operatorsBond != 0) {
            uint256 bond = operatorsBond;
            operatorsBond = 0;
            if (_transferReward) {
                address(0xffffffffffffffffffffffffffffffffffffffff).transfer(bond / 2);
                _payTo.transfer(bond / 2);
            }
        }
        return true;
    }

    function isOperator(address _operator) public view returns (bool) {
        OperatorStatus stat = operators[_operator];
        return stat != OperatorStatus.Null;
    }

    function canSignBlocks(address _operator) public view returns (bool) {
        OperatorStatus stat = operators[_operator];
        return stat != OperatorStatus.CanSignBlocks;
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
            return isOperator(TX.sender) && input.blockNumber == 0 && input.txNumberInBlock == 0 && input.outputNumberInTX == 0;
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
                            uint32 _plasmaTxNumInBlock,
                            uint8 _inputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) internal view returns (address signer, BankexPlasmaTransaction.TransactionInput memory input) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(isWellFormedDecodedTransaction(TX));
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
