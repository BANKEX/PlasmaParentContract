# Plasma Parent Contract

# This contract is active WIP, tests will be pushed in the next few days

# TODO

- Add a method to withdraw to address other than "msg.sender" (low priority).
- Add a zkSNARK to be able to prove knowledge of the private key for an Ethereum address (for fun).
- Evaluate a use of external WithdrawRecord/DepositRecord holder the same way as BlockStorage works, so the main contract can migrate (although it implies partial loss of trust or should be done by a commitee of "trusted" parties). Most likely a V2 ABI encoding support is necessary.

## Transaction structure

### Input
An RLP encoded set with the following items:
- Block number, 4 bytes
- Transaction number in block, 4 bytes
- Output number in transaction, 1 byte
- "Amount" field, 32 bytes, that is more a data field, usually used for an amount of the output referenced by previous field, but has special meaning for "Deposit" transacitons

### Output
An RLP encoded set with the following items:
- Output number in transaction, 1 byte
- Receiver's Ethereum address, 20 bytes
- "Amount" field, 32 bytes

### Transaction 
An RLP encoded set with the following items:
- Transaction type, 1 byte
- An array (list) of Inputs, maximum 2 items
- An array (list) of Outputs, maximum 3 items. One of the outputs is an explicit output to an address of Plasma operator.

### Signed transaction 
An RLP encoded set with the following items:
- Transaction, as described above
- Recoverable EC of the transaction sender:
   1) V value, 1 byte, expected values 27, 28
   2) R value, 32 bytes
   3) S value, 32 bytes

From this signature Plasma operator deduces a sender, checks that the sender is an owner of UTXOs referenced by inputs. Signature is based on EthereumPersonalHash(RLPEncode(Transaction)). Transaction should be well-formed, sum of inputs equal to sum of the outputs, etc 

### Numbered signed transaction 
An RLP encoded set with the following items:
- Transaction number in block, 4 bytes, inserted by Plasma operator when block is assembled
- Signed transaction, as described above

### Block header
- Block number, 4 bytes, used in the main chain to double check proper ordering
- Number of transactions in block, 4 bytes, purely informational
- Parent hash, 32 bytes, hash of the previus block, hashes the full header
- Merkle root of the transactions tree, 32 bytes
- V value, 1 byte, expected values 27, 28
- R value, 32 bytes
- S value, 32 bytes
Signature is based on EthereumPersonalHash(block number || number of transactions || previous hash || merkle root), where || means concatenation. Values V, R, S are than concatenated to the header.

### Block
- Block header, as described above, 137 bytes
- RLP encoded array (list) of Numbered signed transactions, as described above

While some fields can be excessive, such block header can be submitted by anyone to the main Ethereum chain when block is availible, but for some reason not sent to the smart contract. Transaction numbering is done by the operator, it should be monotonically increasing without spaces and number of transactions in header should (although this is not necessary for the functionality) match the number of transactions in the Merkle tree and the full block.

## This contract differs from Minimal Viable Plasma in the following:

- Other transactions structure with nested RLP fields
- Deposit transactions are declarative: new block with 1 transaction is not created automatically (although can be easily changed), but deposit record is created and can be withdrawn back to user if Plasma operator doesn't provide transaction of appropriate structure (referencing this deposit, having proper owner and amount).
- "Slow" withdraw procedure (without burning mentioned above) user has to provide some collateral in case his withdraw will be challenged. If no challenge happened it's returned along with the value of UTXO being withdrawn.
- Anyone(!) can send a header of the block to the main chain, so if block is assembled and availible, but not yet pushed to the main chain, anyone can send a header on behalf of Plasma operator.
- Another important clarification - if user spots an invalid transaction (double spends, etc) a contract is switched to "Exit mode", with all withdraw transactions become an "Exit" transaction and an exit queue if formed. Through the text a word "withdraw" usually means pulling funds from Plasma to the main chain during the normal operation, while "Exit" is when invalid block spotted by at least one (responsible!) user who changes a state of the contract. Incentive will be added for the first person who catches the Plasma operator.


