const util = require("util");
const Block = require("../lib/Block/RLPblock");
const ethUtil = require('ethereumjs-util');

module.exports = {
    /**
     * Asserts that even is emitted
     *
     * @param contract A contract instance to check
     * @param {int} blockNumber Block number to look at
     * @param {(string|Array)} event Event name or an array of events
     * @param {Object} args Optional event args
     * @returns {Promise<void>}
     */
    async expectEvents(contract, blockNumber, event, args = {}) {
      let allEvents = contract.allEvents({fromBlock: blockNumber, toBlock: blockNumber});
      let get = util.promisify(allEvents.get.bind(allEvents));
      let evs = await get();
      assert.web3Events({logs: evs}, Array.isArray(event) ? event : [{event, args}], 'The event is emitted');
    },

    /**
     * Submit a block header to the Plasma contract
     *
     * @param plasma The Plasma contract
     * @param {Block} block A block to submit
     * @returns {Promise<void>}
     */
    async submitBlock(plasma, block) {
        const blockHeader = Buffer.concat(block.serialize()).slice(0,137);
        await plasma.submitBlockHeaders(ethUtil.bufferToHex(blockHeader));
    },

    depositIndex(blockNumber) {
        return (new web3.BigNumber(blockNumber)).mul(new web3.BigNumber(2).pow(32));
    },


    async checkPlasmaStopped() {

    }
};