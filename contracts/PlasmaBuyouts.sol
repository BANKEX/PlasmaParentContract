pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

contract PlasmaBuyouts {
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
    uint256 public constant ShowMeTheInputChallengeDelay = (72 hours);
    uint256 public constant WithdrawDelay = (168 hours);
    uint256 public constant ExitDelay = (336 hours);

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    mapping (uint256 => uint256) public transactionsSpendingRecords; // output index => input index

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
        uint32 expectedBlockNumber;
        uint32 expectedTransactionNumber;
        uint8 expectedOutputNumber;
        uint8 status;
        uint64 timestamp;
    }

    mapping(uint256 => ShowInputChallenge) public showInputChallengeStatuses; //input index => challenge

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
        operatorsBond = msg.value;
    }

    function setOperator(address _op, uint256 _status) public returns (bool success) {
        require(msg.sender == owner);
        return blockStorage.setOperator(_op, _status);
    }

    function offerOutputBuyout(uint256 _withdrawIndex, address _beneficiary) public payable returns (bool success) {
        require(msg.value > 0);
        require(_beneficiary != address(0));
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        WithdrawBuyoutOffer storage offer = withdrawBuyoutOffers[_withdrawIndex];
        emit WithdrawBuyoutOffered(_withdrawIndex, _beneficiary, msg.value);
        require(!offer.accepted);
        address oldFrom = offer.from;
        uint256 oldAmount = offer.amount;
        require(msg.value > oldAmount);
        offer.from = _beneficiary;
        offer.amount = msg.value;
        if (oldFrom != address(0)) {
            oldFrom.transfer(oldAmount);
        }
        return true;
    }

    function acceptBuyoutOffer(uint256 _withdrawIndex) public returns (bool success) {
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        WithdrawBuyoutOffer storage offer = withdrawBuyoutOffers[_withdrawIndex];
        require(offer.from != address(0));
        require(!offer.accepted);
        address oldBeneficiary = record.beneficiary;
        uint256 offerAmount = offer.amount;
        record.beneficiary = offer.from;
        offer.accepted = true;
        // delete withdrawBuyoutOffers[_withdrawIndex];
        emit WithdrawBuyoutAccepted(_withdrawIndex, record.beneficiary); 
        oldBeneficiary.transfer(offerAmount);
        return true;
    }

    function returnExpiredBuyoutOffer(uint256 _withdrawIndex) public returns (bool success) {
        // WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        WithdrawBuyoutOffer storage offer = withdrawBuyoutOffers[_withdrawIndex];
        require(!offer.accepted);
        // require(record.status != WithdrawStatusStarted || (block.timestamp >= record.timestamp + WithdrawDelay));
        address oldFrom = offer.from;
        uint256 oldAmount = offer.amount;
        require(msg.sender == oldFrom);
        delete withdrawBuyoutOffers[_withdrawIndex];
        if (oldFrom != address(0)) {
            oldFrom.transfer(oldAmount);
        }
        return true;
    }

// ----------------------------------

    function() external payable{
        address callee = challengesContract;
        assembly {
            let memoryPointer := mload(0x40)
            calldatacopy(memoryPointer, 0, calldatasize)
            let newFreeMemoryPointer := add(memoryPointer, calldatasize)
            mstore(0x40, newFreeMemoryPointer)
            let retVal := delegatecall(sub(gas, 10000), callee, memoryPointer, calldatasize, newFreeMemoryPointer, 0x40)
            let retDataSize := returndatasize
            returndatacopy(newFreeMemoryPointer, 0, retDataSize)
            switch retVal case 0 { revert(0,0) } default { return(newFreeMemoryPointer, retDataSize) }
        }
    }

}

