# Plasma Parent Contract

## For the understanding of the original idea and possible constructions please refer to
- Original Plasma paper [here](https://plasma.io/)
- Discussion for Minimal Viable Plasma - [MVP](https://ethresear.ch/t/minimal-viable-plasma/426)
- Novel construction of More Viable Plasma - [MoreVP](https://ethresear.ch/t/more-viable-plasma/2160)
# This contract is active WIP for More Viable Plasma implementation

## Test coverage
Recently project got significant update, please use an [up-to-date test](https://github.com/BANKEX/PlasmaParentContract/blob/master/test/transactionSubmissionFunctions.js)

## Optimization

In progress. We work hard on lower gas prices and more transactions per second.


## Quickstart
    git clone https://github.com/BANKEX/PlasmaParentContract.git
    npm i


- To run unit tests, first launch pre-configured local testing network:
- `./helpes/start.sh`

then, run unit tests, on Linux or Mac:

    truffle test test\transactionSubmissionFunctions.js

or windows:

    truffle.cmd test test\transactionSubmissionFunctions.js
# General transaction overview, still subject to change
## Transaction structure

### Input
An RLP encoded set with the following items:
- Block number, 4 bytes
- Transaction number in the block, 4 bytes
- Output number in the transaction, 1 byte
- "Amount" field, 32 bytes, that is more a data field, usually used for an amount of the output referenced by the previous field, but has special meaning for "Deposit" transactions

### Output
An RLP encoded set with the following items:
- Output number in the transaction, 1 byte
- Receiver's Ethereum address, 20 bytes
- "Amount" field, 32 bytes

### Transaction
An RLP encoded set with the following items:
- Transaction type, 1 byte
- An array (list) of Inputs, maximum of 2 items
- An array (list) of Outputs, maximum 3 items. One of the outputs is an explicit output to an address of Plasma operator.

### Signed transaction
An RLP encoded set with the following items:
- The transaction, as described above
- Recoverable EC of the transaction sender:
  1. V value, 1 byte, expected values 27, 28
  2. R value, 32 bytes
  3. S value, 32 bytes

From this signature, Plasma operator deduces the sender, checks that the sender is an owner of UTXOs referenced by inputs. Signature is based on EthereumPersonalHash(RLPEncode(Transaction)). The transaction should be well-formed, the sum of inputs equal to the sum of the outputs, etc

### Numbered signed transaction
> This will change and become deprecated. The transaction number will be determined exclusively from the Merkle tree position 
An RLP encoded set with the following items:
- Transaction number in the block, 4 bytes, inserted by Plasma operator when the block is assembled
- The signed transaction, as described above

### Block header
- Block number, 4 bytes, used in the main chain to double check proper ordering
- Number of transactions in the block, 4 bytes, purely informational
- Parent hash, 32 bytes, the hash of the previous block, hashes the full header
- Merkle root of the transactions tree, 32 bytes
- V value, 1 byte, expected values 27, 28
- R value, 32 bytes
- S value, 32 bytes Signature is based on EthereumPersonalHash(block number || number of transactions || previous hash || Merkle root), where || means concatenation. Values V, R, S are then concatenated to the header.

### Block
- Block header, as described above, 137 bytes
- RLP encoded array (list) of Numbered signed transactions, as described above. Will later change to the list of just Signed transactions!

While some fields can be excessive, such block header can be submitted by anyone to the main Ethereum chain when a block is available, but for some reason not sent to the smart contract. Transaction numbering is done by the operator, it should be monotonically increasing without spaces, and the number of transactions in the header should (although this is not necessary for the functionality) match the number of transactions in the Merkle tree and the full block.

## This contract differs from Minimal Viable Plasma in the following:

- More Viable Plasma transaction priority and canonicity rules, so no confirmation signatures now
- Other transactions structure with nested RLP fields
- Deposit transactions are declarative: new block with 1 transaction is not created automatically (although can be easily changed), but deposit record is created and can be withdrawn back to the user if Plasma operator doesn't provide transaction of appropriate structure (referencing this deposit, having proper owner and amount).
- Anyone(!) can send a header of the block to the main chain, so if the block is assembled and available, but not yet pushed to the main chain, anyone can send a header on behalf of Plasma operator.
- Another important clarification: if user spots an invalid transaction (double spends, etc) a contract is switched to "Exit mode" (broken right now), disabling new block submission functionality.
- Challenges for exits invalidation should only be accepted from the blocks before the first invalid one.
## Implemented functionality:
## Ignore for now

All basic challenges and potential "cheats" for operator or user should be now covered

## List of intended challenges and tests
- [x] Block header uploads
    - [x] should accept one properly signed header
    - [x] should NOT accept same header twice
    - [x] should accept two headers in right sequence
    - [x] should accept two headers in right sequence in the same transaction
    - [x] should NOT accept two headers in wrong sequence
    - [x] should NOT accept invalidly signed block header
    - [x] should NOT accept invalidly signed block header in sequence in one transaction
    - [x] should property update two weeks old block number
    - [x] should check block hashes match in addition to block numbers in sequence
- [ ] Deposits
    - [x] should emit deposit event
    - [x] should allow deposit withdraw process
    - [x] should respond to deposit withdraw challenge
    - [x] should allow successful deposit withdraw
    - [x] should require bond for deposit withdraw start
    - [x] should stop Plasma on duplicate funding transaction
    - [x] should stop Plasma on funding without deposit
    - [x] should update total deposited amount for all tests above
    - [ ] should update amount pending exit for all tests above
- [ ] Withdrawals (normal process)
    - [ ] should start withdraw with proper proof
    - [x] should not allow non-owner of transaction to start a withdraw of UTXO
    - [ ] should respond to withdraw challenge
    - [ ] should allow successful withdraw
    - [ ] should require bond for withdraw start 
    - [ ] should return bond on successful withdraw
    - [ ] should return bond and prevent withdraw if Plasma was stopped in the meantime
    - [ ] should update amount pending withdraw for all tests above
    - [ ] should update total amount deposited for all tests above
    - [x] should allow offer for buyout
    - [x] should allow accepting a buyout offer
    - [x] should allow returning funds for expired offer 
- [ ] Exits (when Plasma is stopped)
    - [ ] should put withdraw in the quequ
    - [ ] should maintain priority in the queue
    - [ ] should give the same priority for blocks that are older than 2 weeks
    - [ ] should respond to exit prevention challenge
    - [ ] should allow successful exit
    - [ ] should update amount pending withdraw for all tests above
    - [ ] should update total amount deposited for all tests above
- [ ] Challenges
    - [x] Invalid transaction in block (unrealisable)
    - [x] should NOT stop on valid transaction (not malformed) in block
    - [x] Transaction in block references the future
    - [x] Transaction references an output with tx number larger, than number in transaction in this UTXO block
    - [x] Transaction has higher number that number of transactions in block
    - [x] Two transactions have the same number in block
    - [x] Transaction is malformed (balance breaking)
    - [x] Transaction is malformed (invalid merge by Plasma owner)
    - [x] Double spend
    - [x] Spend without owner signature
    - [x] UTXO amount is not equal to input amount
    - [x] UTXO was successfully withdrawn and than spent in Plasma
    - [x] Should have interactive challenge (show me the referenced input)
    - [x] Should have interactive challenge with Plasma stop at the absence of challenge

## Contribution

Everyone is welcome to spot mistakes in the logic of this contract as a number of provided functions is substantial. If you find a potential error or security loophole (one that would allow Plasma operator or user to break the normal operation and not being caught) - please open an issue.

## Authors

Alex Vlasov, [@shamatar](https://github.com/shamatar), [av@bankexfoundation.org](mailto:av@bankexfoundation.org)

## Further work

Check out our zkSNARK based Plasma [here](https://github.com/BANKEX/snarky_plasma) and corresponding gadget lib [here](https://github.com/BANKEX/gadget_lib).

## License

All source code and information in this repository is available under the Apache License 2.0 license. See the [LICENSE](https://github.com/BANKEX/PlasmaParentContract/blob/master/LICENSE) file for more info.
