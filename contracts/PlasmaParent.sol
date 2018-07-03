pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

contract PlasmaParent {
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

    event ExitStartedEvent(address indexed _from,
                            uint72 indexed _priority,
                            uint72 indexed _index);
    event ExitStartedEvent(address indexed _from,
                            uint72 indexed _priority,
                            bytes22 indexed _partialHash);
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
        uint160 spendingTransactionIndex;
        uint8 utxoStatus;
        bool isLinkedToLimbo;
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
        bool isLimbo;
        uint72 priority;
        uint8 status;
        uint8 transactionType;
        uint72[] inputIndexes;
        uint72[] outputIndexes;
        uint8[] limboOutputIndexes;
        uint64 datePublished;
        address sender;
    }

    mapping(uint72 => UTXO) public publishedUTXOs;
    mapping(uint160 => Transaction) public publishedTransactions;
    mapping(uint160 => Transaction) public limboTransactions;
    mapping(uint176 => UTXO) public limboUTXOs;

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

    function setOperator(address _op, uint256 _status) public returns (bool success) {
        require(msg.sender == owner);
        return blockStorage.setOperator(_op, _status);
    }

    function setDelegates(address _challenger, address _buyouts) public returns (bool success) {
        require(msg.sender == owner);
        require(_challenger != address(0));
        require(_buyouts != address(0));
        require(buyoutsContract == address(0));
        require(challengesContract == address(0));
        buyoutsContract = _buyouts;
        challengesContract = _challenger;
        return true;
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

    function submitBlockHeaders(bytes _headers) public returns (bool success) {
        require(!plasmaErrorFound);
        return blockStorage.submitBlockHeaders(_headers);
    }

    function lastBlockNumber() public view returns (uint256 blockNumber) {
        return blockStorage.lastBlockNumber();
    }

    function hashOfLastSubmittedBlock() public view returns(bytes32) {
        return blockStorage.hashOfLastSubmittedBlock();
    }

    function addTotalDeposited(int256 _am) internal {
        totalAmountDeposited = totalAmountDeposited + _am;
    }

    function addTotalPendingExit(int256 _am) internal {
        amountPendingExit = amountPendingExit + _am;
    }

    function incrementWeekOldCounter() public {
        // require(!plasmaErrorFound);
        blockStorage.incrementWeekOldCounter();
    }

// ----------------------------------

// ----------------------------------
// Deposit related functions

    function deposit() payable public returns (bool success) {
        return depositFor(msg.sender);
    }

    function depositFor(address _for) payable public returns (bool success) {
        require(msg.value > 0);
        require(!plasmaErrorFound);
        uint256 size;
        assembly {
            size := extcodesize(_for)
        }
        if (size > 0) {
            revert();
        }
        uint256 depositIndex = depositCounter;
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusNoRecord);
        record.from = _for;
        record.amount = msg.value;
        record.status = DepositStatusDeposited;
        depositCounter = depositCounter + 1;
        emit DepositEvent(_for, msg.value, depositIndex);
        allDepositRecordsForUser[_for].push(depositIndex);
        addTotalDeposited(int256(msg.value));
        return true;
    }

// ----------------------------------

