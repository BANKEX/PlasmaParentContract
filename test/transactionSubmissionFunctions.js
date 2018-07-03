
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const PlasmaBuyouts = artifacts.require("PlasmaExitsProcessor");
const util = require("util");
const ethUtil = require('ethereumjs-util')
const BN = ethUtil.BN;
const t = require('truffle-test-utils')
t.init()
const expectThrow = require("../helpers/expectThrow");
const {addresses, keys} = require("./keys.js");
const {createTransaction, parseTransactionIndex} = require("./createTransaction");
const {createBlock, createMerkleTree} = require("./createBlock");
const testUtils = require('./utils');

console.log("Parent bytecode size = " + (PlasmaParent.bytecode.length -2)/2);
console.log("Challenger bytecode size = " + (Challenger.bytecode.length -2)/2);
console.log("Exit game bytecode length is " + (PlasmaBuyouts.bytecode.length -2)/2)
// const Web3 = require("web3");

const increaseTime = async function(addSeconds) {
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0})
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_mine", params: [], id: 1})
}

const {
    TxTypeFund, 
    TxTypeMerge, 
    TxTypeSplit} = require("../lib/Tx/RLPtx.js");

contract('PlasmaParent buyout procedure', async (accounts) => {

    const operatorAddress = accounts[0];
    const operatorKey = keys[0];

    let queue;
    let plasma;
    let storage;
    let challenger;
    let buyouts;
    const operator = accounts[0];

    const alice    = addresses[2];
    const aliceKey = keys[2];
    const bob      = addresses[3];
    const bobKey = keys[3];
    
    let firstHash;

    beforeEach(async () => {
        storage = await BlockStorage.new({from: operator})
        queue  = await PriorityQueue.new({from: operator})
        plasma = await PlasmaParent.new(queue.address, storage.address, {from: operator, value: "10000000000000000000"})
        await storage.setOwner(plasma.address, {from: operator})
        await queue.setOwner(plasma.address, {from: operator})
        buyouts = await PlasmaBuyouts.new(queue.address, storage.address, {from: operator});
        challenger = await Challenger.new(queue.address, storage.address, {from: operator});
        await plasma.setDelegates(challenger.address, buyouts.address, {from: operator})
        await plasma.setOperator(operatorAddress, 2, {from: operator});
        const canSignBlocks = await storage.canSignBlocks(operator);
        assert(canSignBlocks);
        
        const buyoutsAddress = await plasma.buyoutsContract();
        assert(buyoutsAddress == buyouts.address);

        const challengesAddress = await plasma.challengesContract();
        assert(challengesAddress == challenger.address);

        challenger = Challenger.at(plasma.address); // instead of merging the ABI
        buyouts = PlasmaBuyouts.at(plasma.address);
        firstHash = await plasma.hashOfLastSubmittedBlock();
    })

    it('Simulate exit procedure', async () => {
        // first we fund Alice with something
        const withdrawCollateral = await plasma.WithdrawCollateral();
        
        await plasma.deposit({from: alice, value: "10000000000000"})
        let totalDeposited = await plasma.totalAmountDeposited();
        assert(totalDeposited.toString(10) === "10000000000000");
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 1
            }],
            [{
                amount: 100,
                to: alice
            }],
                operatorKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const reencodedTXAlice = tx.serialize();
        const proofAlice = block.merkleTree.getProof(0, true);
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");

        let newHash = await plasma.hashOfLastSubmittedBlock();
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 2
            }],
            [{
                amount: 200,
                to: bob
            }],
                operatorKey
        )

        block = createBlock(2, 1, newHash, [tx],  operatorKey)
        const reencodedTXBob = tx.serialize();
        const proofBob = block.merkleTree.getProof(0, true);

        blockArray = block.serialize();
        blockHeader = Buffer.concat(blockArray).slice(0,137);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();

        bl = await storage.blocks(2);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));

        // than we spend an output, but now Bob signs instead of Alice

        newHash = await plasma.hashOfLastSubmittedBlock();
        const tx2 = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 100,
                to: bob
            }],
                aliceKey
        )
        const tx3 = createTransaction(TxTypeSplit, 1, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 100,
                to: bob
            }],
                aliceKey
        )
        block = createBlock(3, 2, newHash, [tx2, tx3],  operatorKey)
        const reencodedTX2 = tx2.serialize();
        const proof2 = Buffer.concat(block.merkleTree.getProof(0, true));

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(1, true));

        blockArray = block.serialize();
        blockHeader = Buffer.concat(blockArray).slice(0,137);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();

        bl = await storage.blocks(3);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));

        // submissionReceipt = await plasma.publishTransaction(3, ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(proof2));
        submissionReceipt = await buyouts.startExit(3, 0, ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(proof2), {from: bob, value: withdrawCollateral})

        // struct UTXO {
        //     uint160 spendingTransactionIndex;
        //     uint8 utxoStatus;
        //     bool isLinkedToLimbo;
        //     bool amountAndOwnerConfirmed;
        //     bool pendingExit;
        //     bool succesfullyWithdrawn;
        //     address collateralHolder;
        //     address originalOwner;
        //     address boughtBy;
        //     uint256 value;
        //     uint64 dateExitAllowed;
        // }

        // unspent = 1
        // spent = 2
        
        let input = await plasma.publishedUTXOs(submissionReceipt.logs[0].args._index);
        assert(submissionReceipt.logs[0].args._index.toNumber() == 2**40);
        assert(input[0].toNumber() === 3 * (2**32));
        assert(input[1].toString(10) == "2") //spent
        assert(input[2] === false); // not linked to limbo
        assert(input[3] === false); // amount and owner are not confirmed
        assert(input[4] === false); // is not pending exit
        assert(input[5] === false); // is not withdrawn
        assert(input[6] === bob); //bob holds a collateral
        assert(input[7] === alice); //alice was actual owner
        assert(input[8] == "0x0000000000000000000000000000000000000000") 
        assert(input[9].toString(10) == "100") // amount

        
        // prettyPrint(input);
        let output = await plasma.publishedUTXOs(submissionReceipt.logs[1].args._index);
        assert(submissionReceipt.logs[0].args._index.toNumber() == 2**40);
        assert(output[0].toNumber() === 0);
        assert(output[1].toString(10) == "1") //spent
        assert(output[2] === false); // not linked to limbo
        assert(output[3] === true); // amount and owner are not confirmed
        assert(output[4] === true); // is not pending exit
        assert(output[5] === false); // is not withdrawn
        assert(output[6] === "0x0000000000000000000000000000000000000000"); //output collateral is not counted
        assert(output[7] === bob); //alice was actual owner
        assert(output[8] == "0x0000000000000000000000000000000000000000") 
        assert(output[9].toString(10) == "100") // amount
        assert((submissionReceipt.logs[0].args._index).lt(submissionReceipt.logs[1].args._index)); // input index is less than output index

        // prettyPrint(output);
        let exitStartedEvent = submissionReceipt.logs[2]
        assert(exitStartedEvent.args._from == bob);
        assert(exitStartedEvent.args._priority.toString(10) == submissionReceipt.logs[0].args._index.toString(10));
        assert(exitStartedEvent.args._index.toString(10) == submissionReceipt.logs[1].args._index.toString(10));
        // let withdrawIndexBob = submissionReceipt.logs[0].args._withdrawIndex;
        // let withdrawRecordBob = await plasma.withdrawRecords(withdrawIndexBob);
        // assert(withdrawRecordBob[8].toString(10) === "200");
        // assert(withdrawRecordBob[7] === bob);


        // let size = await queue.currentSize();
        // assert(size.toString(10) === "2");
        // let minimalItem = await queue.getMin();
        // assert(minimalItem.eq(withdrawIndexAlice));

        // const delay = await plasma.ExitDelay();
        // await increaseTime(delay.toNumber() + 1);

        // submissionReceipt = await plasma.finalizeExits(1);

        // size = await queue.currentSize();
        // assert(size.toString(10) === "1");

        // minimalItem = await queue.getMin();
        // assert(minimalItem.eq(withdrawIndexBob));

        // submissionReceipt = await plasma.finalizeExits(1);
        
        // size = await queue.currentSize();
        // assert(size.toString(10) === "0");

    })
})

function prettyPrint(res) {
    for (let field of res) {
        console.log(field.toString(10));
    }
}

