pragma solidity ^0.4.24;

import {Conversion} from "./Conversion.sol";
import {ByteSlice} from "./ByteSlice.sol";

interface PlasmaBlockStorageInterface {
    function isOperator(address _operator) external view returns (bool);
    function canSignBlocks(address _operator) external view returns (bool);
    function setOperator(address _op, uint256 _status) external returns (bool success);
    function lastBlockNumber() external view returns(uint256);
    function hashOfLastSubmittedBlock() external view returns(bytes32);
    function weekOldBlockNumber() external view returns(uint256);
    function submitBlockHeaders(bytes _headers) external returns (bool success);
    // function storeBlock(uint256 _blockNumber, uint256 _numberOfTransactions, bytes32 _merkleRoot) external returns (bool success);
    // function storeBlocks(uint256[] _blockNumbers, uint256[] _numbersOfTransactions, bytes32[] _merkleRoots) external returns (bool success);
    function getBlockInformation(uint32 _blockNumber) external view returns (uint256 submittedAt, uint32 numberOfTransactions, bytes32 merkleRoot);
    function getMerkleRoot(uint32 _blockNumber) external view returns (bytes32 merkleRoot);
    function incrementWeekOldCounter() external;
    function getSubmissionTime(uint32 _blockNumber) external view returns (uint256 submittedAt);
    function getNumberOfTransactions(uint32 _blockNumber) external view returns (uint32 numberOfTransaction);
}

