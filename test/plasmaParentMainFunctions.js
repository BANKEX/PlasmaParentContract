
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

// const Web3 = require('web3');
// const web3 = new Web3();

// web3.setProvider('http://127.0.0.1:7545')

// // ganeche features
// web3.extend({
//     property: 'evm',
//     methods: [{
//         name: 'increaseTime',
//         call: 'evm_increaseTime',
//         params: 1,
//         inputFormatter: [null]
//     },{
//         name: 'mine',
//         call: 'evm_mine'
//     }]
// })

contract('PlasmaParent', async (accounts) => {


    const operatorAddress = "0x3075b2a7ca23f21a80a55d6db3968203e91cf615"
    const blockOne = "0x0000 0001 0000 0001 0867 e6b0 df6a 2291 \
    abb4 6521 e681 3f31 766b 7ae3 0909 8ed0 \
    7bb0 0600 9ac7 613c df8a 6ee7 0de2 e839 \
    87ac 7aab a2a9 2e01 61a7 9970 6944 e123 \
    da2b abb8 c9dc 659d 1cf2 fb4f 87b7 16f6 \
    7554 fe23 c1ea 9956 b427 9409 40b7 751d \
    50f7 d755 74c5 9bdd dd38 8202 d051 0e70 \
    f5a5 a652 2ac0 3bf1 bd7e 36bf 007b 577b \
    6ac0 b8a8 f10f fb5d 12f8 c3b8 c1f8 bf84 \
    0000 0000 b8b8 f8b6 b871 f86f 04af eead \
    ec84 0000 0000 8400 0000 0000 a000 0000 \
    0000 0000 0000 0000 0000 0000 0000 0000 \
    0000 0000 0000 0000 0000 0027 13b8 3cf8 \
    3ab8 38f7 0094 6394 b37c f80a 7358 b380 \
    68f0 ca47 60ad 4998 3a1b a000 0000 0000 \
    0000 0000 0000 0000 0000 0000 0000 0000 \
    0000 0000 2386 f26f c100 001b a02d 3e3a \
    1751 35cd 7929 8add 1697 613c 29dd 25ad \
    6f29 8c5c 28f4 4f97 80aa 92c9 7da0 62e8 \
    f5ac 0ee3 4cbd 943b 9dc9 0fed d453 96db \
    9220 7491 42c2 dd37 2cc5 1790 db6a ".replace(/\s/g, "").replace("\n", "").substr(0, 276);

    let queue
    let plasma;
    let storage;
    let challenger;

    const operator = accounts[0]

    const alice    = accounts[2]
    const bob      = accounts[3]

    const some     = 9000;

    beforeEach(async () => {
        storage = await BlockStorage.new({from: operator})
        queue  = await PriorityQueue.new({from: operator})
        plasma = await PlasmaParent.new(queue.address, storage.address, {from: operator})
        await storage.setOwner(plasma.address, {from: operator})
        await queue.setOwner(plasma.address, {from: operator})
        challenger = await Challenger.new(queue.address, storage.address, {from: operator})
        await plasma.setChallenger(challenger.address, {from: operator})
        await plasma.setOperator(operatorAddress, true, {from: operator});
    })

    it('submit block', async () => {
        let lastBlockNumber = await storage.lastBlockNumber()
        let lastBlockHash = await storage.hashOfLastSubmittedBlock()
        lastBlockHash = await plasma.hashOfLastSubmittedBlock()
        assert(lastBlockNumber.toString() == "0");
        const submissionReceipt = await plasma.submitBlockHeaders(blockOne);
        lastBlockNumber = await storage.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        // web3.evm.mine()
        let allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        let get = util.promisify(allEvents.get.bind(allEvents))
        let evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 1,
                 _merkleRoot: "0xdf8a6ee70de2e83987ac7aaba2a92e0161a799706944e123da2babb8c9dc659d"}
        }, 'The event is emitted');
    })

    it('submit same block twice', async () => {
        await plasma.submitBlockHeaders(blockOne);
        expectThrow(plasma.submitBlockHeaders(blockOne))
    })

    it('submit many block', async () => {
        let lastBlockNumber = await storage.lastBlockNumber()
        assert(lastBlockNumber.toString() == "0");
        const submissionReceipt = await plasma.submitBlockHeaders(blockOne);
        lastBlockNumber = await storage.lastBlockNumber();
        assert(lastBlockNumber.toString() == "1");
        // web3.evm.mine()
        let allEvents = storage.allEvents({fromBlock: submissionReceipt.receipt.blockNumber, toBlock: submissionReceipt.receipt.blockNumber});
        let get = util.promisify(allEvents.get.bind(allEvents))
        let evs = await get()
        assert.web3Event({logs: evs}, {
            event: 'BlockHeaderSubmitted',
            args: {_blockNumber: 1,
                 _merkleRoot: "0xdf8a6ee70de2e83987ac7aaba2a92e0161a799706944e123da2babb8c9dc659d"}
        }, 'The event is emitted');
    })

    // it('recieve deposits', async () => {

    //     const deposit_index = await plasma.deposit.call({from:alice,value:some})

    //     web3.evm.mine()

    //     const deposit_withdraw = await plasma.startDepositWithdraw(deposit_index, {from: alice})

    //     // // pp.DepositWithdrawStartedEvent({_depositIndex: deposit_index}, {fromBlock: 0, toBlock: 'latest'});

    //     // assert.web3Event(deposit_withdraw, {
    //     //     event: 'DepositWithdrawStartedEvent',
    //     //     args: {_depositIndex: deposit_index}
    //     // }, 'The event is emitted');

    //     // assert
    // })

})
