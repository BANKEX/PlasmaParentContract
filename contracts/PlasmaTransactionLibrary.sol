pragma solidity ^0.4.21;

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
    }

    bytes constant PersonalMessagePrefixBytes = "\x19Ethereum Signed Message:\n";

    function createPersonalMessageTypeHash(bytes memory message) internal pure returns (bytes32 msgHash) {
        bytes memory lengthBytes = message.length.uintToBytes();
        return keccak256(PersonalMessagePrefixBytes, lengthBytes, message);
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
                h = keccak256(h, elProvided);
            } else {
                h = keccak256(elProvided, h);
            }
        }
        return h == root;
    }

    function plasmaTransactionFromBytes(bytes _rawTX) internal view returns (PlasmaTransaction memory TX) {
        RLP.RLPItem memory item = _rawTX.toRLPItem(true);
        RLP.Iterator memory iter = item.iterator();
        item = iter.next(true);
        uint32 numInBlock = uint32(item.toUint());
        item = iter.next(true);
        TX = signedPlasmaTransactionFromRLPItem(item);
        TX.txNumberInBlock = numInBlock;
        return TX;
    }

    function signedPlasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal view returns (PlasmaTransaction memory TX) {
        RLP.Iterator memory iter = _item.iterator();
        RLP.RLPItem memory item = iter.next(true);
        bytes memory rawSignedPart = item.toBytes();
        bytes32 persMessageHashWithoutNumber = createPersonalMessageTypeHash(rawSignedPart);
        TX = plasmaTransactionFromRLPItem(item);
        item = iter.next(true);
        uint8 v = uint8(item.toUint());
        item = iter.next(true);
        bytes32 r = item.toBytes32();
        item = iter.next(true);
        bytes32 s = item.toBytes32();
        TX.sender = ecrecover(persMessageHashWithoutNumber, v, r, s);
        return TX;
    }

    function plasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal pure returns (PlasmaTransaction memory TX) {
        RLP.Iterator memory iter = _item.iterator();
        RLP.RLPItem memory item = iter.next(true); // transaction type
        uint256[] memory reusableSpace = new uint256[](7);
        reusableSpace[0] = item.toUint();
        item = iter.next(true);
        require(item.isList());
        RLP.Iterator memory reusableIterator = item.iterator();
        RLP.Iterator memory reusableIteratorPerItem;
        TransactionInput[] memory inputs = new TransactionInput[](item.items());
        reusableSpace[1] = 0;
        while (reusableIterator.hasNext()) {
            reusableIteratorPerItem = reusableIterator.next(true).iterator();
            reusableSpace[2] = reusableIteratorPerItem.next(true).toUint();
            reusableSpace[3] = reusableIteratorPerItem.next(true).toUint();
            reusableSpace[4] = reusableIteratorPerItem.next(true).toUint();
            reusableSpace[5] = reusableIteratorPerItem.next(true).toUint();
            require(!reusableIteratorPerItem.hasNext());
            TransactionInput memory input = TransactionInput({
                blockNumber: uint32(reusableSpace[2]),
                txNumberInBlock: uint32(reusableSpace[3]),
                outputNumberInTX: uint8(reusableSpace[4]),
                amount: reusableSpace[5]
            });
            inputs[reusableSpace[1]] = input;
            reusableSpace[1]++;
        }
        item = iter.next(true);
        require(item.isList());
        reusableIterator = item.iterator();
        TransactionOutput[] memory outputs = new TransactionOutput[](item.items());
        reusableSpace[1] = 0;
        while (reusableIterator.hasNext()) {
            reusableIteratorPerItem = reusableIterator.next(true).iterator();
            reusableSpace[2] = reusableIteratorPerItem.next(true).toUint();
            address recipient = reusableIteratorPerItem.next(true).toAddress();
            reusableSpace[3] = reusableIteratorPerItem.next(true).toUint();
            require(!reusableIteratorPerItem.hasNext());
            TransactionOutput memory output = TransactionOutput({
                outputNumberInTX: uint8(reusableSpace[2]),
                recipient: recipient,
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
            sender: address(0)
        });
        return TX;
    }

    function makeTransactionIndex(uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX) internal pure returns (uint256 index) {
        index += uint256(_blockNumber) << ((TxNumberLength + TxOutputNumberLength)*8);
        index += uint256(_txNumberInBlock) << (TxOutputNumberLength*8);
        index += uint256(_outputNumberInTX);
        return index;
    }
}