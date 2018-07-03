const fs = require('fs');
const BlockStorage = artifacts.require("PlasmaBlockStorage.sol");
const PriorityQueue = artifacts.require("PriorityQueue.sol");
const PlasmaParent  = artifacts.require("PlasmaParent.sol");
const PlasmaChallenges  = artifacts.require("PlasmaChallenges.sol");
const PlasmaBuyouts = artifacts.require("PlasmaExitGame");
const assert = require('assert');
const _ = require('lodash');

module.exports = function(deployer, network, accounts) {
    const operator = accounts[0];
    (async () => {
        await deployer.deploy(BlockStorage, {from: operator});
        let storage = await BlockStorage.deployed();

        await deployer.deploy(PriorityQueue, {from: operator});
        let queue = await PriorityQueue.deployed();

        console.log("Plasma parent bytecode length is " + PlasmaParent.bytecode.length / 2);
        console.log("Plasma challenges bytecode length is " + PlasmaChallenges.bytecode.length / 2);
        console.log("Exit game bytecode length is " + PlasmaBuyouts.bytecode.length / 2);
        await deployer.deploy(PlasmaParent, queue.address, storage.address,  {from: operator});
        let parent = await PlasmaParent.deployed();

        await storage.setOwner(parent.address,{from: operator});
        await queue.setOwner(parent.address, {from: operator});

        await deployer.deploy(PlasmaBuyouts, queue.address, storage.address, {from: operator});
        let buyouts = await PlasmaBuyouts.deployed();
        await deployer.deploy(PlasmaChallenges, queue.address, storage.address, {from: operator});
        let challenger = await PlasmaChallenges.deployed();

        await parent.setDelegates(challenger.address, buyouts.address, {from: operator})
        await parent.setOperator("0x3075b2a7ca23f21a80a55d6db3968203e91cf615", 2, {from: operator});

        const canSignBlocks = await storage.canSignBlocks("0x3075b2a7ca23f21a80a55d6db3968203e91cf615");
        assert(canSignBlocks);

        const buyoutsAddress = await parent.buyoutsContract();
        assert(buyoutsAddress === buyouts.address);

        const challengesAddress = await parent.challengesContract();
        assert(challengesAddress === challenger.address);

        let parentAbi = parent.abi;
        let buyoutsAbi = buyouts.abi;
        let challengerAbi = challenger.abi;

        const mergedABI = _.uniqBy([...parentAbi, ...challengerAbi, ...buyoutsAbi], a => a.name || a.type);
        // due to async contract address is not saved in not saved in json by truffle
        // so we need to generate details file from within migration
	    let details = {error: false, address: parent.address, abi: mergedABI};
	    fs.writeFileSync("build/details", JSON.stringify(details));
	    console.log('Complete. Contract address: ' + parent.address);
    })();
};
