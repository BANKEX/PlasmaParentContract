pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

contract PlasmaExitsProcessor {
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

//-----------------------------------

    //references and proves ownership on output of original transaction
    function startExit(
        uint32 _plasmaBlockNumber, // block with the transaction
        uint8 _outputNumber,    // output being exited
        bytes _plasmaTransaction, // transaction itself
        bytes _merkleProof) // proof
    public payable returns(bool success) {
        uint72[] memory detachedByInputs;
        uint72[] memory detachedByOutputs;
        uint160 transactionIndex;
        (success, detachedByInputs, detachedByOutputs, transactionIndex) = publishTransaction(_plasmaBlockNumber, _plasmaTransaction, _merkleProof);
        uint256 numChallengedInsAndOuts = 0;
        uint256 i;
        for (i = 0; i < detachedByInputs.length; i++) {
            if (detachedByInputs[i] != 0) {
                numChallengedInsAndOuts++;
            } else {
                break;
            }
        }
        for (i = 0; i < detachedByOutputs.length; i++) {
            if (detachedByOutputs[i] != 0) {
                numChallengedInsAndOuts++;
            } else {
                break;
            }
        }
        Transaction storage publishedTransaction = publishedTransactions[transactionIndex];
        require(publishedTransaction.isCanonical);
        uint72 publishedOutputIndex = publishedTransaction.outputIndexes[uint256(_outputNumber)];
        require(publishedOutputIndex != 0);
        UTXO storage utxo = publishedUTXOs[publishedOutputIndex];
        require(utxo.originalOwner == msg.sender);
        require(utxo.utxoStatus == UTXOstatusUnspent);
        utxo.pendingExit = true;
        uint72 priorityModifier = publishedTransaction.priority;
        if (_plasmaBlockNumber < blockStorage.weekOldBlockNumber()) {
            priorityModifier = uint72(blockStorage.weekOldBlockNumber() << (32 + 8));
        }
        publishedTransaction.priority = priorityModifier;
        // require(msg.value == WithdrawCollateral*(1+publishedTransaction.inputIndexes.length));
        require(utxo.dateExitAllowed == 0);
        utxo.dateExitAllowed = uint64(block.timestamp + InputChallangesDelay + OutputChallangesDelay);
        exitQueue.insert(priorityModifier, uint8(1), bytes22(publishedOutputIndex));
        allExitsForUser[msg.sender].push(publishedOutputIndex);
        emit ExitStartedEvent(msg.sender, priorityModifier, publishedOutputIndex);
        if (numChallengedInsAndOuts != 0) {
            msg.sender.transfer(WithdrawCollateral*numChallengedInsAndOuts);
        }
        return true;
    }

    function publishTransaction(
        uint32 _plasmaBlockNumber, 
        bytes _plasmaTransaction,
        bytes _merkleProof
        ) 
    public returns (bool success, uint72[] inputsAffected, uint72[] outputsAffected, uint160 transactionIndex) {
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.isWellFormed);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        if (TX.txType == TxTypeFund) {
            require(blockStorage.isOperator(TX.sender));
        }
        transactionIndex = uint160(BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock));
        Transaction storage publishedTransaction = publishedTransactions[transactionIndex];
        require(publishedTransaction.status == PublishedTXstatusNull);
        publishedTransaction.sender = TX.sender;
        publishedTransaction.datePublished = uint64(block.timestamp);
        publishedTransaction.transactionType = TX.txType;
        if (TX.txType == TxTypeFund) {
            DepositRecord storage depositRecord = depositRecords[TX.inputs[0].amount];
            require(depositRecord.status != DepositStatusNoRecord);
            require(depositRecord.status != DepositStatusWithdrawCompleted);
            require(TX.outputs[0].recipient == depositRecord.from);
            depositRecord.status = DepositStatusDepositConfirmed;
        }
        (publishedTransaction, inputsAffected) = workOnInputs(publishedTransaction, TX, transactionIndex);
        (publishedTransaction, outputsAffected) = workOnOutputs(publishedTransaction, TX, _plasmaBlockNumber);
        success = true;
        return;
    }

    function workOnInputs(
        Transaction storage publishedTransaction,
        BankexPlasmaTransaction.PlasmaTransaction memory TX,
        uint160 publishedTransactionIndex)
    internal returns(Transaction storage _publishedTransaction, uint72[] memory detachedInputs) {
        if (publishedTransaction.status == PublishedTXstatusNull) {
            uint72[] memory scratchSpace = new uint72[](4);
            detachedInputs = new uint72[](TX.inputs.length);
            bool clashOnTheInput;
            bool transactionIsNonCanonical;
            // uint72 inputOutputIndex; // scratchSpace[0]
            // uint72 transactionPriority; //scratchSpace[1]
            // uint256 i; // scratchSpace[2]
            // uint256 challangedInputIndex; 
            UTXO memory utxo;
            BankexPlasmaTransaction.TransactionInput memory txInput;
            // for every input check that it was never consumed by other input
            // simultaneously check if an UTXO was already posted, that owner and amount match
            for (scratchSpace[2] = 0; scratchSpace[2] < TX.inputs.length; scratchSpace[2]++) { 
                txInput = TX.inputs[scratchSpace[2]];
                scratchSpace[0] = BankexPlasmaTransaction.makeInputOrOutputIndex(txInput.blockNumber, txInput.txNumberInBlock, txInput.outputNumberInTX); // utxo index being refered
                utxo = publishedUTXOs[scratchSpace[0]];
                if (utxo.amountAndOwnerConfirmed) { // this utxo was already once published
                    if (utxo.originalOwner != TX.sender || utxo.value != txInput.amount) {
                        // such transaction should have never happened and can not produce any meaningful output
                        // keep it for further records, for example, to prevent next transaction to exit
                        revert();
                    } else { // owner and amount are legitimate
                        if (utxo.spendingTransactionIndex == 0) { // was never spent
                            utxo.spendingTransactionIndex = publishedTransactionIndex;
                            utxo.isLinkedToLimbo = publishedTransaction.isLimbo;
                            utxo.utxoStatus = UTXOstatusSpent;
                            utxo.collateralHolder = msg.sender;
                            publishedTransaction.inputIndexes.push(scratchSpace[0]);
                            // if (utxo.dateExitAllowed != 0) { // transaction started to exit, but was spent at some point
                            //     detachedInputs[uint256(scratchSpace[3])] = scratchSpace[0];
                            //     scratchSpace[3]++;
                            // }
                        } else {// was spent, check priorities and displace after we determine the full priority
                            clashOnTheInput = true;
                        }
                    }
                } else if (utxo.spendingTransactionIndex != 0) { // this means that utxo was published as an input only, so it's already "spent"
                    clashOnTheInput = true;
                } else { // utxo was never published so we write the data optimistically
                    utxo.originalOwner = TX.sender;
                    utxo.value = txInput.amount;
                    utxo.utxoStatus = UTXOstatusSpent;
                    utxo.collateralHolder = msg.sender;
                    utxo.spendingTransactionIndex = publishedTransactionIndex;
                    utxo.isLinkedToLimbo = publishedTransaction.isLimbo;
                }
                if (scratchSpace[1] == 0) { // set priority anyway
                    scratchSpace[1] = scratchSpace[0];
                } else if (scratchSpace[1] < scratchSpace[0]) { // transaction's inverse priority (so lower the better) 
                    scratchSpace[1] = scratchSpace[0]; // is the index of the YOUNGEST input (so with the HIGHEST block || tx || output number)
                }
                publishedUTXOs[scratchSpace[0]] = utxo;
                publishedTransaction.inputIndexes.push(scratchSpace[0]);
                emit InputIsPublished(scratchSpace[0]);
            } 
            // now we have determined the priority over all the inputs and can check for collisions
            // now we are sure that input matches an output or at least optimistic
            if (clashOnTheInput) { // loop again and check for priorities
                for (scratchSpace[2] = 0; scratchSpace[2] < TX.inputs.length; scratchSpace[2]++) { // for every input check that it was never published in another transaction
                    txInput = TX.inputs[scratchSpace[2]];
                    scratchSpace[0] = BankexPlasmaTransaction.makeInputOrOutputIndex(txInput.blockNumber, txInput.txNumberInBlock, txInput.outputNumberInTX);
                    utxo = publishedUTXOs[scratchSpace[0]];
                    if (utxo.spendingTransactionIndex == 0) {
                        continue;
                    }
                    Transaction storage previouslyPublishedTransaction = publishedTransactions[utxo.spendingTransactionIndex];
                    // detatch an input that was shown before
                    if (previouslyPublishedTransaction.priority > scratchSpace[1]) {
                        previouslyPublishedTransaction.isCanonical = false;
                        detachedInputs[uint256(scratchSpace[3])] = scratchSpace[0];
                        scratchSpace[3]++;
                        utxo.collateralHolder = msg.sender;
                        if (utxo.amountAndOwnerConfirmed) {
                            if (utxo.originalOwner != TX.sender || utxo.value != txInput.amount) {
                                transactionIsNonCanonical = true;
                            } else {
                                utxo.spendingTransactionIndex = publishedTransactionIndex;
                                utxo.isLinkedToLimbo = publishedTransaction.isLimbo;
                            }
                        }
                        else if (utxo.originalOwner != TX.sender || utxo.value != txInput.amount) {
                            utxo.originalOwner = TX.sender;
                            utxo.value = txInput.amount;
                            utxo.spendingTransactionIndex = publishedTransactionIndex;
                            utxo.isLinkedToLimbo = publishedTransaction.isLimbo;
                        }
                    } else { // priority is lower, so transaction is non-canonical
                        transactionIsNonCanonical = true;
                        // require(_isNonCanonical);
                    }
                }
            }
            publishedTransaction.isCanonical = !transactionIsNonCanonical;
            publishedTransaction.priority = scratchSpace[1];
            publishedTransaction.status = PublishedTXstatusWaitingForInputChallenges;
            // detachedInputs.length = uint256(scratchSpace[3]);
            return (publishedTransaction, detachedInputs);
        } else {
            // just return what we have
            return (publishedTransaction, detachedInputs);
        }
    }

    function workOnOutputs(
        Transaction storage publishedTransaction,
        BankexPlasmaTransaction.PlasmaTransaction memory TX,
        uint32 _plasmaBlockNumber)
    internal returns(Transaction storage _publishedTransaction, uint72[] memory detachedOutputs) {
        if (publishedTransaction.status == PublishedTXstatusWaitingForInputChallenges) {
            detachedOutputs = new uint72[](TX.outputs.length);
            // we should mark what outputs are not yet spent by other inputs already shown to the contract
            uint72[] memory scratchSpace = new uint72[](4);
            // uint72 inputOutputIndex; // scratchSpace[0]
            // uint72 transactionPriority; //scratchSpace[1]
            // uint256 i; // scratchSpace[2]
            // uint256 challangedInputIndex; 
            UTXO memory utxo;
            BankexPlasmaTransaction.TransactionOutput memory txOutput;
            // for every input check that it was never consumed by other input
            // simultaneously check if an UTXO was already posted, that owner and amount match
            for (scratchSpace[2] = 0; scratchSpace[2] < TX.outputs.length; scratchSpace[2]++) { 
                txOutput = TX.outputs[scratchSpace[2]];
                require(txOutput.outputNumberInTX == scratchSpace[2]); // check that numbering is correct. Not too important, but keep for now
                scratchSpace[0] = BankexPlasmaTransaction.makeInputOrOutputIndex(_plasmaBlockNumber, TX.txNumberInBlock, txOutput.outputNumberInTX); // index of created output
                utxo = publishedUTXOs[scratchSpace[0]];
                if (utxo.amountAndOwnerConfirmed) { // this utxo was already once published
                    // such output was already listed, so revert for now
                    revert();
                } else if (utxo.spendingTransactionIndex != 0 || utxo.utxoStatus == UTXOstatusSpent) { // this means that utxo was published as an input only, so it's already "spent"
                    //should check that is matches the spending input
                    if (utxo.originalOwner != txOutput.recipient || utxo.value != txOutput.amount) {
                        publishedTransaction.isCanonical = false;
                        detachedOutputs[uint256(scratchSpace[3])] = scratchSpace[0];
                        scratchSpace[3]++;
                        utxo.utxoStatus = UTXOstatusUnspent;
                        publishedTransaction.outputIndexes.push(scratchSpace[0]);
                    } else {
                        // spent correctly
                        utxo.utxoStatus = UTXOstatusSpent;
                        publishedTransaction.outputIndexes.push(scratchSpace[0]);
                    }
                } else { // utxo now available
                    utxo.originalOwner = txOutput.recipient;
                    utxo.value = txOutput.amount;
                    utxo.utxoStatus = UTXOstatusUnspent;
                    publishedTransaction.outputIndexes.push(scratchSpace[0]);
                }
                utxo.amountAndOwnerConfirmed = true;
                // detachedOutputs.length = uint256(scratchSpace[3]);
                publishedUTXOs[scratchSpace[0]] = utxo;
                emit OutputIsPublished(scratchSpace[0]);
            } 
            return (publishedTransaction, detachedOutputs);
        } else {
            revert();
            // should never happen
        }
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