## Express withdraw is off for now

## Implemeted functionality:

All basic challanges and potential "cheats" for operator or user should be now covered

- Normal mode operation: deposit, withdraw, challanges of deposit and withdraw procedures.
- Some invalid transaction proofs:
   - double spend
   - double deposit
   - balance breaking in transaciton
   - ownership breaking

## List of intended challenges and tests
- [ ] Block header uploads
    - [x] should accept one properly signed header
    - [x] should NOT accept same header twice
    - [x] should accept two headers in right sequence
    - [x] should accept two headers in right sequence in the same transaction
    - [x] should NOT accept two headers in wrong sequence
    - [x] should NOT accept invalidly signed block header
    - [x] should NOT accept invalidly signed block header in sequence in one transaction
    - [x] should propery update two weeks old block number
    - [x] should check block hashes match in addition to block numbers in sequence
- [ ] Deposits
    - [x] should emit deposit event
    - [x] should allow deposit withdraw process
    - [ ] should respond to deposit withdraw challenge
    - [x] should allow successful deposit withdraw
    - [x] should require bond for deposit withdraw start
    - [ ] should stop Plasma on duplicate funding transaction
    - [ ] should stop Plasma on funding without deposit
    - [ ] should update total deposited amount for all tests above
    - [ ] should update amount pending exit for all tests above
- [ ] Withdrawals (normal process)
    - [ ] should start withdraw with proper proof
    - [ ] should respond to withdraw challenge
    - [ ] should allow succesful withdraw
    - [ ] should require bond for withdraw start 
    - [ ] should return bond on succeful withdraw
    - [ ] should return bond and prevent withdraw if Plasma was stopped in the meantime
    - [ ] should update amount pending withdraw for all tests above
    - [ ] should update total amount deposited for all tests above
- [ ] Exits (when Plasma is stopped)
    - [ ] should put withdraw in the quequ
    - [ ] should maintain priority in the queue
    - [ ] should give the same priority for blocks that are older than 2 weeks
    - [ ] should respond to exit prevention challenge
    - [ ] should allow succesful exit
    - [ ] should update amount pending withdraw for all tests above
    - [ ] should update total amount deposited for all tests above
- [ ] Challenges
    - [x] Invalid transaction in block (unserializable)
    - [x] should NOT stop on valid transaction (not malformed) in block
    - [x] Transaction in block references the future
    - [x] Transaction references an output with tx number larger, than number in transaction in this UTXO block
    - [ ] Transaction has higher number that number of transactions in block
    - [ ] Transaction is malformed (balance breaking)
    - [ ] Transaction is malformed (merge by Plasma owner)
    - [ ] Double spend
    - [ ] Spend without owner signature
    - [ ] UTXO was succesfully withdrawn and than spent in Plasma
    - [ ] Two transactions in block have the same number
    - [ ] Should have interactive challenge (show me the referenced input)

## Contribution

Everyone is welcome to spot mistakes in the logic of this contract as number of provided functions is substantial. If you find a potential error or security loophole (one that would allow Plasma operator or user to break the normal operation and not being caught) - please open an issue.

## Authors

Alex Vlasov, [@shamatar](https://github.com/shamatar),  av@bankexfoundation.org

## Further work

Making a hybrid of Minimal Viable Plasma and Plasma Cash to use separate tree of all transactions ever spent, and use this tree when withdraw procesure is executed.

Trial usage of invariant that sum of all unchallenged pending withdrawals should be less than or equal to a total balance of Plasma contract. It will prevent the case of block withholding by Plasma operator - by trying to do a double spend or unvalid ownership transfer and than to withhold few blocks to prevent a global stop he will most likely exceed such limitation.

## License

All source code and information in this repository is available under the Apache License 2.0 license. See the [LICENSE](https://github.com/BANKEX/PlasmaParentContract/blob/master/LICENSE) file for more info.