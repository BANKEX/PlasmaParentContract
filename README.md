# Plasma Parent Contract

## This contract differs from Minimal Viable Plasma in the following:

- Other transactions structure with nested RLP fields
- Deposit transactions are declarative: new block with 1 transaction is not created automatically (although can be easily changed), but deposit record is created and can be withdrawn back to user if Plasma operator doesn't provide transaction of appropriate structure (referencing this deposit, having proper owner and amount).
- Has extended withdraw functionality in case of normal operation mode: user can emit transaction in Plasma chain burning his funds to address == 0 and amount == 0, than present proof of such burn to the contract along with a proof of ownership of the output that was burned and that output was created earlier than 1 week from now. This 1 week delay would allow everyone to stop invalid transaction from being burned or transfered and instantly burned (for example, a Plasma operator transfers someone's UTXO to his address and tries to withdraw immediately - than 1 week delay will start from the moment of transfering someone's UTXO to Plasma operator's controlled address, so other participants of Plasma can spot this transaction and move smart contract to "Exit" mode), while provides users a way to instantly withdraw their funds that were not touched for some time.
- "Slow" withdraw procedure (without burning mentioned above) user has to provide some collateral in case his withdraw will be challenged. If no challenge happened it's returned along with the value of UTXO being withdrawn.


## Implemeted functionality:

- Normal mode operation: deposit, withdraw, express withdraw, challanges of deposit and withdraw procedures.
- Some invalid transaction proofs - double spend, double deposit, etc. For not those proofs don't transfer the contract to an "Exit" mode, that requires 2 extra lines of code :)

## Contribution

Everyone is welcome to spot mistakes in the logic of this contract as number of provided functions is substantial. If you find a potential error or security loophole (one that would allow Plasma operator or user to break the normal operation and not being caught) - please open an issue.

## Authors

## Authors

Alex Vlasov, [@shamatar](https://github.com/shamatar),  alex.m.vlasov@bankex.com
