const util = require("util");

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
    }
};