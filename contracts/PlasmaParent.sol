pragma solidity ^0.4.21;

import {Conversion} from "./Conversion.sol";
import {ByteSlice} from "./ByteSlice.sol";
import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";
import {PlasmaBlockStorageInterface} from "./PlasmaBlockStorage.sol";
import {PriorityQueueInterface} from "./PriorityQueue.sol";

// interface PlasmaParentInterface {
//     function setErrorAndLastFoundBlock(uint256 _lastValidBlock) external returns (bool success);
//     function isOperator(address _operator) external view returns (bool isOperator);
// }

contract PlasmaParent {
    using BankexPlasmaTransaction for BankexPlasmaTransaction.PlasmaTransaction;
    using ByteSlice for bytes;
    using ByteSlice for ByteSlice.Slice;
    using Conversion for uint256;

    bool public plasmaErrorFound = false;
    uint256 public lastValidBlock = 0;

    PriorityQueueInterface public exitQueue;
    PlasmaBlockStorageInterface public blockStorage;
    address public challengesContract;
    address public owner = msg.sender;

    mapping(address => bool) public operators;
    uint32 public blockHeaderLength = 137;

    bytes32 public hashOfLastSubmittedBlock = keccak256(PersonalMessagePrefixBytes,"16","BankexFoundation");
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

    function PlasmaParent(address _priorityQueue, address _blockStorage) public {
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
        require(challengesContract == address(0));
        challengesContract = _challenger;
        return true;
    }

    // function setErrorAndLastFoundBlock(uint256 _lastValidBlock) public returns (bool success) {
    //     require(msg.sender == challengesContract);
    //     if (!plasmaErrorFound) {
    //         plasmaErrorFound = true;
    //     }
    //     if (lastValidBlock == 0) {
    //         lastValidBlock = _lastValidBlock;
    //     } else {
    //         require(lastValidBlock > _lastValidBlock);
    //         lastValidBlock = _lastValidBlock;
    //     }
    //     return true;
    // }

    // function isOperator(address _operator) public view returns (bool isOperator) {
    //     return operators[_operator];
    // }

    function submitBlockHeaders(bytes _headers) public returns (bool success) {
        require(_headers.length % blockHeaderLength == 0);
        ByteSlice.Slice memory slice = _headers.slice();
        ByteSlice.Slice memory reusableSlice;
        uint256[] memory reusableSpace = new uint256[](5);
        bytes32 lastBlockHash = hashOfLastSubmittedBlock;
        uint256 lastBlockNumber = blockStorage.lastBlockNumber();
        for (uint256 i = 0; i < _headers.length/blockHeaderLength; i++) {
            reusableSlice = slice.slice(i*blockHeaderLength, (i+1)*blockHeaderLength);
            reusableSpace[0] = 0;
            reusableSpace[1] = BlockNumberLength;
            reusableSpace[2] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //blockNumber
            require(reusableSpace[2] == lastBlockNumber+1+i);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += TxNumberLength;
            reusableSpace[3] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //numberOfTransactions
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 previousBlockHash = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            require(previousBlockHash == hashOfLastSubmittedBlock);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 merkleRootHash = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 1;
            reusableSpace[4] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint();
            if (reusableSpace[4] < 27) {
                reusableSpace[4] = reusableSpace[4]+27;
            }
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 r = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 s = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            bytes32 newBlockHash = keccak256(PersonalMessagePrefixBytes, NewBlockPersonalHashLength.uintToBytes(), uint32(reusableSpace[2]), uint32(reusableSpace[3]), previousBlockHash, merkleRootHash);
            address signer = ecrecover(newBlockHash, uint8(reusableSpace[4]), r, s);
            require(operators[signer]);
            lastBlockHash = keccak256(PersonalMessagePrefixBytes, PreviousBlockPersonalHashLength.uintToBytes(), reusableSlice.toBytes());
            blockStorage.storeBlock(reusableSpace[2], merkleRootHash);
        }
        hashOfLastSubmittedBlock = lastBlockHash;
        return true;
    }

    function lastBlockNumber() public view returns (uint256 blockNumber) {
        return blockStorage.lastBlockNumber();
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

    // function () payable external {
    //     deposit();
    // }


    function deposit() payable public returns (uint256 idx) {
        require(!plasmaErrorFound);
        if (block.number != lastEthBlockNumber) {
            depositCounterInBlock = 0;
        }
        uint256 depositIndex = block.number << 32 + depositCounterInBlock;
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusNoRecord);
        record.from = msg.sender;
        record.amount = msg.value;
        record.status = DepositStatusDeposited;
        depositCounterInBlock = depositCounterInBlock + 1;
        DepositEvent(msg.sender, msg.value, depositIndex);
        allDepositRecordsForUser[msg.sender].push(depositIndex);
        return depositIndex;
    }

    function startDepositWithdraw(uint256 depositIndex) public payable returns (bool success) {
        require(block.number >= (depositIndex >> 32) + 500); 
        require(msg.value == DepositWithdrawCollateral);
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusDeposited);
        require(record.from == msg.sender);
        record.status = DepositStatusWithdrawStarted;
        record.withdrawStartedAt = now;
        record.hasCollateral = !plasmaErrorFound;
        DepositWithdrawStartedEvent(depositIndex);
        return true;
    }

    function finalizeDepositWithdraw(uint256 depositIndex) public returns (bool success) {
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusWithdrawStarted);
        require(now >= record.withdrawStartedAt + DepositWithdrawDelay);
        record.status = DepositStatusWithdrawCompleted;
        DepositWithdrawCompletedEvent(depositIndex);
        uint256 toSend = record.amount;
        if (record.hasCollateral) {
            toSend += DepositWithdrawCollateral;
        }
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
        DepositWithdrawChallengedEvent(depositIndex);
        if (record.hasCollateral) {
            msg.sender.transfer(DepositWithdrawCollateral);
        }
        return true;
    }

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
    event WithdrawChallengedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawFinalizedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event ExitStartedEvent(address indexed _from,
                            uint256 indexed _priority);

    mapping(uint256 => WithdrawRecord) public withdrawRecords;
    mapping(address => uint256[]) public allWithdrawRecordsForUser;

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
        allWithdrawRecordsForUser[msg.sender].push(index);
        WithdrawRequestAcceptedEvent(output.recipient, index);
        // WithdrawStartedEvent(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber);
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
        require(output.recipient == msg.sender);
        uint256 index;
        WithdrawRecord memory record;
        (record, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, true);
        uint256 priorityModifier = uint256(_plasmaBlockNumber) << 192;
        if (_plasmaBlockNumber < blockStorage.weekOldBlockNumber()) {
            priorityModifier = blockStorage.weekOldBlockNumber() << 192;
        }
        uint256 priority = priorityModifier + (index % (1 << 128));
        exitQueue.insert(priority);
        // WithdrawStartedEvent(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber);
        ExitStartedEvent(output.recipient, priority);
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
        uint256 txIndex = BankexPlasmaTransaction.makeTransactionIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        require(BankexPlasmaTransaction.checkForInclusionIntoBlock(blockStorage.getMerkleRoot(_plasmaBlockNumber), _plasmaTransaction, _merkleProof));
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        require(TX.inputs[_inputNumber].blockNumber == record.blockNumber);
        require(TX.inputs[_inputNumber].txNumberInBlock == record.txNumberInBlock);
        require(TX.inputs[_inputNumber].outputNumberInTX == record.outputNumberInTX);
        record.status = WithdrawStatusChallenged;
        transactionsSpendingRecords[_withdrawIndex % (1 << 128)] = txIndex;
        WithdrawChallengedEvent(msg.sender, _withdrawIndex);
        if (record.hasCollateral) {
            msg.sender.transfer(WithdrawCollateral);
        }
        return true;
    }

    function finalizeWithdraw(uint256 withdrawIndex) public returns(bool success) {
        WithdrawRecord storage record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        if (plasmaErrorFound && record.blockNumber > lastValidBlock) {
            if (record.hasCollateral) {
                address to = record.beneficiary;
                delete withdrawRecords[withdrawIndex];
                to.transfer(WithdrawCollateral);
            } else {
                delete withdrawRecords[withdrawIndex];
            }
            return true;
        }
        require(now >= record.timestamp + WithdrawDelay);
        record.status = WithdrawStatusCompleted;
        record.timestamp = now;
        WithdrawFinalizedEvent(record.blockNumber, record.txNumberInBlock, record.outputNumberInTX);
        uint256 toSend = record.amount;
        if (record.hasCollateral) {
            toSend += WithdrawCollateral;
        }
        record.beneficiary.transfer(toSend);
        return true;
    }


    function finalizeExits(uint256 _numOfExits) public returns (bool success) {
        uint256 exitTimestamp = now - ExitDelay;
        uint256 withdrawIndex = exitQueue.getMin() % (1 << 128);
        WithdrawRecord storage currentRecord = withdrawRecords[withdrawIndex];
        for (uint i = 0; i <= _numOfExits; i++) {
            if (blockStorage.getSubmissionTime(currentRecord.blockNumber) < exitTimestamp) {
                require(currentRecord.status == WithdrawStatusStarted);
                currentRecord.status = WithdrawStatusCompleted;
                currentRecord.beneficiary.transfer(currentRecord.amount);
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
        record.timestamp = now;
        record.blockNumber = _blockNumber;
        record.txNumberInBlock = _txNumberInBlock;
        record.outputNumberInTX = _outputNumberInTX;
        return (record, withdrawIndex);
    }
// ----------------------------------
// Double-spend related functions

    function() external {
        bytes32 x;
        address callee = challengesContract;
        assembly {
            calldatacopy(0xff, 0, calldatasize)
            let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
            x := returndatasize
            switch _retVal case 0 { revert(0,0) } default { return(0, x) }
        }
    }


    event DoubleSpendProovedEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);
    event SpendAndWithdrawProovedEvent(uint256 indexed _txIndex, uint256 indexed _withdrawIndex);

// // two transactions spend the same output
//     function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
//                             uint32 _plasmaTxNumInBlock1,
//                             uint8 _inputNumber1,
//                             bytes _plasmaTransaction1,
//                             bytes _merkleProof1,
//                             uint32 _plasmaBlockNumber2, //references and proves transaction number 2
//                             uint32 _plasmaTxNumInBlock2,
//                             uint8 _inputNumber2,
//                             bytes _plasmaTransaction2,
//                             bytes _merkleProof2) public returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

//     function checkActualDoubleSpendProof(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
//                             uint32 _plasmaTxNumInBlock1,
//                             uint8 _inputNumber1,
//                             bytes _plasmaTransaction1,
//                             bytes _merkleProof1,
//                             uint32 _plasmaBlockNumber2, //references and proves transaction number 2
//                             uint32 _plasmaTxNumInBlock2,
//                             uint8 _inputNumber2,
//                             bytes _plasmaTransaction2,
//                             bytes _merkleProof2) public view returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

// // transaction output is withdrawn and spent in Plasma chain
//     function proveSpendAndWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
//                             uint32 _plasmaTxNumInBlock,
//                             uint8 _inputNumber,
//                             bytes _plasmaTransaction,
//                             bytes _merkleProof,
//                             uint256 _withdrawIndex //references withdraw
//                             ) public returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

// // ----------------------------------
// // Prove unlawful funding transactions on Plasma

    event FundingWithoutDepositEvent(uint256 indexed _txIndex, uint256 indexed _depositIndex);
    event DoubleFundingEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);

