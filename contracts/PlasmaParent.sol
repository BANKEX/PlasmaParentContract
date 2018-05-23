pragma solidity ^0.4.24;

import {Conversion} from "./Conversion.sol";
import {ByteSlice} from "./ByteSlice.sol";
import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

interface PlasmaParentInterface {
    function isOperator(address _operator) external view returns (bool);
}

contract PlasmaParent {
    using BankexPlasmaTransaction for BankexPlasmaTransaction.PlasmaTransaction;

    bool public plasmaErrorFound;
    uint32 public lastValidBlock;
    uint256 public operatorsBond;

    PriorityQueueInterface public exitQueue;
    PlasmaBlockStorageInterface public blockStorage;
    address public challengesContract;
    address public owner = msg.sender;
    int256 public totalAmountDeposited;
    int256 public amountPendingExit;

    mapping(address => bool) public operators;

    uint256 public lastEthBlockNumber = block.number;
    uint256 public depositCounterInBlock;

    uint256 public DepositWithdrawCollateral = 0;
    uint256 public WithdrawCollateral = 0;
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
        bool isExpress;
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
        uint8 status;
        uint64 timestamp;
    }

    mapping(uint256 => ShowInputChallenge) showInputChallengeStatuses;
    event ShowInputChallengeInitiatedEvent(address indexed _from,
                                uint256 indexed _inputIndex);
    event ShowInputChallengeRespondedEvent(address indexed _from,
                                uint256 indexed _inputIndex,
                                uint256 indexed _outputIndex);
