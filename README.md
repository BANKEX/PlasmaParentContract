# Plasma Parent Contract

# This contract is active WIP, tests will be pushed in the next few days

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
- Has extended withdraw functionality in case of normal operation mode: user can emit transaction in Plasma chain burning his funds to address == 0 and amount == 0, than present proof of such burn to the contract along with a proof of ownership of the output that was burned and that output was created earlier than 1 week from now. This 1 week delay would allow everyone to stop invalid transaction from being burned or transfered and instantly burned (for example, a Plasma operator transfers someone's UTXO to his address and tries to withdraw immediately - than 1 week delay will start from the moment of transfering someone's UTXO to Plasma operator's controlled address, so other participants of Plasma can spot this transaction and move smart contract to "Exit" mode), while provides users a way to faster withdraw their funds that were not touched for some time (so you receive funds - burn them, and than can always withdraw this burned output a little bit faster. Requirements - original transaciton is > 7 days old, burning transaction > 2 days old for now).
- "Slow" withdraw procedure (without burning mentioned above) user has to provide some collateral in case his withdraw will be challenged. If no challenge happened it's returned along with the value of UTXO being withdrawn.
- Anyone(!) can send a header of the block to the main chain, so if block is assembled and availible, but not yet pushed to the main chain, anyone can send a header on behalf of Plasma operator.
- Another important clarification - if user spots an invalid transaction (double spends, etc) a contract is switched to "Exit mode", with all withdraw transactions become an "Exit" transaction and an exit queue if formed. Through the text a word "withdraw" usually means pulling funds from Plasma to the main chain during the normal operation, while "Exit" is when invalid block spotted by at least one (responsible!) user who changes a state of the contract. Incentive will be added for the first person who catches the Plasma operator.


## Implemeted functionality:

- Normal mode operation: deposit, withdraw, express withdraw, challanges of deposit and withdraw procedures.
- Some invalid transaction proofs - double spend, double deposit, etc. For not those proofs don't transfer the contract to an "Exit" mode, that requires 2 extra lines of code :)

## Contribution

Everyone is welcome to spot mistakes in the logic of this contract as number of provided functions is substantial. If you find a potential error or security loophole (one that would allow Plasma operator or user to break the normal operation and not being caught) - please open an issue.

## Authors

Alex Vlasov, [@shamatar](https://github.com/shamatar),  alex.m.vlasov@bankex.com

## Open questions

- Fast withdraws - are they even necessary?
- While in a process of sending funds A -> B inclusion of this transaction in a block and block being committed to the main chain is enough for everyone, we should develop some kind of mechanism for a user A who has an access to the full Plasma and main Ethereum network to produce some kind of proof that 
  1) transaction is included in Plasma block 
  2) Plasma block is included in the main chain
  
  so the user B can believe A even without access to the Plasma and Ethereum at that moment.

## License

All source code and information in this repository is available under the Apache License 2.0 license. See the [LICENSE](https://github.com/BANKEX/PlasmaParentContract/blob/master/LICENSE) file for more info.