
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

contract('PlasmaParent invalid block challenges', async (accounts) => {

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
        await plasma.setOperator(operatorAddress, true, {from: operator})
        const chalAddr = await plasma.challengesContract();
        assert(chalAddr == challenger.address);
        challenger = Challenger.at(plasma.address); // instead of merging the ABI
        firstHash = await plasma.hashOfLastSubmittedBlock();
    })

    it('should stop on invalid transaction (malformed) in block - invalid amount', async () => {
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
                operatorKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const serializedTX = tx.serialize();
        const decoded = ethUtil.rlp.decode(serializedTX);

        let output = decoded[1][0][2][0];
        output[2] = Buffer.alloc(33);
        decoded[1][0][2][0] = output;
        const reencodedTX = ethUtil.rlp.encode(decoded);
        const redecoded = ethUtil.rlp.decode(reencodedTX);
        const newTree = createMerkleTree([reencodedTX]);
        const rootValue = newTree.getMerkleRoot();
        const proof = newTree.getProof(0, true);

        block.header.merkleTree = newTree;
        block.header.merkleRootHash = rootValue;
        block.sign(operatorKey);       
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('should stop on invalid transaction (malformed) in block invalid - num of arguments', async () => {
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
                operatorKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const serializedTX = tx.serialize();
        const decoded = ethUtil.rlp.decode(serializedTX);

        let output = decoded[1][0][2][0];
        decoded[1][0][2][0] = [output[0], output[1]];
        const reencodedTX = ethUtil.rlp.encode(decoded);
        const redecoded = ethUtil.rlp.decode(reencodedTX);
        const newTree = createMerkleTree([reencodedTX]);
        const rootValue = newTree.getMerkleRoot();
        const proof = newTree.getProof(0, true);

        block.header.merkleTree = newTree;
        block.header.merkleRootHash = rootValue;
        block.sign(operatorKey);       
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('should stop on invalid transaction (malformed) in block invalid - complete garbage', async () => {
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
                operatorKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const reencodedTX = Buffer.from(require("crypto").randomBytes(128));
        const newTree = createMerkleTree([reencodedTX]);
        const rootValue = newTree.getMerkleRoot();
        const proof = newTree.getProof(0, true);

        block.header.merkleTree = newTree;
        block.header.merkleRootHash = rootValue;
        block.sign(operatorKey);       
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('should NOT stop on valid transaction (not malformed) in block', async () => {
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
                operatorKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = challenger.proveInvalidTransaction(1, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof),);
        await expectThrow(submissionReceipt);
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(!plasmaIsStopped);
    })

    it('Transaction in block references the future', async () => {
        const tx = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 100,
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
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveReferencingInvalidBlock(1, 0, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Transaction references an output with tx number larger, than number in transaction in this UTXO block', async () => {
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
                operatorKey
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
        tx = createTransaction(TxTypeSplit, 0, 
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
        block = createBlock(2, 1, newHash, [tx],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
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
        const numTx = await storage.getNumberOfTransactions(2);
        submissionReceipt = await challenger.proveReferencingInvalidTransactionNumber(2, 0, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Transaction has higher number that number of transactions in block', async () => {
        const tx = createTransaction(TxTypeSplit, 100, 
            [{
                blockNumber: 100,
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
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const blockOneHeader = blockOne.slice(0,137);
        const deserialization = ethUtil.rlp.decode(blockOneArray[7]);
        let lastBlockNumber = await plasma.lastBlockNumber()
        let lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        let submissionReceipt = await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockOneHeader));
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
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveBreakingTransactionNumbering(1, 0, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

})