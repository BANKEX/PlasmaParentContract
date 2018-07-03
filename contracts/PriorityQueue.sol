pragma solidity ^0.4.24;

// original source from https://github.com/DavidKnott
// https://github.com/omisego/plasma-mvp/blob/master/plasma/root_chain/contracts/RootChain/RootChain.sol

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

interface PriorityQueueInterface {
    function insert(uint72 _priority, uint8 _type, bytes22 _index) external;
    function minChild(uint256 i) view external returns (uint256);
    function getMin() external view returns (uint8 recordType, bytes22 index);
    function delMin() external returns (uint8 recordType, bytes22 index);
    function currentSize() external returns (uint256);
}

contract PriorityQueue {
    using SafeMath for uint256;
    /*
     *  Modifiers
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setOwner (address _newOwner) onlyOwner public {
        require(_newOwner != address(0));
        owner = _newOwner;
    }

    /*
     *  Storage
     */

    uint8 constant RecordTypeIndex = 1;
    uint8 constant RecordTypeHash = 2;

    struct QueueItem {
        uint72 priority;
        uint8 recordType;
        bytes22 withdrawIndex;
    }
    
    address public owner;
    QueueItem[] public heapList;
    uint256 public currentSize;

    constructor () public
    {
        owner = msg.sender;
        QueueItem memory item = QueueItem({
            priority: 0,
            recordType: 0,
            withdrawIndex: bytes22(0)
        });
        heapList.push(item);
        currentSize = 0;
    }

    function insert(uint72 _priority, uint8 _type, bytes22 _index)
        public
        onlyOwner
    {
        require(_type == RecordTypeIndex || _type == RecordTypeHash);
        heapList.push(QueueItem({
            priority: _priority,
            recordType: _type,
            withdrawIndex: _index
        }));
        currentSize = currentSize.add(1);
        percUp(currentSize);
    }

    function minChild(uint256 i)
        public
        view
        returns (uint256)
    {
        if (i.mul(2).add(1) > currentSize) {
            return i.mul(2);
        } else {
            if (heapList[i.mul(2)].priority < heapList[i.mul(2).add(1)].priority) {
                return i.mul(2);
            } else {
                return i.mul(2).add(1);
            }
        }
    }

    function getMin()
        public
        view
        returns (uint8 recordType, bytes22 index)
    {
        return (heapList[1].recordType, heapList[1].withdrawIndex);
    }

    function delMin()
        public
        onlyOwner
        returns (uint8 recordType, bytes22 index)
    {
        require(currentSize > 0);
        recordType = heapList[1].recordType;
        index = heapList[1].withdrawIndex;
        heapList[1] = heapList[currentSize];
        delete heapList[currentSize];
        currentSize = currentSize.sub(1);
        percDown(1);
        return (recordType, index);
    }

    function percUp(uint256 j)
        private
    {   
        uint256 i = j;
        QueueItem memory tmp;
        while (i.div(2) > 0) {
            if (heapList[i].priority < heapList[i.div(2)].priority) {
                tmp = heapList[i.div(2)];
                heapList[i.div(2)] = heapList[i];
                heapList[i] = tmp;
            }
            i = i.div(2);
        }
    }

    function percDown(uint256 j)
        private
    {
        uint256 i = j;
        QueueItem memory tmp;
        while (i.mul(2) <= currentSize) {
            uint256 mc = minChild(i);
            if (heapList[i].priority > heapList[mc].priority) {
                tmp = heapList[i];
                heapList[i] = heapList[mc];
                heapList[mc] = tmp;
            }
            i = mc;
        }
    }
}