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
                            uint256 indexed _priority,
                            uint256 indexed _withdrawIndex);
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
                address(0xffffffffffffffffffffffffffffffffffffffff).transfer(bond / 2);
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
        require(!plasmaErrorFound);
        blockStorage.incrementWeekOldCounter();
    }

    function inputIsChallenged(uint32 blockNumber, uint32 txNumberInBlock, uint8 inputNumber) public view returns (bool) {
        uint256 inputIndex = BankexPlasmaTransaction.makeTransactionIndex(blockNumber, txNumberInBlock, inputNumber);
        ShowInputChallenge storage challenge = showInputChallengeStatuses[inputIndex];
        return challenge.status == ShowInputChallengeStarted;
    }


// ----------------------------------
// Deposit related functions

    function deposit() payable public returns (bool success) {
        uint256 size;
        address _addr = msg.sender;
        assembly {
            size := extcodesize(_addr)
        }
        if (size > 0) {
            revert();
        }
        return depositFor(msg.sender);
    }

    function depositFor(address _for) payable public returns (bool success) {
        require(msg.value > 0);
        require(!plasmaErrorFound);
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

    function challengeDepositWithdraw(uint256 depositIndex,
                            uint32 _plasmaBlockNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof) public returns (bool success) {
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
// Withdraw related functions

    function startWithdraw(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint8 _outputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof)
    public payable returns(bool success, uint256 withdrawIndex) {
        if (plasmaErrorFound) {
            return startExit(_plasmaBlockNumber, _outputNumber, _plasmaTransaction, _merkleProof);
        }
        require(msg.value == WithdrawCollateral);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.isWellFormed);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        if (TX.txType == TxTypeFund) {
            require(blockStorage.isOperator(TX.sender));
        }
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[_outputNumber];
        require(output.recipient == msg.sender);
        uint256 index;
        WithdrawRecord memory record;
        (record, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, TX.txNumberInBlock, _outputNumber, true);
        record.numInputs = uint8(TX.inputs.length);
        require(transactionsSpendingRecords[index % (1 << 128)] == 0);
        allWithdrawRecordsForUser[msg.sender].push(index);
        addTotalPendingExit(int256(record.amount));
        emit WithdrawRequestAcceptedEvent(output.recipient, index);
        return (true, index);
    }

    function startExit(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint8 _outputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof)
    internal returns(bool success, uint256 withdrawIndex) {
        require(msg.value == WithdrawCollateral);
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        require(TX.isWellFormed);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        if (TX.txType == TxTypeFund) {
            require(blockStorage.isOperator(TX.sender));
        }
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[_outputNumber];
        uint256 index;
        WithdrawRecord memory record;
        (record, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, TX.txNumberInBlock, _outputNumber, true);
        if (withdrawBuyoutOffers[index].accepted) {
            require(output.recipient == withdrawBuyoutOffers[index].from);
        } else {
            require(output.recipient == msg.sender);
        }
        record.numInputs = uint8(TX.inputs.length);
        require(transactionsSpendingRecords[index % (1 << 128)] == 0);
        uint256 priorityModifier = uint256(_plasmaBlockNumber) << 192;
        if (_plasmaBlockNumber < blockStorage.weekOldBlockNumber()) {
            priorityModifier = blockStorage.weekOldBlockNumber() << 192;
        }
        uint256 priority = priorityModifier + (index % (1 << 128));
        exitQueue.insert(priority);
        emit ExitStartedEvent(output.recipient, priorityModifier, index % (1 << 128));
        return (true, index);
    }

    // stop the withdraw by presenting a transaction in Plasma chain
    function challengeWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint8 _inputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof,
                            uint256 _withdrawIndex //references withdraw
                            ) public returns (bool success) {
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        if (transactionsSpendingRecords[_withdrawIndex % (1 << 128)] != 0) {
            record.status = WithdrawStatusChallenged;
            emit WithdrawChallengedEvent(msg.sender, _withdrawIndex);
            addTotalPendingExit(-int256(record.amount));
            if (record.hasCollateral) {
                msg.sender.transfer(WithdrawCollateral);
            }
            return true;
        }
        if (lastValidBlock > 0) {
            require(_plasmaBlockNumber < lastValidBlock);
        }
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        uint256 txIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock, _inputNumber);
        require(TX.isWellFormed);
        require(TX.inputs[_inputNumber].blockNumber == record.blockNumber);
        require(TX.inputs[_inputNumber].txNumberInBlock == record.txNumberInBlock);
        require(TX.inputs[_inputNumber].outputNumberInTX == record.outputNumberInTX);
        record.status = WithdrawStatusChallenged;
        transactionsSpendingRecords[_withdrawIndex % (1 << 128)] = txIndex;
        emit WithdrawChallengedEvent(msg.sender, _withdrawIndex);
        addTotalPendingExit(-int256(record.amount));
        if (record.hasCollateral) {
            msg.sender.transfer(WithdrawCollateral);
        }
        return true;
    }

    function finalizeWithdraw(uint256 withdrawIndex) public returns(bool success) {
        WithdrawRecord storage record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        require(transactionsSpendingRecords[withdrawIndex % (1 << 128)] == 0);
        if (plasmaErrorFound) { // do not allow to finalize withdrawals if error is found even if an error was in a block later than this withdraw references
            address to = address(0);
            if (record.hasCollateral) {
                to = record.beneficiary;
            }
            addTotalPendingExit(-int256(record.amount));
            delete withdrawRecords[withdrawIndex];
            if (to != address(0)) {
                to.transfer(WithdrawCollateral);
            }
            return true;
        }
        require(block.timestamp >= record.timestamp + WithdrawDelay);
        uint8 numInputs = record.numInputs;
        uint32 blockNumber = record.blockNumber;
        uint32 txNumberInBlock = record.txNumberInBlock;
        for (uint8 i = 0; i < numInputs; i++) {
            require(!inputIsChallenged(blockNumber, txNumberInBlock, i));
        }
        if (amountPendingExit > totalAmountDeposited) {
            setErrorAndLastFoundBlock(uint32(lastBlockNumber()), false, msg.sender);
            return false;
        }
        record.status = WithdrawStatusCompleted;
        record.timestamp = block.timestamp;
        emit WithdrawFinalizedEvent(record.blockNumber, record.txNumberInBlock, record.outputNumberInTX);
        uint256 toSend = record.amount;
        addTotalPendingExit(-int256(record.amount));
        addTotalDeposited(-int256(record.amount));
        if (record.hasCollateral) {
            toSend += WithdrawCollateral;
        }
        record.beneficiary.transfer(toSend);
        return true;
    }


    function finalizeExits(uint256 _numOfExits) public returns (bool success) {
        require(plasmaErrorFound);
        uint256 exitTimestamp = block.timestamp - ExitDelay;
        uint256 withdrawIndex = exitQueue.getMin() % (1 << 128);
        WithdrawRecord storage currentRecord = withdrawRecords[withdrawIndex];
        uint256 toSend = 0;
        uint8 status = 0;
        address beneficiary = address(0);
        for (uint i = 0; i < _numOfExits; i++) {
            if (blockStorage.getSubmissionTime(currentRecord.blockNumber) < exitTimestamp) {
                status = currentRecord.status;
                if (status == WithdrawStatusStarted) {
                    beneficiary = currentRecord.beneficiary;
                    currentRecord.status = WithdrawStatusCompleted;
                    toSend = currentRecord.amount;
                    addTotalDeposited(-int256(toSend));
                    if (currentRecord.hasCollateral) {
                        toSend += WithdrawCollateral;
                    }
                    // delete withdrawRecords[withdrawIndex]
                }
                exitQueue.delMin();
                if (beneficiary != address(0)) {
                    beneficiary.transfer(toSend);
                }
                if (exitQueue.currentSize() > 0) {
                    withdrawIndex = exitQueue.getMin() % (1 << 128);
                    currentRecord = withdrawRecords[withdrawIndex];
                    toSend = 0;
                    beneficiary = address(0);
                    status = 0;
                } else {
                    break;
                }
            }
        }
        return true;
    }

    function populateWithdrawRecordFromOutput(BankexPlasmaTransaction.TransactionOutput memory _output, uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX, bool _setCollateral) internal returns (WithdrawRecord storage record, uint256 withdrawIndex) {
        withdrawIndex = BankexPlasmaTransaction.makeTransactionIndex(_blockNumber, _txNumberInBlock, _outputNumberInTX);
        record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusNoRecord);
        record.status = WithdrawStatusStarted;
        record.hasCollateral = _setCollateral;
        record.beneficiary = _output.recipient;
        record.amount = _output.amount;
        record.timestamp = block.timestamp;
        record.blockNumber = _blockNumber;
        record.txNumberInBlock = _txNumberInBlock;
        record.outputNumberInTX = _outputNumberInTX;
        return (record, withdrawIndex);
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
