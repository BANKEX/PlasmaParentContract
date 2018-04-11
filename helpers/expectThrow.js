module.exports = async function expectThrow(promise) {
    try {
        await promise;
    } catch (error) {
        // TODO: Check jump destination to destinguish between a throw
        //       and an actual invalid jump.
        const invalidJump = error.message.search('invalid JUMP') >= 0;
        // TODO: When we contract A calls contract B, and B throws, instead
        //       of an 'invalid jump', we get an 'out of gas' error. How do
        //       we distinguish this from an actual out of gas event? (The
        //       testrpc log actually show an 'invalid jump' event.)
        const outOfGas = error.message.search('out of gas') >= 0;
            // General revert
        const revert = error.message.search("VM Exception while processing transaction: revert") >= 0;
      assert(
        invalidJump || outOfGas || revert,
        "Expected throw, got '" + error + "' instead",
      );
        return;
    }
    assert.fail('Expected throw not received');
  };