// end of storage declarations ---------------------------  

    constructor(address _priorityQueue, address _blockStorage) public payable {
        require(_priorityQueue != address(0));
        require(_blockStorage != address(0));
        exitQueue = PriorityQueueInterface(_priorityQueue);
        blockStorage = PlasmaBlockStorageInterface(_blockStorage);
        operators[msg.sender] = true;
        operatorsBond = msg.value;
    }

    function setOperator(address _op, bool _status) public returns (bool success) {
        require(msg.sender == owner);
        operators[_op] = _status;
        return true;
    }

    function setChallenger(address _challenger) public returns (bool success) {
        require(msg.sender == owner);
        require(_challenger != address(0));
        require(challengesContract == address(0));
        challengesContract = _challenger;
        return true;
    }

    function setErrorAndLastFoundBlock(uint32 _lastValidBlock, bool _transferReward) internal returns (bool success) {
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
        if (operatorsBond != 0 && _transferReward) {
            uint256 bond = operatorsBond;
            operatorsBond = 0;
            msg.sender.transfer(bond);
        }
        return true;
    }

    function isOperator(address _operator) public view returns (bool) {
        return operators[_operator];
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


// ----------------------------------
// Deposit related functions

    function deposit() payable public returns (uint256 idx) {
        uint32 size;
        address _addr = msg.sender;
        assembly {
            size := extcodesize(_addr)
        }
        if (size > 0) {
            revert();
        }
        return depositFor(msg.sender);
    }

    function depositFor(address _for) payable public returns (uint256 idx) {
        require(msg.value > 0);
        require(!plasmaErrorFound);
        if (block.number != lastEthBlockNumber) {
            depositCounterInBlock = 0;
        }
        uint256 depositIndex = block.number << 32 + depositCounterInBlock;
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusNoRecord);
        record.from = _for;
        record.amount = msg.value;
        record.status = DepositStatusDeposited;
        depositCounterInBlock = depositCounterInBlock + 1;
        emit DepositEvent(_for, msg.value, depositIndex);
        allDepositRecordsForUser[_for].push(depositIndex);
        addTotalDeposited(int256(msg.value));
        return depositIndex;
    }

    function startDepositWithdraw(uint256 depositIndex) public payable returns (bool success) {
        //require(block.number >= (depositIndex >> 32) + 500);
        require(msg.value == DepositWithdrawCollateral);
        totalAmountDeposited = totalAmountDeposited + int256(msg.value);
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
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        require(operators[TX.sender]);
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
                            uint32 _plasmaTxNumInBlock,
                            uint8 _outputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof)
    public payable returns(bool success, uint256 withdrawIndex) {
        require(msg.value == WithdrawCollateral);
        if (plasmaErrorFound) {
            return startExit(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, _plasmaTransaction, _merkleProof);
        }
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        require(TX.txType == TxTypeFund || TX.sender != address(0));
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[_outputNumber];
        require(output.recipient == msg.sender);
        uint256 index;
        WithdrawRecord memory record;
        (record, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, true);
        require(transactionsSpendingRecords[index % (1 << 128)] == 0);
        allWithdrawRecordsForUser[msg.sender].push(index);
        addTotalPendingExit(int256(record.amount));
        emit WithdrawRequestAcceptedEvent(output.recipient, index);
        return (true, index);
    }

    function startExit(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint32 _plasmaTxNumInBlock,
                            uint8 _outputNumber,
                            bytes _plasmaTransaction,
                            bytes _merkleProof)
    internal returns(bool success, uint256 withdrawIndex) {
        blockStorage.incrementWeekOldCounter();
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        require(TX.txType == TxTypeFund || TX.sender != address(0));
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[_outputNumber];
        require(_plasmaTxNumInBlock == TX.txNumberInBlock);
        require(output.recipient == msg.sender);
        uint256 index;
        WithdrawRecord memory record;
        (record, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, true);
        require(transactionsSpendingRecords[index % (1 << 128)] == 0);
        uint256 priorityModifier = uint256(_plasmaBlockNumber) << 192;
        if (_plasmaBlockNumber < blockStorage.weekOldBlockNumber()) {
            priorityModifier = blockStorage.weekOldBlockNumber() << 192;
        }
        uint256 priority = priorityModifier + (index % (1 << 128));
        exitQueue.insert(priority);
        emit ExitStartedEvent(output.recipient, priority);
        return (true, priority);
    }

    // stop the withdraw by presenting a transaction in Plasma chain
    function challengeWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock,
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
        uint256 txIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
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
        // if (plasmaErrorFound && record.blockNumber > lastValidBlock) {
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
        if (amountPendingExit > totalAmountDeposited) {
            setErrorAndLastFoundBlock(uint32(lastBlockNumber()), false);
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
        for (uint i = 0; i <= _numOfExits; i++) {
            if (blockStorage.getSubmissionTime(currentRecord.blockNumber) < exitTimestamp) {
                require(currentRecord.status == WithdrawStatusStarted);
                currentRecord.status = WithdrawStatusCompleted;
                toSend = currentRecord.amount;
                if (currentRecord.hasCollateral) {
                    toSend += WithdrawCollateral;
                }
                addTotalDeposited(-int256(currentRecord.amount));
                currentRecord.beneficiary.transfer(toSend);
                exitQueue.delMin();
                if (exitQueue.currentSize() > 0) {
                    withdrawIndex = exitQueue.getMin() % (1 << 128);
                    currentRecord = withdrawRecords[withdrawIndex];
                } else {
                    break;
                }
            }
        }
        return true;
    }

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
        record.timestamp = block.timestamp;
        record.blockNumber = _blockNumber;
        record.txNumberInBlock = _txNumberInBlock;
        record.outputNumberInTX = _outputNumberInTX;
        return (record, withdrawIndex);
    }

    function offerOutputBuyout(uint256 _withdrawIndex, address _beneficiary) public payable returns (bool success) {
        require(msg.value > 0);
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        WithdrawBuyoutOffer storage offer = withdrawBuyoutOffers[_withdrawIndex];
        emit WithdrawBuyoutOffered(_withdrawIndex, msg.sender, msg.value);
        if (offer.from == address(0)) {
            offer.from = _beneficiary;
            offer.amount = msg.value;
            return true;
        } else {
            require(msg.value > offer.amount);
            address oldFrom = offer.from;
            uint256 oldAmount = offer.amount;
            offer.from = _beneficiary;
            offer.amount = msg.value;
            oldFrom.transfer(oldAmount);
            return true;
        }
    }

    function acceptBuyoutOffer(uint256 _withdrawIndex) public returns (bool success) {
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        WithdrawBuyoutOffer storage offer = withdrawBuyoutOffers[_withdrawIndex];
        require(offer.from != address(0));
        require(offer.amount <= record.amount);
        address oldBeneficiary = record.beneficiary;
        uint256 offerAmount = offer.amount;
        record.beneficiary = offer.from;
        delete withdrawBuyoutOffers[_withdrawIndex];
        emit WithdrawBuyoutAccepted(_withdrawIndex, record.beneficiary); 
        oldBeneficiary.transfer(offerAmount);
        return true;
    }
// ----------------------------------
// Double-spend related functions

    function() external {
        bytes32 x;
        address callee = challengesContract;
        uint256 memoryPointer;
        assembly {
            memoryPointer := mload(0x40)
            calldatacopy(memoryPointer, 0, calldatasize)
            let _retVal := delegatecall(sub(gas, 10000), callee, memoryPointer, calldatasize, 0x60, 0x00)
            x := returndatasize
            returndatacopy(0x60, 0, x)
            switch _retVal case 0 { revert(0,0) } default { return(0x60, x) }
        }
    }


// Convenience functions

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