contract PlasmaBlockStorage {
    using ByteSlice for bytes;
    using ByteSlice for ByteSlice.Slice;
    using Conversion for uint256;
    address public owner;

    mapping(address => OperatorStatus) public operators;
    enum OperatorStatus {Null, CanSignTXes, CanSignBlocks}

    uint256 public lastBlockNumber;
    uint256 public weekOldBlockNumber;
    uint256 public blockHeaderLength = 137;
    bytes32 public hashOfLastSubmittedBlock = keccak256(abi.encodePacked(PersonalMessagePrefixBytes,"16","BankexFoundation"));

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

    struct BlockInformation {
        uint32 numberOfTransactions;
        uint64 submittedAt;
        bytes32 merkleRootHash;
    }

    mapping (uint256 => BlockInformation) public blocks;
    event BlockHeaderSubmitted(uint256 indexed _blockNumber, bytes32 indexed _merkleRoot);

    constructor() public {
        owner = msg.sender;
        blocks[weekOldBlockNumber].submittedAt = uint64(block.timestamp);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setOwner(address _newOwner) onlyOwner public {
        require(_newOwner != address(0));
        owner = _newOwner;
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

    function isOperator(address _operator) public view returns (bool) {
        OperatorStatus stat = operators[_operator];
        return stat != OperatorStatus.Null;
    }

    function canSignBlocks(address _operator) public view returns (bool) {
        OperatorStatus stat = operators[_operator];
        return stat == OperatorStatus.CanSignBlocks;
    }

    function incrementWeekOldCounter() onlyOwner public {
        uint256 ts = block.timestamp - (1 weeks);
        uint256 localCounter = weekOldBlockNumber;
        while (uint256(blocks[localCounter].submittedAt) <= ts) {
            if (blocks[localCounter].submittedAt == 0) {
                break;
            }
            localCounter++;
        }
        if (localCounter != weekOldBlockNumber) {
            weekOldBlockNumber = localCounter - 1;
        }
    }

    function submitBlockHeaders(bytes _headers) onlyOwner public returns (bool success) {
        require(_headers.length % blockHeaderLength == 0);
        ByteSlice.Slice memory slice = _headers.slice();
        ByteSlice.Slice memory reusableSlice;
        uint256[] memory reusableSpace = new uint256[](5);
        bytes32 lastBlockHash = hashOfLastSubmittedBlock;
        uint256 _lastBlockNumber = lastBlockNumber;
        for (uint256 i = 0; i < _headers.length/blockHeaderLength; i++) {
            reusableSlice = slice.slice(i*blockHeaderLength, (i+1)*blockHeaderLength);
            reusableSpace[0] = 0;
            reusableSpace[1] = BlockNumberLength;
            reusableSpace[2] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //blockNumber
            require(reusableSpace[2] == _lastBlockNumber+1+i);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += TxNumberLength;
            reusableSpace[3] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //numberOfTransactions
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += PreviousHashLength;
            bytes32 previousBlockHash = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            require(previousBlockHash == lastBlockHash);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += MerkleRootHashLength;
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
            bytes32 newBlockHash = keccak256(abi.encodePacked(PersonalMessagePrefixBytes, NewBlockPersonalHashLength.uintToBytes(), uint32(reusableSpace[2]), uint32(reusableSpace[3]), previousBlockHash, merkleRootHash));
            address signer = ecrecover(newBlockHash, uint8(reusableSpace[4]), r, s);
            require(canSignBlocks(signer));
            lastBlockHash = keccak256(abi.encodePacked(PersonalMessagePrefixBytes, PreviousBlockPersonalHashLength.uintToBytes(), reusableSlice.toBytes()));
            storeBlock(reusableSpace[2], reusableSpace[3], merkleRootHash, i);
        }
        hashOfLastSubmittedBlock = lastBlockHash;
        return true;
    }


    function storeBlock(uint256 _blockNumber, uint256 _numberOfTransactions, bytes32 _merkleRoot, uint256 _timeOffset) internal returns (bool success) {
        incrementWeekOldCounter();
        require(_blockNumber == lastBlockNumber + 1);
        BlockInformation storage newBlockInformation = blocks[_blockNumber];
        newBlockInformation.merkleRootHash = _merkleRoot;
        newBlockInformation.submittedAt = uint64(block.timestamp + _timeOffset);
        newBlockInformation.numberOfTransactions = uint32(_numberOfTransactions);
        lastBlockNumber = _blockNumber;
        emit BlockHeaderSubmitted(_blockNumber, _merkleRoot);
        return true;
    }

    // function storeBlocks(uint256[] _blockNumbers, uint256[] _numbersOfTransactions, bytes32[] _merkleRoots) public returns (bool success) {
    //     require(_blockNumbers.length == _merkleRoots.length);
    //     require(_blockNumbers.length == _numbersOfTransactions.length);
    //     require(_blockNumbers.length != 0);
    //     incrementWeekOldCounter();

    //     uint256 currentCounter = lastBlockNumber;
    //     for (uint256 i = 0; i < _blockNumbers.length; i++) {
    //         require(_blockNumbers[i] == currentCounter + 1);   
    //         currentCounter = _blockNumbers[i];
    //         BlockInformation storage newBlockInformation = blocks[currentCounter];
    //         newBlockInformation.merkleRootHash = _merkleRoots[i];
    //         newBlockInformation.submittedAt = uint192(block.timestamp + i);
    //         newBlockInformation.numberOfTransactions = uint32(_numbersOfTransactions[i]);
    //         emit BlockHeaderSubmitted(_blockNumbers[i], _merkleRoots[i]);
    //     }
    //     lastBlockNumber = currentCounter;
    //     return true;
    // }

    function getBlockInformation(uint32 _blockNumber) public view returns (uint256 submittedAt, uint32 numberOfTransactions, bytes32 merkleRoot) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return (blockInformation.submittedAt, blockInformation.numberOfTransactions, blockInformation.merkleRootHash);
    }

    function getMerkleRoot(uint32 _blockNumber) public view returns (bytes32 merkleRoot) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return blockInformation.merkleRootHash;
    }

    function getSubmissionTime(uint32 _blockNumber) public view returns (uint256 submittedAt) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return uint256(blockInformation.submittedAt);
    }

    function getNumberOfTransactions(uint32 _blockNumber) public view returns (uint32 numberOfTransaction) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return blockInformation.numberOfTransactions;
    }
}