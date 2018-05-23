pragma solidity ^0.4.24;

import {BankexPlasmaTransaction} from "./PlasmaTransactionLibrary.sol";

contract TXTester {
    constructor() {

    }

    // function proveInvalidTransaction(bytes _plasmaTransaction) public returns (bool success) {   
    //     BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
    //     require(!TX.isWellFormed);
    //     return true;
    // }
    
    function parseTransaction(bytes _plasmaTransaction) public view returns (uint32 txNum, uint8 txType, uint numIns, uint numOuts, address sender, bool isWellFormed ) {   
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        return (TX.txNumberInBlock, TX.txType, TX.inputs.length, TX.outputs.length, TX.sender, TX.isWellFormed);
    }

    function getInputInfo(bytes _plasmaTransaction, uint8 _inputNumber) public view returns (uint32 blockNumber, uint32 txNumberInBlock, uint8 outputNumberInTx, uint amount) {   
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        BankexPlasmaTransaction.TransactionInput memory input = TX.inputs[_inputNumber];
        return (input.blockNumber, input.txNumberInBlock, input.outputNumberInTX, input.amount);
    }

    function getOutputInfo(bytes _plasmaTransaction, uint8 _outputNumber) public view returns (uint8 outputNumberInTx, address recipient, uint amount) {   
        BankexPlasmaTransaction.PlasmaTransaction memory TX = BankexPlasmaTransaction.plasmaTransactionFromBytes(_plasmaTransaction);
        BankexPlasmaTransaction.TransactionOutput memory output = TX.outputs[_outputNumber];
        return (output.outputNumberInTX, output.recipient, output.amount);
    }
}