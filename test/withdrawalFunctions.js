
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const util = require("util");
const ethUtil = require('ethereumjs-util')
// const BN = ethUtil.BN;
var BN;
const t = require('truffle-test-utils')
t.init()
const expectThrow = require("../helpers/expectThrow");
const {addresses, keys} = require("./keys.js");
const createTransaction = require("./createTransaction");
const createBlock = require("./createBlock");
const testUtils = require('./utils');

const {
    TxTypeFund,
    TxTypeMerge,
    TxTypeSplit} = require("../lib/Tx/RLPtx.js");

// const Web3 = require("web3");

const increaseTime = async function(addSeconds) {
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0})
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_mine", params: [], id: 1})
};

contract('PlasmaParent', async (accounts) => {
    BN = web3.BigNumber;
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
        storage = await BlockStorage.new({from: operator});
        queue  = await PriorityQueue.new({from: operator});
        plasma = await PlasmaParent.new(queue.address, storage.address, {from: operator});
        await storage.setOwner(plasma.address, {from: operator});
        await queue.setOwner(plasma.address, {from: operator});
        challenger = await Challenger.new(queue.address, storage.address, {from: operator});
        await plasma.setChallenger(challenger.address, {from: operator});
        await plasma.setOperator(operatorAddress, true, {from: operator});
        firstHash = await plasma.hashOfLastSubmittedBlock();
    });

    it('should emit deposit event', async () => {
        const depositIndex = await plasma.deposit.call({from: alice, value: 314});
        const receipt = await plasma.deposit({from: alice, value: 314});
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositEvent', {_from: alice, _amount: 314, _depositIndex: depositIndex.toNumber()});
    });

    it('should allow deposit withdraw process', async () => {
        const depositIndex = await plasma.deposit.call({from: alice, value: 314});
        await plasma.deposit({from: alice, value: 314});

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        const receipt = await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawStartedEvent', {_depositIndex: depositIndex.toNumber()});
    });

    it('should require bond for deposit withdraw start', async () => {
        const depositIndex = await plasma.deposit.call({from: alice, value: 314});
        await plasma.deposit({from: alice, value: 314});

        const receipt = await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: 0});
        const promise = testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawStartedEvent', {_depositIndex: depositIndex.toNumber()});
        // Will also fail if contract's bond constant is set to 0
        await expectThrow(promise);
    });

    it('should not allow early deposit withdraw', async () => {
        const depositIndex = await plasma.deposit.call({from: alice, value: 314});
        await plasma.deposit({from: alice, value: 314});

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});

        let promise = plasma.finalizeDepositWithdraw(depositIndex.toString(), {from: alice});
        await expectThrow(promise);
    });

    it('should allow successful deposit withdraw', async () => {
        const depositAmount = new BN(314);
        const depositIndex = await plasma.deposit.call({from: alice, value: depositAmount.toString()});
        await plasma.deposit({from: alice, value: depositAmount.toString()});

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});

        const delay = await plasma.DepositWithdrawDelay();
        await increaseTime(delay.toNumber() + 1);
        const balanceBeforeWithdraw = web3.eth.getBalance(alice);
        let receipt = await plasma.finalizeDepositWithdraw(depositIndex.toString(), {from: alice});
        testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawCompletedEvent', {_depositIndex: depositIndex.toNumber()});

        const balanceAfterWithdraw = web3.eth.getBalance(alice);
        const gasPrice = web3.eth.gasPrice;
        const expectedBalance =
            balanceBeforeWithdraw
            .add(depositAmount)
            .add(depositWithdrawCollateral)
            .add(gasPrice.mul(new BN(receipt.receipt.gasUsed)));
        console.log(balanceBeforeWithdraw.toString());
        console.log(balanceAfterWithdraw.toString());
        console.log(expectedBalance.toString());
        assert.equal(balanceAfterWithdraw.toString(), expectedBalance.toString(), 'Balance not equal');
    });

    // uint256 public constant DepositWithdrawDelay = (72 hours);
    // uint256 public constant ShowMeTheInputChallengeDelay = (72 hours);
    // uint256 public constant WithdrawDelay = (168 hours);
    // uint256 public constant ExitDelay = (336 hours);

});
