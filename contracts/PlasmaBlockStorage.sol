pragma solidity ^0.4.21;

interface PlasmaBlockStorageInterface {
    function lastBlockNumber() external view returns(uint256);
    function weekOldBlockNumber() external view returns(uint256);
    function storeBlock(uint256 _blockNumber, bytes32 _merkleRoot) external returns (bool success);
    function storeBlocks(uint256[] _blockNumbers, bytes32[] _merkleRoots) external returns (bool success);
    function getBlockInformation(uint32 _blockNumber) external view returns (uint256 submittedAt, bytes32 merkleRoot);
    function getMerkleRoot(uint32 _blockNumber) external view returns (bytes32 merkleRoot);
    function incrementWeekOldCounter() external;
    function getSubmissionTime(uint32 _blockNumber) external view returns (uint256 submittedAt);
}

contract PlasmaBlockStorage {
    address public owner = msg.sender;

    uint256 public lastBlockNumber = 0;
    uint256 public weekOldBlockNumber = 0;

    struct BlockInformation {
        uint256 submittedAt;
        bytes32 merkleRootHash;
    }

    mapping (uint256 => BlockInformation) public blocks;
    event BlockHeaderSubmitted(uint256 indexed _blockNumber, bytes32 indexed _merkleRoot);

    function PlasmaBlockStorage() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setOwner(address _newOwner) onlyOwner public {
        require(_newOwner != address(0));
        owner = _newOwner;
    }

    function incrementWeekOldCounter() public {
        while (blocks[weekOldBlockNumber].submittedAt < now - (1 weeks)) {
            if (blocks[weekOldBlockNumber].submittedAt == 0)
                break;
            weekOldBlockNumber++;
        }
    }

    function storeBlock(uint256 _blockNumber, bytes32 _merkleRoot) onlyOwner public returns (bool success) {
        incrementWeekOldCounter();
        require(_blockNumber == lastBlockNumber + 1);
        BlockInformation storage newBlockInformation = blocks[_blockNumber];
        newBlockInformation.merkleRootHash = _merkleRoot;
        newBlockInformation.submittedAt = now;
        lastBlockNumber = _blockNumber;
        BlockHeaderSubmitted(_blockNumber, _merkleRoot);
        return true;
    }

    function storeBlocks(uint256[] _blockNumbers, bytes32[] _merkleRoots) public returns (bool success) {
        require(_blockNumbers.length == _merkleRoots.length);
        require(_blockNumbers.length != 0);
        incrementWeekOldCounter();

        uint256 currentCounter = lastBlockNumber;
        for (uint256 i = 0; i < _blockNumbers.length; i++) {
            require(_blockNumbers[i] == currentCounter + 1);   
            currentCounter = _blockNumbers[i];
            BlockInformation storage newBlockInformation = blocks[currentCounter];
            newBlockInformation.merkleRootHash = _merkleRoots[i];
            newBlockInformation.submittedAt = now;
            BlockHeaderSubmitted(_blockNumbers[i], _merkleRoots[i]);
        }
        lastBlockNumber = currentCounter;
        return true;
    }

    function getBlockInformation(uint32 _blockNumber) public view returns (uint256 submittedAt, bytes32 merkleRoot) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return (blockInformation.submittedAt, blockInformation.merkleRootHash);
    }

    function getMerkleRoot(uint32 _blockNumber) public view returns (bytes32 merkleRoot) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return blockInformation.merkleRootHash;
    }

    function getSubmissionTime(uint32 _blockNumber) public view returns (uint256 submittedAt) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        return blockInformation.submittedAt;
    }

}