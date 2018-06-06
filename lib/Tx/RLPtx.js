const {blockNumberLength,
    txNumberLength,
    txTypeLength, 
    signatureVlength,
    signatureRlength,
    signatureSlength,
    merkleRootLength,
    previousHashLength,
    txOutputNumberLength,
    txAmountLength,
    txToAddressLength} = require('../dataStructureLengths');
  
  const ethUtil = require('ethereumjs-util')
  const BN = ethUtil.BN;
  const ZERO = new BN(0);
  const ZEROADDRESS = Buffer.alloc(txToAddressLength);
  const ZEROADDRESShex = ethUtil.bufferToHex(ZEROADDRESS);
  
  const defineProperties = require('../recursiveEncoder').defineProperties;
  const stripHexPrefix = require('strip-hex-prefix');
  
  const TxTypeSplit = 1;
  const TxTypeMerge = 2;
  const TxTypeWithdraw = 3;
  const TxTypeFund = 4;
  const TxTypeTransfer = 5;
  
  // secp256k1n/2
  const N_DIV_2 = new BN('7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0', 16)
  
  const {TransactionInput, TransactionInputLength} = require("./RLPinput");
  const {TransactionOutput, TransactionOutputLength} = require("./RLPoutput");
  
  class PlasmaTransaction {
    constructor (data) {
      data = data || {}
      // Define Properties
      const fields = [{
        name: 'transactionType',
        alias: 'txType',
        length: txTypeLength,
        allowLess: false,
        allowZero: true,
        default: Buffer.alloc(txTypeLength)
      }, {
        name: 'inputs',
        envelope: true,
        array: true,
        class: TransactionInput
      }, {
        name: 'outputs',
        envelope: true,
        array: true,
        class: TransactionOutput
      }];
  
      defineProperties(this, fields, data)
    }
  
    /**
     * If the tx's `to` is to the creation address
     * @return {Boolean}
     */
    toWithdrawAddress () {
      return  this.outputs[0].to.toString('hex') === '' &&
              this.outputs[0].amoutBuffer.toString('hex') === '' &&
              this.transactionTypeUInt() == TxTypeWithdraw
    }
  
      /**
     * If the tx's `from` is from the creation address
     * @return {Boolean}
     */
    fromFundingAddress () {
      return  this.inputs[0].blockNumber.toString('hex') === '' &&
              this.inputs[0].txNumberInBlock.toString('hex') === '' &&
              this.inputs[0].outputNumberInTransaction.toString('hex') === '' &&
              this.transactionTypeUInt() === TxTypeFund
    }

    getTransactionInput(inputNumber) {
        if (this.inputs[inputNumber]) {
          return this.inputs[inputNumber]
        }
        return null;
    }
  
    getTransactionOutput(outputNumber) {
        if (this.outputs[outputNumber]) {
          return this.outputs[outputNumber]
        }
        return null;
    }
  
    getKey() {
      if(this._key) {
        return this._key;
      }
      this._key = "";
      for (let i of [0,1]) {
          let inp = this.getTransactionInput(i);
          if (inp && typeof inp !== "undefined") {
            this._key = this._key + inp.getKey();
          }
      }
      return this._key;
    }

    transactionTypeUInt() {
      const txType = ethUtil.bufferToInt(this.transactionType)
      return txType;
    }
  
    /**
     * validates the signature and checks internal consistency
     * @param {Boolean} [stringError=false] whether to return a string with a dscription of why the validation failed or return a Bloolean
     * @return {Boolean|String}
     */
    validate (stringError) {
      const errors = []
      if (stringError === undefined || stringError === false) {
        return errors.length === 0
      } else {
        return errors.join(', ')
      }
    }
  
    isWellFormed() {
      const txType = this.transactionTypeUInt()
      const numInputs = this.inputs.length;
      const numOutputs = this.outputs.length
      if (txType === TxTypeMerge) {
          if (numInputs !== 2 || numOutputs !== 1) {
              return false
          }
      } else if (txType === TxTypeSplit) {
          if (numInputs !== 1 || (numOutputs < 1 || numOutputs > 3)) {
              return false
          }
      } else if (txType === TxTypeFund) {
          if (numInputs !== 1 || numOutputs !== 1) {
              return false
          }
      } else {
        return false;
      }

      if (txType !== TxTypeFund) {
        let inputsTotalValue = new BN(0);
        let outputsTotalValue = new BN(0);
        let outputCounter = 0;
          for (let input of this.inputs) {
              inputsTotalValue.iadd(input.value);
          }
          for (let output of this.outputs) {
              if (output.value.lte(0)) {
                return false;
              }
              if (ethUtil.bufferToInt(output.outputNumberInTransaction) !== outputCounter) {
                return false;
              }
              outputsTotalValue.iadd(output.value);
              const addr = ethUtil.bufferToHex(output.to);
              if (addr === undefined || addr === null) {
                  return false;
              }
              outputCounter++;
          }
          if (!outputsTotalValue.eq(inputsTotalValue)) {
            return false;
          }
      }
      return true;
    }

    toFullJSON(labeled) {
      if (labeled) {
        const rawObj = this.toJSON(labeled);
        const transactionType = this.transactionTypeUInt()
        const obj = {
          transactionType,
          inputs: [],
          outputs: []
        }
        for (let inp of this.inputs) {
          obj.inputs.push(inp.toFullJSON(labeled))
        }
        for (let out of this.outputs) {
          obj.outputs.push(out.toFullJSON(labeled))
        }
        return obj
      } else {
        return ethUtil.baToJSON(this.raw)
      }
    }
  }
  
  
  const NumInputsForType = {}
  NumInputsForType[TxTypeFund] =  1
  NumInputsForType[TxTypeWithdraw] = 0
  NumInputsForType[TxTypeMerge] = 2
  NumInputsForType[TxTypeSplit] = 1
  NumInputsForType[TxTypeTransfer] = 0
  
  const NumOutputsForType = {}
  NumOutputsForType[TxTypeFund] = 1
  NumOutputsForType[TxTypeWithdraw] = 0
  NumOutputsForType[TxTypeMerge] = 1
  NumOutputsForType[TxTypeSplit] = 3
  NumOutputsForType[TxTypeTransfer] = 0
  
  module.exports = {PlasmaTransaction,
                    TxTypeFund, 
                    TxTypeMerge, 
                    TxTypeSplit, 
                    TxTypeWithdraw,
                    TxTypeTransfer, 
                    NumInputsForType,
                    NumOutputsForType}