// someone has already published the transaction and you just want to exit one of the outputs
    function joinExit(
        uint32 _plasmaBlockNumber, // block with the transaction
        uint32 _plasmaTransactionNumber, // transaction number
        uint8 _outputNumber // outputNumber
    ) public payable returns(bool success) {
        // we join some CANONICAL transaction to exit
        uint64 transactionIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, _plasmaTransactionNumber);
        Transaction storage publishedTransaction = publishedTransactions[transactionIndex];
        uint72 publishedOutputIndex = publishedTransaction.outputIndexes[uint256(_outputNumber)];
        require(publishedOutputIndex != 0);
        require(publishedTransaction.isCanonical);
        UTXO storage utxo = publishedUTXOs[publishedOutputIndex];
        require(utxo.originalOwner == msg.sender);
        require(utxo.value != 0);
        require(msg.value == WithdrawCollateral);
        utxo.pendingExit = true;
        uint72 priorityModifier = publishedTransaction.priority;
        exitQueue.insert(priorityModifier, uint8(1), bytes22(publishedOutputIndex));
        allExitsForUser[msg.sender].push(publishedOutputIndex);
        emit ExitStartedEvent(msg.sender, priorityModifier, publishedOutputIndex);
        return true;
    }

    // function finalizeExits(uint256 _numOfExits) public returns (bool success) {
    //     uint256 toSend = 0;
    //     address beneficiary = address(0);
    //     for (uint i = 0; i < _numOfExits; i++) {
    //         (uint8 recordType, bytes22 index) = exitQueue.delMin();
    //         UTXO storage utxo;
    //         Transaction storage originatingTransaction;
    //         if (recordType == 1) {
    //             uint64 transactionIndex = uint64(index >> 8);
    //             originatingTransaction = publishedTransactions[transactionIndex];
    //             utxo = publishedUTXOs[originatingTransaction.outputIndexes[uint256(index % 256)]]
    //         } else if (recordType == 2) {

    //         } else {
    //             if (i == 0) {
    //                 revert();
    //             } else {
    //                 break;
    //             }
    //         }
    //         if (utxo.dateExitAllowed > nowStamp) {
    //             if (i == 0) {
    //                 revert();
    //             } else {
    //                 break;
    //             }
    //         }
    //         if (originatingTransaction.isCanonical && utxo.utxoStatus == UTXOstatusUnspent && utxo.value != 0 && utxo.pendingExit) {
    //             if (utxo.boughtBy != address(0)) {
    //                 beneficiary = utxo.boughtBy;
    //             } else {
    //                 beneficiary = utxo.originalOwner;
    //             }
    //             toSend = utxo.value + WithdrawCollateral;
    //             utxo.succesfullyWithdrawn = true;
    //             if (beneficiary != address(0)) {
    //                 beneficiary.transfer(toSend);
    //             }
    //         }
    //         if (exitQueue.currentSize() > 0) {
    //             (recordType, index) = exitQueue.delMin();
    //             utxo = publishedUTXOs[uint72(index)];
    //             transactionIndex = BankexPlasmaTransaction.makeTransactionIndex(utxo.originatingBlockNumber, utxo.originatingTransactionNumber);
    //             originatingTransaction = publishedTransactions[transactionIndex];
    //             toSend = 0;
    //             beneficiary = address(0);
    //         } else {
    //             break;
    //         }
    //     }
    //     return true;
    // }

    function attemptNormalExit(uint72 _index) internal returns (bool success){
        uint64 transactionIndex = uint64(_index >> 8);
        Transaction storage originatingTransaction = publishedTransactions[transactionIndex];
        if (!originatingTransaction.isCanonical) {
            return true;
        }
        UTXO storage utxo = publishedUTXOs[originatingTransaction.outputIndexes[uint256(_index % 256)]];
        if (utxo.dateExitAllowed > block.timestamp) {
            return false;
        }
        if (utxo.succesfullyWithdrawn) {
            return true;
        }
        if (utxo.utxoStatus == UTXOstatusUnspent && utxo.value != 0 && utxo.pendingExit) {
            address beneficiary;
            if (utxo.boughtBy != address(0)) {
                beneficiary = utxo.boughtBy;
            } else {
                beneficiary = utxo.originalOwner;
            }
            uint256 toSend = utxo.value + WithdrawCollateral;
            utxo.succesfullyWithdrawn = true;
            if (beneficiary != address(0)) {
                beneficiary.transfer(toSend);
            }
        }
        return true;
    }

    function attemptLimboExit(bytes22 _index) internal returns (bool success) {
        uint160 transactionHash = uint160(uint176(_index) >> 16);
        Transaction storage originatingTransaction = limboTransactions[transactionHash];
        if (!originatingTransaction.isCanonical) {
            return true;
        }
        UTXO storage utxo = limboUTXOs[uint176(_index)];
        if (utxo.dateExitAllowed > block.timestamp) {
            return false;
        }
        if (utxo.succesfullyWithdrawn) {
            return true;
        }
        if (utxo.utxoStatus == UTXOstatusUnspent && utxo.value != 0 && utxo.pendingExit) {
            address beneficiary;
            if (utxo.boughtBy != address(0)) {
                beneficiary = utxo.boughtBy;
            } else {
                beneficiary = utxo.originalOwner;
            }
            uint256 toSend = utxo.value + WithdrawCollateral;
            utxo.succesfullyWithdrawn = true;
            if (beneficiary != address(0)) {
                beneficiary.transfer(toSend);
            }
        }
        return true;
    }

    function collectInputsCollateral(uint64 _transactionIndex) public returns (bool success) {
        Transaction storage publishedTransaction = publishedTransactions[_transactionIndex];
        require(publishedTransaction.isCanonical);
        require(block.timestamp >= publishedTransaction.datePublished + InputChallangesDelay);
        uint256 totalToSend = 0;
        for (uint256 j = 0; j < publishedTransaction.inputIndexes.length; j++) {
            UTXO storage utxo = publishedUTXOs[publishedTransaction.inputIndexes[j]];
            if (utxo.collateralHolder == msg.sender) {
                totalToSend += WithdrawCollateral;
                delete utxo.collateralHolder;
            }
        }
        require(totalToSend > 0);
        msg.sender.transfer(totalToSend);
        return true;
    }

    function offerOutputBuyout(uint72 _utxoIndex, address _beneficiary) public payable returns (bool success) {
        require(msg.value > 0);
        require(_beneficiary != address(0));
        UTXO storage utxo = publishedUTXOs[_utxoIndex];
        require(utxo.utxoStatus == UTXOstatusUnspent);
        ExitBuyoutOffer storage offer = exitBuyoutOffers[_utxoIndex];
        emit WithdrawBuyoutOffered(_utxoIndex, _beneficiary, msg.value);
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

    function acceptBuyoutOffer(uint72 _utxoIndex) public returns (bool success) {
        UTXO storage utxo = publishedUTXOs[_utxoIndex];
        require(utxo.utxoStatus == UTXOstatusUnspent);
        ExitBuyoutOffer storage offer = exitBuyoutOffers[_utxoIndex];
        require(offer.from != address(0));
        require(!offer.accepted);
        address oldBeneficiary = utxo.originalOwner;
        uint256 offerAmount = offer.amount;
        utxo.boughtBy = offer.from;
        offer.accepted = true;
        emit WithdrawBuyoutAccepted(_utxoIndex, utxo.boughtBy); 
        oldBeneficiary.transfer(offerAmount);
        return true;
    }

    function returnExpiredBuyoutOffer(uint72 _utxoIndex) public returns (bool success) {
        // WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        ExitBuyoutOffer storage offer = exitBuyoutOffers[_utxoIndex];
        require(!offer.accepted);
        // require(record.status != WithdrawStatusStarted || (block.timestamp >= record.timestamp + WithdrawDelay));
        address oldFrom = offer.from;
        uint256 oldAmount = offer.amount;
        require(msg.sender == oldFrom);
        delete exitBuyoutOffers[_utxoIndex];
        if (oldFrom != address(0)) {
            oldFrom.transfer(oldAmount);
        }
        return true;
    }


// ----------------------------------

    function() external payable{
        address callee = buyoutsContract;
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
