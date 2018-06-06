
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const PlasmaBuyouts = artifacts.require("PlasmaBuyouts");
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
        plasma = await PlasmaParent.new(queue.address, storage.address, {from: operator})
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        let root = await storage.getMerkleRoot(1);
        assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = challenger.proveInvalidTransaction(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof),);
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
                amount: 10
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveReferencingInvalidBlock(1, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
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
        submissionReceipt = await challenger.proveReferencingInvalidTransactionNumber(2, 0, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Transaction has higher number that number of transactions in block', async () => {
        const tx = createTransaction(TxTypeSplit, 100, 
            [{
                blockNumber: 100,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 10
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveBreakingTransactionNumbering(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Two transactions have the same number in block', async () => {
        const tx = createTransaction(TxTypeSplit, 1, 
            [{
                blockNumber: 100,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const tx2 = createTransaction(TxTypeSplit, 1, 
            [{
                blockNumber: 100,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 2, firstHash, [tx, tx2],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
        assert(block.merkleTree.validateProof(block.merkleTree.getProof(0, false), tx.hash(), block.header.merkleRootHash));
        const reencodedTX2 = tx2.serialize();
        const proof2 = block.merkleTree.getProof(1, true);
        assert(block.merkleTree.validateProof(block.merkleTree.getProof(1, false), tx2.hash(), block.header.merkleRootHash));
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveTwoTransactionsWithTheSameNumber(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(Buffer.concat(proof)), ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(Buffer.concat(proof2)));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Transaction is malformed (balance breaking)', async () => {
        const tx = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 10
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        let block = createBlock(1, 1, firstHash, [tx],  operatorKey) // first create normal block, than replace a transaction manually

        const tx2 = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 1
            }],
            [{
                amount: 10,
                to: alice
            }],
                aliceKey
        )
        const reencodedTX = tx2.serialize();
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
        await testUtils.expectEvents(
            storage,
            submissionReceipt.receipt.blockNumber,
            'BlockHeaderSubmitted',
            {_blockNumber: 1, _merkleRoot: ethUtil.bufferToHex(block.header.merkleRootHash)}
        );
        let bl = await storage.blocks(1);
        assert(bl[2] == ethUtil.bufferToHex(block.header.merkleRootHash));
        // let root = await storage.getMerkleRoot(1);
        // assert(root = ethUtil.bufferToHex(ethUtil.hashPersonalMessage(reencodedTX)));
        submissionReceipt = await challenger.proveInvalidTransaction(1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Spend without owner signature', async () => {
        // first we fund Alice with something
        
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
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
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

        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
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
                bobKey
        )
        block = createBlock(2, 1, newHash, [tx2],  operatorKey)
        const reencodedTX2 = tx2.serialize();
        const proof2 = block.merkleTree.getProof(0, true);
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
                            // uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            // uint32 _plasmaTxNumInBlock,
                            // bytes _plasmaTransaction,
                            // bytes _merkleProof,
                            // uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
                            // uint32 _originatingPlasmaTxNumInBlock,
                            // bytes _originatingPlasmaTransaction,
                            // bytes _originatingMerkleProof,
                            // uint256 _inputOfInterest
                            
        submissionReceipt = await challenger.proveBalanceOrOwnershipBreakingBetweenInputAndOutput(
            2, ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(proof2),
            1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof),
            0);
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('UTXO amount is not equal to input amount', async () => {
        // first we fund Alice with something
        
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
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
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

        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
        const tx2 = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 1000
            }],
            [{
                amount: 1000,
                to: bob
            }],
                aliceKey
        )
        block = createBlock(2, 1, newHash, [tx2],  operatorKey)
        const reencodedTX2 = tx2.serialize();
        const proof2 = block.merkleTree.getProof(0, true);
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
                            // uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            // uint32 _plasmaTxNumInBlock,
                            // bytes _plasmaTransaction,
                            // bytes _merkleProof,
                            // uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
                            // uint32 _originatingPlasmaTxNumInBlock,
                            // bytes _originatingPlasmaTransaction,
                            // bytes _originatingMerkleProof,
                            // uint256 _inputOfInterest
                            
        submissionReceipt = await challenger.proveBalanceOrOwnershipBreakingBetweenInputAndOutput(
            2, ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(proof2),
            1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof),
            0);
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Double spend', async () => {
        // first we fund Alice with something
        
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
        const reencodedTX = tx.serialize();
        const proof = block.merkleTree.getProof(0, true);
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

        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
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
        block = createBlock(2, 2, newHash, [tx2, tx3],  operatorKey)
        const reencodedTX2 = tx2.serialize();
        const proof2 = Buffer.concat(block.merkleTree.getProof(0, true));

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(1, true));

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
        // function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
        //     uint32 _plasmaTxNumInBlock1,
        //     uint8 _inputNumber1,
        //     bytes _plasmaTransaction1,
        //     bytes _merkleProof1,
        //     uint32 _plasmaBlockNumber2, //references and proves transaction number 2
        //     uint32 _plasmaTxNumInBlock2,
        //     uint8 _inputNumber2,
        //     bytes _plasmaTransaction2,
        //     bytes _merkleProof2)
                            
        submissionReceipt = await challenger.proveDoubleSpend(
            2, 0, ethUtil.bufferToHex(reencodedTX2), ethUtil.bufferToHex(proof2),
            2, 0, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3));
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Transaction is malformed (invalid merge by Plasma owner)', async () => {
        // first we fund Alice with something
        
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

        let tx2 = createTransaction(TxTypeFund, 1, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 2
            }],
            [{
                amount: 100,
                to: alice
            }],
                operatorKey
        )
        let block = createBlock(1, 2, firstHash, [tx, tx2],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = Buffer.concat(block.merkleTree.getProof(0, true));
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

        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
        const tx3 = createTransaction(TxTypeMerge, 1, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            },
            {
                blockNumber: 1,
                txNumberInBlock: 1,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 200,
                to: bob
            }],
                operatorKey
        )
        block = createBlock(2, 1, newHash, [tx3],  operatorKey)

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(0, true));

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
        // function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
        //     uint32 _plasmaTxNumInBlock1,
        //     uint8 _inputNumber1,
        //     bytes _plasmaTransaction1,
        //     bytes _merkleProof1,
        //     uint32 _plasmaBlockNumber2, //references and proves transaction number 2
        //     uint32 _plasmaTxNumInBlock2,
        //     uint8 _inputNumber2,
        //     bytes _plasmaTransaction2,
        //     bytes _merkleProof2)
                            
        submissionReceipt = await challenger.proveBalanceOrOwnershipBreakingBetweenInputAndOutput(
            2, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3),
            1, ethUtil.bufferToHex(reencodedTX), ethUtil.bufferToHex(proof),
            0);
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);
    })

    it('Should have interactive challenge (show me the referenced input)', async () => {
        // first we fund Alice with something
        const withdrawCollateral = await plasma.WithdrawCollateral();

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

        let tx2 = createTransaction(TxTypeFund, 1, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 2
            }],
            [{
                amount: 100,
                to: alice
            }],
                operatorKey
        )
        let block = createBlock(1, 2, firstHash, [tx, tx2],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = Buffer.concat(block.merkleTree.getProof(0, true));
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

        // should be in principle able to withdraw an output before the procedure

        const succ = await plasma.startWithdraw.call(1, 0,ethUtil.bufferToHex(reencodedTX),
        ethUtil.bufferToHex(proof), {from: alice, value: withdrawCollateral});

        assert(succ[0]);


        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
        const tx3 = createTransaction(TxTypeMerge, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            },
            {
                blockNumber: 1,
                txNumberInBlock: 1,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 200,
                to: alice
            }],
                operatorKey
        )
        block = createBlock(2, 1, newHash, [tx3],  operatorKey)

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(0, true));

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
        // startShowMeTheInputChallenge(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
        //     uint8 _inputNumber,
        //     bytes _plasmaTransaction,
        //     bytes _merkleProof)
        
        submissionReceipt = await challenger.startShowMeTheInputChallenge(
            2, 0, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3), {from: bob, value: withdrawCollateral});

        let allLogs = submissionReceipt.logs;
        let from = allLogs[0].args._from;
        let inputIndex = allLogs[0].args._inputIndex;
        let outputIndex = allLogs[0].args._outputIndex;
        let {blockNumber, txNumber, outputNumber} = parseTransactionIndex(outputIndex.toString(10));
        assert(from == bob);
        assert(blockNumber.toNumber() === 1);
        assert(txNumber.toNumber() === 0);
        assert(outputNumber.toNumber() === 0);

        submissionReceipt = await challenger.respondShowMeTheInputChallenge(inputIndex, ethUtil.bufferToHex(reencodedTX),
                                                ethUtil.bufferToHex(proof), {from: operator});

        // await testUtils.expectEvents(
        //     challenger,
        //     submissionReceipt.receipt.blockNumber,
        //     'ShowInputChallengeRespondedEvent',
        //     {_from: operator,
        //     _inputIndex: inputIndex,
        //     _outputIndex: outputIndex}
        // );

        let challenge = await plasma.showInputChallengeStatuses(inputIndex);
        ({blockNumber, txNumber, outputNumber} = parseTransactionIndex(outputIndex.toString(10)));
        assert(challenge[0] === bob);
        assert(challenge[1].toString(10) === blockNumber.toString(10));
        assert(challenge[2].toString(10) === txNumber.toString(10));
        assert(challenge[3].toString(10) === outputNumber.toString(10));
        let spendingRecord = await plasma.transactionsSpendingRecords(outputIndex);
        assert(spendingRecord.eq(inputIndex));
        allLogs = submissionReceipt.logs;
        from = allLogs[0].args._from;
        outputIndex = allLogs[0].args._outputIndex;
        ({blockNumber, txNumber, outputNumber} = parseTransactionIndex(outputIndex.toString(10)));
        assert(from == operator);
        assert(blockNumber.toNumber() === 1);
        assert(txNumber.toNumber() === 0);
        assert(outputNumber.toNumber() === 0);
                    
        /// should not be able to start a withdraw process after output was shown as spent

        // startWithdraw(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
        //     uint32 _plasmaTxNumInBlock,
        //     uint8 _outputNumber,
        //     bytes _plasmaTransaction,
        //     bytes _merkleProof)

        await expectThrow(plasma.startWithdraw.call(1, 0,ethUtil.bufferToHex(reencodedTX),
        ethUtil.bufferToHex(proof), {from: alice, value: withdrawCollateral}));

    })

    it('Should have interactive challenge with Plasma stop at the absence of challenge', async () => {
        // first we fund Alice with something
        const withdrawCollateral = await plasma.WithdrawCollateral();

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

        let tx2 = createTransaction(TxTypeFund, 1, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 2
            }],
            [{
                amount: 100,
                to: alice
            }],
                operatorKey
        )
        let block = createBlock(1, 2, firstHash, [tx, tx2],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = Buffer.concat(block.merkleTree.getProof(0, true));
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

        // should be in principle able to withdraw an output before the procedure

        const succ = await plasma.startWithdraw.call(1, 0,ethUtil.bufferToHex(reencodedTX),
        ethUtil.bufferToHex(proof), {from: alice, value: withdrawCollateral});

        assert(succ[0]);


        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
        const tx3 = createTransaction(TxTypeMerge, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            },
            {
                blockNumber: 1,
                txNumberInBlock: 1,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 200,
                to: alice
            }],
                operatorKey
        )
        block = createBlock(2, 1, newHash, [tx3],  operatorKey)

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(0, true));

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
        // startShowMeTheInputChallenge(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
        //     uint8 _inputNumber,
        //     bytes _plasmaTransaction,
        //     bytes _merkleProof)
        
        submissionReceipt = await challenger.startShowMeTheInputChallenge(
            2, 0, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3), {from: bob, value: withdrawCollateral});

        let allLogs = submissionReceipt.logs;
        let from = allLogs[0].args._from;
        let inputIndex = allLogs[0].args._inputIndex;
        let outputIndex = allLogs[0].args._outputIndex;
        let {blockNumber, txNumber, outputNumber} = parseTransactionIndex(outputIndex.toString(10));
        assert(from == bob);
        assert(blockNumber.toNumber() === 1);
        assert(txNumber.toNumber() === 0);
        assert(outputNumber.toNumber() === 0);

        const delay = await plasma.ShowMeTheInputChallengeDelay();
        await increaseTime(delay.toNumber() + 1);

        submissionReceipt = await challenger.finalizeShowMeTheInputChallenge(inputIndex, {from: bob});
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);

    })

    it('UTXO was successfully withdrawn and than spent in Plasma', async () => {
        // deposit to prevent stopping

        await plasma.deposit({from: alice, value: "1000000000"})

        // first we fund Alice with something
        const withdrawCollateral = await plasma.WithdrawCollateral();

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

        let tx2 = createTransaction(TxTypeFund, 1, 
            [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 2
            }],
            [{
                amount: 100,
                to: alice
            }],
                operatorKey
        )
        let block = createBlock(1, 2, firstHash, [tx, tx2],  operatorKey)
        const reencodedTX = tx.serialize();
        const proof = Buffer.concat(block.merkleTree.getProof(0, true));
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

        // should be in principle able to withdraw an output before the procedure

        submissionReceipt = await plasma.startWithdraw(1, 0, ethUtil.bufferToHex(reencodedTX),
        ethUtil.bufferToHex(proof), {from: alice, value: withdrawCollateral});

        let withdrawIndex = submissionReceipt.logs[0].args._withdrawIndex;


        // than we spend an output, but now Bob signs instead of Alice

        const newHash = await plasma.hashOfLastSubmittedBlock();
        const tx3 = createTransaction(TxTypeMerge, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 100
            },
            {
                blockNumber: 1,
                txNumberInBlock: 1,
                outputNumberInTransaction: 0,
                amount: 100
            }],
            [{
                amount: 200,
                to: alice
            }],
                operatorKey
        )
        block = createBlock(2, 1, newHash, [tx3],  operatorKey)

        const reencodedTX3 = tx3.serialize();
        const proof3 = Buffer.concat(block.merkleTree.getProof(0, true));

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
        // startShowMeTheInputChallenge(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
        //     uint8 _inputNumber,
        //     bytes _plasmaTransaction,
        //     bytes _merkleProof)
        
        submissionReceipt = await challenger.startShowMeTheInputChallenge(
            2, 0, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3), {from: bob, value: withdrawCollateral});

        let allLogs = submissionReceipt.logs;
        let from = allLogs[0].args._from;
        let inputIndex = allLogs[0].args._inputIndex;
        let outputIndex = allLogs[0].args._outputIndex;
        let {blockNumber, txNumber, outputNumber} = parseTransactionIndex(outputIndex.toString(10));
        assert(from == bob);
        assert(blockNumber.toNumber() === 1);
        assert(txNumber.toNumber() === 0);
        assert(outputNumber.toNumber() === 0);

        const delay = await plasma.WithdrawDelay();
        await increaseTime(delay.toNumber() + 1);

        submissionReceipt = await plasma.finalizeWithdraw(withdrawIndex, {from: alice});
        let status = await plasma.withdrawRecords(withdrawIndex);
        assert(status[3].toNumber() === 3);
        // proveSpendAndWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
        //     uint32 _plasmaTxNumInBlock,
        //     uint8 _inputNumber,
        //     bytes _plasmaTransaction,
        //     bytes _merkleProof,
        //     uint256 _withdrawIndex //references withdraw

        submissionReceipt = await challenger.proveSpendAndWithdraw(2, 0, ethUtil.bufferToHex(reencodedTX3), ethUtil.bufferToHex(proof3), withdrawIndex, {from: bob});
        const plasmaIsStopped = await plasma.plasmaErrorFound();
        assert(plasmaIsStopped);

    })

})