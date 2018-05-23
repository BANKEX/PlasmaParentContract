const increaseTime = async function(addSeconds) {
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_increaseTime", params: [addSeconds], id: 0})
    await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_mine", params: [], id: 1})
}

const increaseBlockCounter = async function(addBlocks) {
    for (let i = 0; i < addBlocks; i++) {
        await web3.currentProvider.send({jsonrpc: "2.0", method: "evm_mine", params: [], id: i})
    }
}

module.exports.increaseTime = {increaseTime, increaseBlockCounter};