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
              this.transactionTypeUInt() == TxTypeFund
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
          if (inp && typeof inp != "undefined") {
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
      // const length = Buffer.concat(this.clearRaw(true, true)).length;
      const txType = this.transactionTypeUInt();
      // if (length !== TxLengthForType[txType]) {
      //   errors.push('Invalid Length');
      // }
      // for (let i of [0,1]) {
      //   const input = this.getTransactionInput(i);
      //   if (input && input.outputNumberInTransaction.equals(Buffer.from("ff", "hex")) ) {
      //         errors.push('Invalid Input Numbers')
      //       }
      // }
      // if (txType == TxTypeMerge) {
      //   if (!this.getTransactionInput(0).to.equal(this.getTransactionInput(1).to)){
      //     errors.push('Invalid Inputs')
      //   }
      // } else 
      if (txType == TxTypeWithdraw) {
        const output = this.getTransactionOutput(0);
        if (!output.to.equal(ZEROADDRESS) || !output.value.isZero()){
          errors.push('Invalid Withdraw Output')
        }
      }
      if (stringError === undefined || stringError === false) {
        return errors.length === 0
      } else {
        return errors.join(', ')
      }
    }
  
    toFullJSON(labeled) {
      if (labeled) {
        const rawObj = this.toJSON(labeled);
        const transactionType = this.transactionTypeUInt()
        var obj = {
          transactionType,
          inputs: {},
          outputs: {}
        }
        for (let i of [0,1]) {
          const inp = this.getTransactionInput(i);
          if (inp && typeof inp !== "undefined") {
            obj.inputs[i] = inp.toFullJSON(labeled)
          }
        }
        for (let i of [0,1]) {
          const out = this.getTransactionOutput(i);
          if (out && typeof out !== "undefined") {
            obj.outputs[i] = out.toFullJSON(labeled)
          }
        }
        return obj
      } else {
        return ethUtil.baToJSON(this.raw)
      }
    }
  }
  
  // // const dummy = new PlasmaTransaction();
  // // const TXmainLength = Buffer.concat(dummy.raw.filter((r) =>{
  // //   return typeof r !== "undefined"
  // // })).length
  
  // const TXmainLength = 100;

  // const TxLengthForType = {};
  // TxLengthForType[TxTypeMerge]= TXmainLength+2*TransactionInputLength + 1*TransactionOutputLength
  // TxLengthForType[TxTypeSplit]= TXmainLength+1*TransactionInputLength + 2*TransactionOutputLength
  // TxLengthForType[TxTypeWithdraw]= TXmainLength+1*TransactionInputLength + 1*TransactionOutputLength
  // TxLengthForType[TxTypeFund]= TXmainLength+1*TransactionInputLength + 2*TransactionOutputLength
  // TxLengthForType[TxTypeTransfer]= TXmainLength+1*TransactionInputLength + 1*TransactionOutputLength
  
  // PlasmaTransaction.prototype.initTxForTypeFromBinary = function(txType, blob) {
  //   const numInputs = NumInputsForType[txType];
  //   const numOutputs = NumOutputsForType[txType];
  //   if (numInputs == undefined || numOutputs == undefined) {
  //     return null;
  //   }
  //   const splitFront = [];
  //   let i=0;
  //   for (let sliceLen of [txNumberLength, txTypeLength]) {
  //     splitFront.push(blob.slice(i, i+ sliceLen));
  //     i += sliceLen;
  //   }
  //   const txParams = {};
  //   for (let j = 0; j < numInputs; j++){
  //     const input = TransactionInput.prototype.initFromBinaryBlob(blob.slice(i, i+TransactionInputLength));
  //     i+= TransactionInputLength;
  //     txParams["inputNum"+j] = Buffer.concat(input.raw);
  //   }
  //   for (let j = 0; j < numOutputs; j++){
  //     const output = TransactionOutput.prototype.initFromBinaryBlob(blob.slice(i, i+TransactionOutputLength));
  //     i+= TransactionOutputLength;
  //     txParams["outputNum"+j] = Buffer.concat(output.raw);
  //   }
  //   const splitEnd = [];
  //   for (let sliceLen of [signatureVlength, signatureRlength, signatureSlength]) {
  //     splitEnd.push(blob.slice(i, i+ sliceLen));
  //     i += sliceLen;
  //   }
  //   txParams['transactionNumberInBlock'] = splitFront[0];
  //   txParams['transactionType'] = splitFront[1];
  //   txParams['v'] = splitEnd[0];
  //   txParams['r'] = splitEnd[1];
  //   txParams['s'] = splitEnd[2];
  //   const TX = new PlasmaTransaction(txParams);
  //   return TX;
  // }
  
  
  
  const NumInputsForType = {}
  NumInputsForType[TxTypeFund] =  1
  NumInputsForType[TxTypeWithdraw] = 1
  NumInputsForType[TxTypeMerge] = 2
  NumInputsForType[TxTypeSplit] = 1
  NumInputsForType[TxTypeTransfer] = 1
  
  const NumOutputsForType = {}
  NumOutputsForType[TxTypeFund] = 2
  NumOutputsForType[TxTypeWithdraw] = 1
  NumOutputsForType[TxTypeMerge] = 1
  NumOutputsForType[TxTypeSplit] = 2
  NumOutputsForType[TxTypeTransfer] = 1
  
  module.exports = {PlasmaTransaction,
                    TxTypeFund, 
                    TxTypeMerge, 
                    TxTypeSplit, 
                    TxTypeWithdraw,
                    TxTypeTransfer, 
                    // TxLengthForType,
                    NumInputsForType,
                    NumOutputsForType}