// function proveFundingWithoutDeposit(uint32 _plasmaBlockNumber, //references and proves transaction
//                             uint32 _plasmaTxNumInBlock,
//                             bytes _plasmaTransaction,
//                             bytes _merkleProof) public returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

//     //prove double funding of the same

//     function proveDoubleFunding(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
//                             uint32 _plasmaTxNumInBlock1,
//                             bytes _plasmaTransaction1,
//                             bytes _merkleProof1,
//                             uint32 _plasmaBlockNumber2, //references and proves transaction number 2
//                             uint32 _plasmaTxNumInBlock2,
//                             bytes _plasmaTransaction2,
//                             bytes _merkleProof2) public returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

// // Prove invalid ownership in split or merge, or balance breaking inside a signle transaction or between transactions

// // Balance breaking in TX
//     function proveBalanceBreaking(uint32 _plasmaBlockNumber, //references and proves transaction
//                             uint32 _plasmaTxNumInBlock,
//                             bytes _plasmaTransaction,
//                             bytes _merkleProof) public returns (bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

// // Prove that either amount of the input doesn't match the amount of the output, or spender of the output didn't have an ownership


// // IMPORTANT Allow plasma operator to make merges on behalf of the users, in this case merge transaction MUST have 1 output that belongs to owner of original outputs
// // Only operator have a power for such merges
//     function proveBalanceOrOwnershipBreakingBetweenInputAndOutput(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
//                             uint32 _plasmaTxNumInBlock,
//                             bytes _plasmaTransaction,
//                             bytes _merkleProof,
//                             uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
//                             uint32 _originatingPlasmaTxNumInBlock,
//                             bytes _originatingPlasmaTransaction,
//                             bytes _originatingMerkleProof,
//                             uint256 _inputOfInterest
//                             ) public returns(bool success) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }

//     function checkRightfullInputOwnershipAndBalance(bytes _spendingTXbytes, bytes _originatingTXbytes, uint32 _originatingPlasmaBlockNumber, uint256 _inputNumber) internal view returns (bool isValid) {
//         bytes32 x;
//         address callee = challengesContract;
//         assembly {
//             calldatacopy(0xff, 0, calldatasize)
//             let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//             x := returndatasize
//             switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//         }
//     }


// ----------------------------------
// Convenience functions

//    function isWellFormedTransaction(bytes _plasmaTransaction) public view returns (bool isWellFormed) {
//        bytes32 x;
//        address callee = challengesContract;
//        assembly {
//            calldatacopy(0xff, 0, calldatasize)
//            let _retVal := delegatecall(sub(gas, 10000), callee, 0xff, calldatasize, 0, 0x20)
//            x := returndatasize
//            switch _retVal case 0 { revert(0,0) } default { return(0, x) }
//        }
//    }

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
