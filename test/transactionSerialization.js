
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const TXTester = artifacts.require("TXTester");
const util = require("util");
const ethUtil = require('ethereumjs-util')
const BN = ethUtil.BN;
const t = require('truffle-test-utils')
t.init()
const expectThrow = require("../helpers/expectThrow");
const {addresses, keys} = require("./keys.js");
const {createTransaction} = require("./createTransaction");
const {createBlock, createMerkleTree} = require("./createBlock");
const testUtils = require('./utils');

// const Web3 = require("web3");

const increaseTime = async function(addSeconds) {
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0})
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_mine", params: [], id: 1})
}

const {
    TxTypeFund, 
    TxTypeMerge, 
    TxTypeSplit} = require("../lib/Tx/RLPtx.js");

contract('Transaction deserialization tester', async (accounts) => {

    const operatorAddress = accounts[0];
    const operatorKey = keys[0];
    let txTester;

    const operator = accounts[0];

    const alice    = addresses[2];
    const aliceKey = keys[2];
    const bob      = addresses[3];
    const bobKey = keys[3];
    
    let firstHash;

    beforeEach(async () => {
        txTester = await TXTester.new({from: operator});
    })

    it('should give proper information about the TX', async () => {
        const tx = createTransaction(TxTypeSplit, 100, 
            [{
                blockNumber: 1,
                txNumberInBlock: 200,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const reencodedTX = tx.serialize();
        const info = await txTester.parseTransaction(ethUtil.bufferToHex(reencodedTX));
        const txNumberInBlock = info[0].toNumber();
        const txType = info[1].toNumber();
        const inputsLength = info[2].toNumber();
        const outputsLength = info[3].toNumber();
        const sender = info[4];
        const isWellFormed = info[5];
        assert(isWellFormed);
        assert(sender === alice);
        assert(txType === TxTypeSplit);
        assert(inputsLength === 1);
        assert(outputsLength === 1);
        assert(txNumberInBlock === 100);
    });

    it('should give proper information about the TX input', async () => {
        const tx = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 200,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const reencodedTX = tx.serialize();
        const info = await txTester.getInputInfo(ethUtil.bufferToHex(reencodedTX), 0);
        const blockNumber = info[0].toNumber();
        const txNumberInBlock = info[1].toNumber();
        const outputNumber = info[2].toNumber();
        const amount = info[3].toString(10);
        assert(blockNumber === 1);
        assert(txNumberInBlock === 200);
        assert(outputNumber === 0);
        assert(amount === ""+10);
    });

    it('should give proper information about the TX output', async () => {
        const tx = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 200,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: bob
            }],
                aliceKey
        )
        const reencodedTX = tx.serialize();
        const info = await txTester.getOutputInfo(ethUtil.bufferToHex(reencodedTX), 0);
        const outputNumber = info[0].toNumber();
        const recipient = info[1];
        const amount = info[2].toString(10);
        assert(outputNumber === 0);
        assert(recipient === bob);
        assert(amount === ""+10);
    });

})