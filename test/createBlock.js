const Block = require("../lib/Block/RLPblock");
const ethUtil = require("ethereumjs-util");
const BN = ethUtil.BN;
const MerkleTools = require("../lib/merkle-tools");

function createBlock(blockNumber, numberOfTransactions, previousHash, transactions, privateKey) {
    const params = {
        blockNumber : (new BN(blockNumber)).toBuffer("be", 4),
        transactions : transactions,
        parentHash : ethUtil.toBuffer(previousHash),
    }
    const block = new Block(params)
    block.numberOfTransactions = (new BN(numberOfTransactions)).toBuffer("be",4)
    block.sign(privateKey);
    return block
}

function createMerkleTree(dataArray) {
    const treeOptions = {
        hashType: 'sha3'
    }
    
    const merkleTree = new MerkleTools(treeOptions)
    for (let i = 0; i < dataArray.length; i++) {
        const txHash = ethUtil.hashPersonalMessage(dataArray[i]);
        merkleTree.addLeaf(txHash);
    }  
    merkleTree.makeTree(false);
    return merkleTree
}

module.exports = {createBlock, createMerkleTree}