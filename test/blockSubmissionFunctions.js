
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const util = require("util");
const ethUtil = require('ethereumjs-util')
const BN = ethUtil.BN;
const t = require('truffle-test-utils')
t.init()
const expectThrow = require("../helpers/expectThrow");
const {addresses, keys} = require("./keys.js");
const createTransaction = require("./createTransaction");
const {createBlock} = require("./createBlock");
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

contract('PlasmaParent block submission', async (accounts) => {

    const operatorAddress = accounts[0];
    const operatorKey = keys[0];

    let queue;
    let plasma;
    let storage;
    let challenger;

    const operator = accounts[0];

    const alice    = addresses[2];
    const aliceKey = keys[2];
    const bob      = addresses[3];
    const bobKey = keys[3];
    
    let firstHash;

    beforeEach(async () => {
        storage = await BlockStorage.new({from: operator})
        queue  = await PriorityQueue.new({from: operator})
        plasma = await PlasmaParent.new(queue.address, storage.address, {from: operator})
        await storage.setOwner(plasma.address, {from: operator})
        await queue.setOwner(plasma.address, {from: operator})
        challenger = await Challenger.new(queue.address, storage.address, {from: operator})
        await plasma.setChallenger(challenger.address, {from: operator})
        await plasma.setOperator(operatorAddress, true, {from: operator});
        firstHash = await plasma.hashOfLastSubmittedBlock();
    })

    it('should accept one properly signed header', async () => {
        const tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        const submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
    })

    it('should NOT accept same header twice', async () => {
        const tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        const submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        const repeatedSubmission = plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
        await expectThrow(repeatedSubmission);
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
    })

    it('should accept two headers in right sequence', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        let allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        let get = util.promisify(allEvents.get.bind(allEvents))
        let evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 1,
                 _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        }, 'The event is emitted');
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));

        const newHash = await plasma.hashOfLastSubmittedBlock();
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, newHash, [tx],  operatorKey)
        blockArray = block.serialize();
        blockHeader = Buffer.concat(blockArray).slice(0,137);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();

        allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        get = util.promisify(allEvents.get.bind(allEvents))
        evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 2,
                 _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        }, 'The event is emitted');

        bl = await storage.blocks(2);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));

    })

    it('should accept two headers in right sequence in the same transaction', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let hash1 = block.header.merkleRootHash
        const newHash = block.hash(true);
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 100,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, newHash, [tx],  operatorKey)
        let hash2 = block.header.merkleRootHash
        blockArray = block.serialize();
        blockHeader = Buffer.concat([blockHeader,Buffer.concat(blockArray).slice(0,137)]);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "2");
        let allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        let get = util.promisify(allEvents.get.bind(allEvents))
        let evs = await get()
        assert.web3Events({logs: evs}, [{
                event: 'BlockHeaderSubmitted',
                args: {_blockNumber: 1,
                     _merkleRoot: ethUtil.bufferToHex(hash1)
                    }
            }, {
                event: 'BlockHeaderSubmitted',
                args: {_blockNumber: 2,
                    _merkleRoot: ethUtil.bufferToHex(hash2)}
            }
        ], 'The event is emitted');

        bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(hash1));
        bl = await storage.blocks(2);
        assert(bl[2] == ethUtil.bufferToHex(hash2));
    })

    it('should NOT accept two headers in wrong sequence', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let hash1 = block.header.merkleRootHash
        const newHash = block.hash(true);
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 100,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, newHash, [tx],  operatorKey)
        let hash2 = block.header.merkleRootHash
        blockArray = block.serialize();
        blockHeader = Buffer.concat([Buffer.concat(blockArray).slice(0,137), blockHeader]);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        await expectThrow(submissionReceipt);
    })

    it('should NOT accept invalidly signed block header', async () => {
        const tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const block = createBlock(1, 1, firstHash, [tx],  aliceKey)
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        const submissionReceipt = plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
        await expectThrow(submissionReceipt);
    })

    it('should NOT accept invalidly signed block header in sequence in one transaction', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let hash1 = block.header.merkleRootHash
        const newHash = block.hash(true);
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 100,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, newHash, [tx],  aliceKey)
        let hash2 = block.header.merkleRootHash
        blockArray = block.serialize();
        blockHeader = Buffer.concat([blockHeader,Buffer.concat(blockArray).slice(0,137)]);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        await expectThrow(submissionReceipt);
    })

    it('should check block hashes match in addition to block numbers in sequence', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let hash1 = block.header.merkleRootHash
        const newHash = block.hash(true);
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 100,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, firstHash, [tx],  operatorKey)
        let hash2 = block.header.merkleRootHash
        blockArray = block.serialize();
        blockHeader = Buffer.concat([blockHeader,Buffer.concat(blockArray).slice(0,137)]);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        await expectThrow(submissionReceipt);
    })

    it('should propery update two weeks old block number', async () => {
        let tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        let blockArray = block.serialize();
        let blockHeader = Buffer.concat(blockArray).slice(0,137);
        let deserialization = ethUtil.rlp.decode(blockArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        let allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        let get = util.promisify(allEvents.get.bind(allEvents))
        let evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 1,
                 _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        }, 'The event is emitted');
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));

        const newHash = await plasma.hashOfLastSubmittedBlock();
        tx = createTransaction(TxTypeFund, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 0
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        block = createBlock(2, 0, newHash, [tx],  operatorKey)
        blockArray = block.serialize();
        blockHeader = Buffer.concat(blockArray).slice(0,137);
        deserialization = ethUtil.rlp.decode(blockArray[7]);
        submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
        lastBlockNumber = await plasma.lastBlockNumber();

        allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        get = util.promisify(allEvents.get.bind(allEvents))
        evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 2,
                 _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        }, 'The event is emitted');

        bl = await storage.blocks(2);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        await increaseTime(60*60*24*14 + 1);
        await storage.incrementWeekOldCounter();

        let oldBlock = await storage.weekOldBlockNumber();
        assert(oldBlock.toString(10) === "2");
    })

})