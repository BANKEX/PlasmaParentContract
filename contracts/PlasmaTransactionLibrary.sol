pragma solidity ^0.4.24;

import {RLP} from "./RLP.sol";
import {Conversion} from "./Conversion.sol";

library BankexPlasmaTransaction {

    using RLP for RLP.RLPItem;
    using RLP for RLP.Iterator;
    using RLP for bytes;
    using Conversion for uint256;

    uint256 public constant BlockNumberLength = 4;
    uint256 public constant TxNumberLength = 4;
    uint256 public constant TxTypeLength = 1;
    uint256 public constant TxOutputNumberLength = 1;

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    struct TransactionInput {
        uint32 blockNumber;
        uint32 txNumberInBlock;
        uint8 outputNumberInTX;
        uint256 amount;
    }

    struct TransactionOutput {
        address recipient;
        uint8 outputNumberInTX;
        uint256 amount;
    }

    struct PlasmaTransaction {
        uint32 txNumberInBlock;
        uint8 txType;
        TransactionInput[] inputs;
        TransactionOutput[] outputs;
        address sender;
        bool isWellFormed;
    }

    bytes constant PersonalMessagePrefixBytes = "\x19Ethereum Signed Message:\n";

    function createPersonalMessageTypeHash(bytes memory message) internal pure returns (bytes32 msgHash) {
        bytes memory lengthBytes = message.length.uintToBytes();
        return keccak256(abi.encodePacked(PersonalMessagePrefixBytes, lengthBytes, message));
    }

    function checkForInclusionIntoBlock(bytes32 _merkleRoot, bytes _plasmaTransaction, bytes _merkleProof) internal pure returns (bool included) {
        included = checkProof(_merkleRoot, _plasmaTransaction, _merkleProof, true);
        return included;
    }

    function checkProof(bytes32 root, bytes data, bytes proof, bool convertToMessageHash) internal pure returns (bool) {
        bytes32 h;
        if (convertToMessageHash) {
            h = createPersonalMessageTypeHash(data);
        } else {
            h = keccak256(data);
        }
        bytes32 elProvided;
        uint8 rightElementProvided;
        uint32 loc;
        uint32 elLoc;
        for (uint32 i = 32; i <= uint32(proof.length); i += 33) {
            assembly {
                loc  := proof
                elLoc := add(loc, add(i, 1))
                elProvided := mload(elLoc)
            }
            rightElementProvided = uint8(bytes1(0xff)&proof[i-32]);
            if (rightElementProvided > 0) {
                h = keccak256(abi.encodePacked(h, elProvided));
            } else {
                h = keccak256(abi.encodePacked(elProvided, h));
            }
        }
        return h == root;
    }

    function plasmaTransactionFromBytes(bytes _rawTX) internal view returns (PlasmaTransaction memory TX) {
        RLP.RLPItem memory item = _rawTX.toRLPItem();
        if (!item._validate()) {
            return constructEmptyTransaction();
        }
        if (!item.isList()) {
            return constructEmptyTransaction();
        }
        uint256 numItems = item.items();
        if (numItems != 2) {
            return constructEmptyTransaction();
        }
        RLP.Iterator memory iter = item.iterator();
        item = iter.next();
        (uint256 numInBlock, bool valid) = item.toUint(TxNumberLength);
        if (!valid) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        TX = signedPlasmaTransactionFromRLPItem(item);
        if (!TX.isWellFormed) {
            return constructEmptyTransaction();
        }
        TX.txNumberInBlock = uint32(numInBlock);
        return TX;
    }

    function signedPlasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal view returns (PlasmaTransaction memory TX) {
        if (!_item.isList()) {
            return constructEmptyTransaction();
        }
        uint256 numItems = _item.items();
        if (numItems != 4) {
            return constructEmptyTransaction();
        }
        RLP.Iterator memory iter = _item.iterator();
        RLP.RLPItem memory item = iter.next();
        bytes memory rawSignedPart = item.toBytes();
        bytes32 persMessageHashWithoutNumber = createPersonalMessageTypeHash(rawSignedPart);
        TX = plasmaTransactionFromRLPItem(item);
        if (!TX.isWellFormed) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        (uint256 v_tmp, bool valid) = item.toUint(1);
        uint8 v = uint8(v_tmp);
        if (!valid) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        bytes32 r;
        (r, valid) = item.toBytes32();
        if (!valid) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        bytes32 s;
        (s, valid) = item.toBytes32();
        if (!valid) {
            return constructEmptyTransaction();
        }
        TX.sender = ecrecover(persMessageHashWithoutNumber, v, r, s);
        if (TX.sender == address(0)) {
            return constructEmptyTransaction();
        }
        return TX;
    }

    function plasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal pure returns (PlasmaTransaction memory TX) {
        if (!_item.isList()) {
            return constructEmptyTransaction();
        }
        uint256 numItems = _item.items();
        if (numItems != 3) {
            return constructEmptyTransaction();
        }
        RLP.Iterator memory iter = _item.iterator();
        if (!iter.hasNext()) {
            return constructEmptyTransaction();
        }
        RLP.RLPItem memory item = iter.next(); // transaction type
        bool reusableValidFlag = false;
        uint256[] memory reusableSpace = new uint256[](7);
        (reusableSpace[0], reusableValidFlag) = item.toUint(TxTypeLength); //hardcode can be used
        uint256 txType = reusableSpace[0];
        if (!(txType == TxTypeFund || txType == TxTypeSplit || txType == TxTypeMerge) ) {
            return constructEmptyTransaction();
        }
        if (!reusableValidFlag) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        if (!item.isList()) {
            return constructEmptyTransaction();
        }
        numItems = item.items();
        if (numItems == 0) {
            return constructEmptyTransaction();
        }
        RLP.Iterator memory reusableIterator = item.iterator();
        RLP.Iterator memory reusableIteratorPerItem;
        TransactionInput[] memory inputs = new TransactionInput[](numItems);
        reusableSpace[1] = 0;
        while (reusableIterator.hasNext()) { // go over the inputs
            item = reusableIterator.next();
            if (!item.isList()) {
                return constructEmptyTransaction();
            }
            numItems = item.items();
            if (numItems != 4) {
                return constructEmptyTransaction();
            }
            reusableIteratorPerItem = item.iterator();
            (reusableSpace[2], reusableValidFlag) = reusableIteratorPerItem.next().toUint(BlockNumberLength); // block number
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            (reusableSpace[3], reusableValidFlag) = reusableIteratorPerItem.next().toUint(TxNumberLength); // tx number in block
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            (reusableSpace[4], reusableValidFlag) = reusableIteratorPerItem.next().toUint(TxOutputNumberLength); //tx output number in tx
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            (reusableSpace[5], reusableValidFlag) = reusableIteratorPerItem.next().toUint(32); //tx amount
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            TransactionInput memory input = TransactionInput({
                blockNumber: uint32(reusableSpace[2]),
                txNumberInBlock: uint32(reusableSpace[3]),
                outputNumberInTX: uint8(reusableSpace[4]),
                amount: reusableSpace[5]
            });
            inputs[reusableSpace[1]] = input;
            reusableSpace[1]++;
        } // now we have completed parsing all the inputs
        if (!iter.hasNext()) {
            return constructEmptyTransaction();
        }
        item = iter.next();
        if(!item.isList()){
            return constructEmptyTransaction();
        }
        reusableIterator = item.iterator();
        numItems = item.items();
        if (numItems == 0) {
            return constructEmptyTransaction();
        }
        TransactionOutput[] memory outputs = new TransactionOutput[](numItems);
        reusableSpace[1] = 0;
        address reusableRecipient;
        while (reusableIterator.hasNext()) { // go over outputs
            item = reusableIterator.next();
            if (!item.isList()) {
                return constructEmptyTransaction();
            }
            numItems = item.items();
            if (numItems != 3) {
                return constructEmptyTransaction();
            }
            reusableIteratorPerItem = item.iterator();
            if (!reusableIteratorPerItem.hasNext()) {
                return constructEmptyTransaction();
            }
            (reusableSpace[2], reusableValidFlag) = reusableIteratorPerItem.next().toUint(TxOutputNumberLength); // output numbber
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            (reusableRecipient, reusableValidFlag) = reusableIteratorPerItem.next().toAddress(); // recipient
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            (reusableSpace[3], reusableValidFlag) = reusableIteratorPerItem.next().toUint(32); //amount
            if (!reusableValidFlag) {
                return constructEmptyTransaction();
            }
            TransactionOutput memory output = TransactionOutput({
                outputNumberInTX: uint8(reusableSpace[2]),
                recipient: reusableRecipient,
                amount: reusableSpace[3]
            });
            outputs[reusableSpace[1]] = output;
            reusableSpace[1]++;
        }
        TX = PlasmaTransaction({
            txNumberInBlock: 0,
            txType: uint8(reusableSpace[0]),
            inputs: inputs,
            outputs: outputs,
            sender: address(0),
            isWellFormed: true
        });
        return TX;
    }

    function makeTransactionIndex(uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX) internal pure returns (uint256 index) {
        index += ( uint256(_blockNumber) << ((TxNumberLength + TxOutputNumberLength)*8) );
        index += ( uint256(_txNumberInBlock) << (TxOutputNumberLength*8) );
        index += uint256(_outputNumberInTX);
        return index;
    }

    function parseTransactionIndex(uint256 _index) internal pure returns (uint32 blockNumber, uint32 txNumberInBlock, uint8 outputNumber) {
        uint256 idx = _index % (uint256(1) << 128);
        outputNumber = uint8(idx % (uint256(1) << TxOutputNumberLength*8));
        idx = idx >> (TxOutputNumberLength*8);
        txNumberInBlock = uint32(idx % (uint256(1) << TxNumberLength*8));
        idx = idx >> (TxNumberLength*8);
        blockNumber = uint32(idx % (uint256(1) << BlockNumberLength*8));
        return (blockNumber, txNumberInBlock, outputNumber);
    }

    function constructEmptyTransaction() internal pure returns (PlasmaTransaction memory TX) {
        TransactionInput[] memory inputs = new TransactionInput[](0);
        TransactionOutput[] memory outputs = new TransactionOutput[](0);
        TX = PlasmaTransaction({
            txNumberInBlock: 0,
            txType: 0,
            sender: address(0),
            inputs: inputs,
            outputs: outputs,
            isWellFormed: false
        });
    }
}