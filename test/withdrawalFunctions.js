
const SafeMath       = artifacts.require('SafeMath');
const PlasmaParent   = artifacts.require('PlasmaParent');
const PriorityQueue  = artifacts.require('PriorityQueue');
const BlockStorage = artifacts.require("PlasmaBlockStorage");
const Challenger = artifacts.require("PlasmaChallenges");
const PlasmaBuyouts = artifacts.require("PlasmaBuyouts");
const util = require("util");
const ethUtil = require('ethereumjs-util');
// const BN = ethUtil.BN;
var BN;
const t = require('truffle-test-utils');
t.init();
const expectThrow = require("../helpers/expectThrow");
const {addresses, keys} = require("./keys.js");
const {createTransaction} = require("./createTransaction");
const {createBlock, createMerkleTree} = require("./createBlock");
const testUtils = require('./utils');

const {
    TxTypeFund,
    TxTypeMerge,
    TxTypeSplit} = require("../lib/Tx/RLPtx.js");

// const Web3 = require("web3");

const increaseTime = async function(addSeconds) {
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0});
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

    it('should emit deposit event', async () => {
        const depositAmount = 42;
        const depositedBefore = await plasma.totalAmountDeposited();
        let receipt = await plasma.deposit({from: alice, value: depositAmount});
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);
        const depositIndex = new web3.BigNumber(0);
        const depositedAfter = await plasma.totalAmountDeposited();
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositEvent', {_from: alice, _amount: depositAmount, _depositIndex: depositIndex.toNumber()});
        assert.equal(depositedAfter.toNumber(), depositedBefore.toNumber() + depositAmount, 'Deposit counter should increase');
    });

    it('should allow deposit withdraw process', async () => {
        let receipt = await plasma.deposit({from: alice, value: 314});
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);
        const depositIndex = new web3.BigNumber(0);
        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        receipt = await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawStartedEvent', {_depositIndex: depositIndex.toNumber()});
    });

    it('should require bond for deposit withdraw start', async () => {
        const receipt = await plasma.deposit({from: alice, value: 314});
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);
        const depositIndex = new web3.BigNumber(0);
        const promise = plasma.startDepositWithdraw(depositIndex, {from: alice, value: 0});
        // Will also fail if contract's bond constant is set to 0
        await expectThrow(promise);
    });

    it('should not allow early deposit withdraw', async () => {
        let receipt = await plasma.deposit({from: alice, value: 314});
        const depositIndex = new web3.BigNumber(0);
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});

        const promise = plasma.finalizeDepositWithdraw(depositIndex.toString(), {from: alice});
        await expectThrow(promise);
    });

    it('should allow successful deposit withdraw', async () => {
        const depositAmount = new BN(314);
        let receipt = await plasma.deposit({from: alice, value: depositAmount.toString()});
        const depositIndex = new web3.BigNumber(0);
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        await plasma.startDepositWithdraw(depositIndex.toString(), {from: alice, value: depositWithdrawCollateral.toString()});

        const delay = await plasma.DepositWithdrawDelay();
        await increaseTime(delay.toNumber() + 1);
        const balanceBefore = await web3.eth.getBalance(alice);
        const depositedBefore = await plasma.totalAmountDeposited();
        receipt = await plasma.finalizeDepositWithdraw(depositIndex.toString(), {from: alice, gasPrice: web3.eth.gasPrice});
        const depositedAfter = await plasma.totalAmountDeposited();
        const balanceAfter = await web3.eth.getBalance(alice);
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawCompletedEvent', {_depositIndex: depositIndex.toNumber()});

        const expectedBalance = balanceBefore
            .add(depositAmount)
            .add(depositWithdrawCollateral)
            .sub(web3.eth.gasPrice.mul(receipt.receipt.gasUsed));
        assert.equal(balanceAfter.toString(), expectedBalance.toString(), 'Balance not equal');
        assert.equal(depositedAfter.toString(), (depositedBefore - depositAmount).toString(), 'Deposit counter should decrease');
    });

    it('should respond to deposit withdraw challenge', async () => {
        const depositAmount = new BN(42);
        let receipt = await plasma.deposit({from: alice, value: depositAmount.toString()});
        const depositIndex = new web3.BigNumber(0);
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);

        const tx = createTransaction(TxTypeFund, 0, [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: depositIndex.toString(10)
            }], [{
                amount: depositAmount.toString(10),
                to: alice
            }],
            operatorKey
        );
        const block = createBlock(1, 1, firstHash, [tx],  operatorKey);
        await testUtils.submitBlock(plasma, block);
        const proof = block.merkleTree.getProof(0, true);

        const depositWithdrawCollateral = await plasma.DepositWithdrawCollateral();
        await plasma.startDepositWithdraw(depositIndex, {from: alice, value: depositWithdrawCollateral});

        const balanceBefore = await web3.eth.getBalance(bob);
        receipt = await plasma.challengeDepositWithdraw(depositIndex.toString(), 1, ethUtil.bufferToHex(tx.rlpEncode()), ethUtil.bufferToHex(proof), {from: bob, gasPrice: web3.eth.gasPrice});
        const balanceAfter = await web3.eth.getBalance(bob);
        await testUtils.expectEvents(plasma, receipt.receipt.blockNumber, 'DepositWithdrawChallengedEvent', {_depositIndex: depositIndex.toNumber()});

        const expectedBalance = balanceBefore
            .add(depositWithdrawCollateral)
            .sub(web3.eth.gasPrice.mul(receipt.receipt.gasUsed));
        assert.equal(balanceAfter.toString(), expectedBalance.toString(), 'Balance not equal');
    });

    it('should stop Plasma on funding without deposit', async () => {
        const depositAmount = new BN(42);
        const tx = createTransaction(TxTypeFund, 0, [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: 1
            }], [{
                amount: depositAmount.toString(),
                to: alice
            }],
            operatorKey
        );
        const block = createBlock(1, 1, firstHash, [tx],  operatorKey);
        await testUtils.submitBlock(plasma, block);
        const proof = block.merkleTree.getProof(0, true);

        const balanceBefore = await web3.eth.getBalance(bob);
        const receipt = await challenger.proveInvalidDeposit(1, ethUtil.bufferToHex(tx.rlpEncode()),
            ethUtil.bufferToHex(proof), {from: bob, gasPrice: web3.eth.gasPrice});
        const balanceAfter = await web3.eth.getBalance(bob);

        assert.equal(true, await plasma.plasmaErrorFound());

        const bond = await plasma.operatorsBond();
        const expectedBalance = balanceBefore
            .add(bond / 2)
            .sub(web3.eth.gasPrice.mul(receipt.receipt.gasUsed));
        assert.equal(balanceAfter.toString(), expectedBalance.toString(), 'Balance not equal');
    });

    it('should stop Plasma on double funding', async () => {
        const depositAmount = new BN(42);
        let receipt = await plasma.deposit({from: alice, value: depositAmount.toString()});
        const depositIndex = new web3.BigNumber(0);
        // const depositIndex = testUtils.depositIndex(receipt.receipt.blockNumber);

        const tx1 = createTransaction(TxTypeFund, 0, [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: depositIndex.toString()
            }], [{
                amount: depositAmount.toString(),
                to: alice
            }],
            operatorKey
        );
        const tx2 = createTransaction(TxTypeFund, 1, [{
                blockNumber: 0,
                txNumberInBlock: 0,
                outputNumberInTransaction: 0,
                amount: depositIndex.toString()
            }], [{
                amount: depositAmount.toString(),
                to: alice
            }],
            operatorKey
        );
        const block = createBlock(1, 1, firstHash, [tx1, tx2],  operatorKey);
        await testUtils.submitBlock(plasma, block);
        const proof1 = block.merkleTree.getProof(0, true);
        const proof2 = block.merkleTree.getProof(1, true);

        const balanceBefore = await web3.eth.getBalance(bob);
        receipt = await challenger.proveDoubleFunding(
            1, ethUtil.bufferToHex(tx1.rlpEncode()), ethUtil.bufferToHex(Buffer.concat(proof1)),
            1, ethUtil.bufferToHex(tx2.rlpEncode()), ethUtil.bufferToHex(Buffer.concat(proof2)),
            {from: bob, gasPrice: web3.eth.gasPrice});
        const balanceAfter = await web3.eth.getBalance(bob);

        assert.equal(true, await plasma.plasmaErrorFound());

        const bond = await plasma.operatorsBond();
        const expectedBalance = balanceBefore
            .add(bond / 2)
            .sub(web3.eth.gasPrice.mul(receipt.receipt.gasUsed));
        assert.equal(balanceAfter.toString(), expectedBalance.toString(), 'Balance not equal');
    });

    it('should withdraw from the huge block', async () => {
        const withdrawCollateral = await plasma.WithdrawCollateral();
        await plasma.deposit({from: alice, value: "100000000000000"});

        const numToCreate = 1000;
        const allTXes = [];
        for (let i = 0; i < numToCreate; i++) {
            const tx = createTransaction(TxTypeFund, i, 
                [{
                    blockNumber: 0,
                    txNumberInBlock: 0,
                    outputNumberInTransaction: 0,
                    amount: 0
                }],
                [{
                    amount: 100+i,
                    to: alice
                }],
                    operatorKey
            )
            allTXes.push(tx);
        }
        const block = createBlock(1, allTXes.length, firstHash, allTXes,  operatorKey)
        await testUtils.submitBlock(plasma, block);
        const blockOneArray = block.serialize();
        const blockOne = Buffer.concat(blockOneArray);
        const MerkleTools = require("../lib/merkle-tools");
        const tools = new MerkleTools({hashType: "sha3"});
        const merkleRoot = block.header.merkleRootHash;
        for (let i = 0; i < 10; i++) {
            try {
                const randomTXnum = Math.floor(Math.random() * numToCreate);
                const rawTX = block.transactions[randomTXnum].signedTransaction.serialize();
                const proofObject = block.getProofForTransaction(rawTX);
                // console.log((new ethUtil.BN(proofObject.tx.txNumberInBlock)).toString(10));
                // console.log(JSON.stringify(block.transactions[randomTXnum].toFullJSON(true)));
                const submissionReceipt = await plasma.startWithdraw(
                    1, 0, ethUtil.bufferToHex(proofObject.tx.serialize()), ethUtil.bufferToHex(proofObject.proof),
                    {from: alice, value: withdrawCollateral}
                )
                const withdrawIndex = submissionReceipt.logs[0].args._withdrawIndex;
                const withdrawRecord = await plasma.withdrawRecords(withdrawIndex);
                assert(withdrawRecord[7] === alice);
                assert(withdrawRecord[3].toString(10) === "1");
                const included = tools.validateBinaryProof(proofObject.proof, proofObject.tx.hash(), merkleRoot);
                assert(included);
            } catch(e) {
                console.log(e);
                throw e;
            }
        }
    })

    it('should withdraw from the huge block and challenge after', async () => {
        const withdrawCollateral = await plasma.WithdrawCollateral();
        await plasma.deposit({from: alice, value: "10000000000000"});

        const numToCreate = 1000;
        const allTXes = [];
        for (let i = 0; i < numToCreate; i++) {
            const tx = createTransaction(TxTypeFund, i, 
                [{
                    blockNumber: 0,
                    txNumberInBlock: 0,
                    outputNumberInTransaction: 0,
                    amount: 0
                }],
                [{
                    amount: 100+i,
                    to: alice
                }],
                    operatorKey
            )
            allTXes.push(tx);
        }
        const block = createBlock(1, allTXes.length, firstHash, allTXes,  operatorKey)
        await testUtils.submitBlock(plasma, block);
        let nextHash = await plasma.hashOfLastSubmittedBlock();
        const randomTXtoSpendIndex = Math.floor(Math.random() * numToCreate);
        const txToSpend = allTXes[randomTXtoSpendIndex];
        const spendingTX = createTransaction(TxTypeSplit, 0, 
            [{
                blockNumber: 1,
                txNumberInBlock: txToSpend.txNumberInBlock,
                outputNumberInTransaction: 0,
                amount: txToSpend.amountBuffer
            }],
            [{
                amount: txToSpend.amountBuffer,
                to: alice
            }],
                aliceKey
        )
        const block2 = createBlock(2, 1, nextHash, [spendingTX],  operatorKey)
        await testUtils.submitBlock(plasma, block2);

        const MerkleTools = require("../lib/merkle-tools");
        const tools = new MerkleTools({hashType: "sha3"});
        let merkleRoot = block.header.merkleRootHash;
        const rawTX = block.transactions[randomTXtoSpendIndex].signedTransaction.serialize();
        let proofObject = block.getProofForTransaction(rawTX);
        let included = tools.validateBinaryProof(proofObject.proof, proofObject.tx.hash(), merkleRoot);
        assert(included);
        let submissionReceipt = await plasma.startWithdraw(
            1, 0, ethUtil.bufferToHex(proofObject.tx.serialize()), ethUtil.bufferToHex(proofObject.proof),
            {from: alice, value: withdrawCollateral}
        )
        const withdrawIndex = submissionReceipt.logs[0].args._withdrawIndex;
        let withdrawRecord = await plasma.withdrawRecords(withdrawIndex);
        assert(withdrawRecord[7] === alice);
        assert(withdrawRecord[3].toString(10) === "1");


        proofObject = block2.getProofForTransactionSpendingUTXO(spendingTX.signedTransaction.serialize(), spendingTX.signedTransaction.transaction.inputs[0].getUTXOnumber());
        merkleRoot = block2.header.merkleRootHash;
        included = tools.validateBinaryProof(proofObject.proof, proofObject.tx.hash(), merkleRoot);
        assert(included);
        submissionReceipt = await plasma.challengeWithdraw(
            2, proofObject.inputNumber.toNumber(), 
            ethUtil.bufferToHex(proofObject.tx.serialize()), ethUtil.bufferToHex(proofObject.proof),
            withdrawIndex
        )
        withdrawRecord = await plasma.withdrawRecords(withdrawIndex);
        assert(withdrawRecord[7] === alice);
        assert(withdrawRecord[3].toString(10) === "4");
    })

});
