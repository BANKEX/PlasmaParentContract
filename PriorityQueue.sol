pragma solidity 0.4.19;

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

contract PriorityQueue {
    using SafeMath for uint256;

    /*
     *  Modifiers
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /* 
     *  Storage
     */
    address owner;
    uint256[] heapList;
    uint256 public currentSize;

    function PriorityQueue()
        public
    {
        owner = msg.sender;
        heapList = [0];
        currentSize = 0;
    }

    function insert(uint256 k) 
        public
        onlyOwner
    {
        heapList.push(k);
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
            if (heapList[i.mul(2)] < heapList[i.mul(2).add(1)]) {
                return i.mul(2);
            } else {
                return i.mul(2).add(1);
            }
        }
    }

    function getMin()
        public
        view
        returns (uint256)
    {
        return heapList[1];
    }

    function delMin()
        public
        onlyOwner
        returns (uint256)
    {
        uint256 retVal = heapList[1];
        heapList[1] = heapList[currentSize];
        delete heapList[currentSize];
        currentSize = currentSize.sub(1);
        percDown(1);
        return retVal;
    }

    function percUp(uint256 i) 
        private
    {
        while (i.div(2) > 0) {
            if (heapList[i] < heapList[i.div(2)]) {
                uint256 tmp = heapList[i.div(2)];
                heapList[i.div(2)] = heapList[i];
                heapList[i] = tmp;
            }
            i = i.div(2);
        }
    }

    function percDown(uint256 i)
        private
    {
        while (i.mul(2) <= currentSize) {
            uint256 mc = minChild(i);
            if (heapList[i] > heapList[mc]) {
                uint256 tmp = heapList[i];
                heapList[i] = heapList[mc];
                heapList[mc] = tmp;
            }
            i = mc;
        }
    }
}