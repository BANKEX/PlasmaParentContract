const TruffleContract = require('truffle-contract');
const Web3 = require("web3");

async function deployContracts(web3ProviderAddress, operatorAddress) {
    const web3 = new Web3(web3ProviderAddress);
    const PriorityQueueContract = new TruffleContract(require("../build/contracts/PriorityQueue.json"));
    const BlockStorageContract = new TruffleContract(require("../build/contracts/PlasmaBlockStorage.json"));
    const PlasmaParentContract = new TruffleContract(require("../build/contracts/PlasmaParent.json"));
    const PlasmaChallengerContract = new TruffleContract(require("../build/contracts/PlasmaChallenges.json"));
    const addresses = await web3.eth.getAccounts();
    const address = addresses[0];
    console.log("Plasma operator address is " + address);
    const Web3PriorityQueueContract = new web3.eth.Contract(PriorityQueueContract.abi, {from: address, gasPrice: 35e9});
    let gas = await Web3PriorityQueueContract.deploy({data: PriorityQueueContract.bytecode}).estimateGas();
    console.log("Queue gas price " + gas)
    const DeployedPriorityQueueContract = await Web3PriorityQueueContract.deploy({data: PriorityQueueContract.bytecode}).send({from:address, gas: gas});
    console.log("Deployed queue at "+ DeployedPriorityQueueContract._address);
    const Web3BlockStorageContract = new web3.eth.Contract(BlockStorageContract.abi, {from: address, gasPrice: 35e9});
    gas = await Web3BlockStorageContract.deploy({data: BlockStorageContract.bytecode}).estimateGas();
    console.log("Storage gas price " + gas)
    const DeployedBlockStorageContract = await Web3BlockStorageContract.deploy({data: BlockStorageContract.bytecode}).send({from:address, gas: gas});
    console.log("Deployed storage at "+ DeployedBlockStorageContract._address);
    const Web3PlasmaParentContract = new web3.eth.Contract(PlasmaParentContract.abi, {from: address, gasPrice: 35e9});
    console.log("Plasma parent bytecode size is " + (PlasmaParentContract.bytecode.length-2)/2);
    gas = await Web3PlasmaParentContract.deploy({data: PlasmaParentContract.bytecode, arguments: [DeployedPriorityQueueContract._address, DeployedBlockStorageContract._address]}).estimateGas();
    console.log("Parent gas price " + gas)
    const DeployedPlasmaParentContract = await Web3PlasmaParentContract.deploy({data: PlasmaParentContract.bytecode, arguments: [DeployedPriorityQueueContract._address, DeployedBlockStorageContract._address]}).send({from:address, gas: gas});
    console.log("Deployed parent at "+ DeployedPlasmaParentContract._address);
    const Web3PlasmaChallengerContract = new web3.eth.Contract(PlasmaChallengerContract.abi, {from: address, gasPrice: 35e9});
    gas = await Web3PlasmaChallengerContract.deploy({data: PlasmaChallengerContract.bytecode, arguments: [DeployedPriorityQueueContract._address, DeployedBlockStorageContract._address]}).estimateGas();
    console.log("Challenger gas price " + gas)
    const DeployedPlasmaChallengerContract = await Web3PlasmaChallengerContract.deploy({data: PlasmaChallengerContract.bytecode, arguments: [DeployedPriorityQueueContract._address, DeployedBlockStorageContract._address]}).send({from:address, gas: gas});
    console.log("Deployed challenger at "+ DeployedPlasmaChallengerContract._address);
    await DeployedPriorityQueueContract.methods.setOwner(DeployedPlasmaParentContract._address).send({from:address})
    await DeployedBlockStorageContract.methods.setOwner(DeployedPlasmaParentContract._address).send({from:address})
    await DeployedPlasmaParentContract.methods.setChallenger(DeployedPlasmaChallengerContract._address).send({from:address})
    await DeployedPlasmaParentContract.methods.setOperator("0x3075b2a7ca23f21a80a55d6db3968203e91cf615", true).send({from:address})
    const firstHash = await DeployedPlasmaParentContract.methods.hashOfLastSubmittedBlock().call();
    console.log("Hash of the header for block 0 is " + firstHash);
    return {web3: web3, plasmaParent: DeployedPlasmaParentContract}
}

module.exports = deployContracts;

// deployContracts("http://127.0.0.1:8545").then();