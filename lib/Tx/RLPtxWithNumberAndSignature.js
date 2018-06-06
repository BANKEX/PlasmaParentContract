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
  const {PlasmaTransaction} = require("./RLPtx");
  const {PlasmaTransactionWithSignature} = require("./RLPtxWithSignature");
  
  class PlasmaTransactionWithNumberAndSignature {
    constructor (data) {
      data = data || {}
      // Define Properties
      const fields = [
      {
        name: 'transactionNumberInBlock',
        length: txNumberLength,
        alias : "txNumberInBlock",
        allowLess: false,
        allowZero: true,
        default: Buffer.alloc(txNumberLength)
      }, {
        name: 'signedTransaction',
        envelope: true,
        array: false,
        class: PlasmaTransactionWithSignature
      }]
      defineProperties(this, fields, data)
      /**
       * @property {Buffer} from (read only) sender address of this transaction, mathematically derived from other parameters.
       * @name from
       * @memberof Transaction
       */
      Object.defineProperty(this, 'from', {
        enumerable: true,
        configurable: true,
        get: this.signedTransaction.getSenderAddress
      })
    }

  
    /**
     * Determines if the signature is valid
     * @return {Boolean}
     */
    verifySignature () {
      return this.signedTransaction.verifySignature();
    }
  
    /**
     * sign a transaction with a given a private key
     * @param {Buffer} privateKey
     */
    sign (privateKey) {
      return this.signedTransaction.sign(privateKey);
    }


    serializeSignature(signatureString) {
        return this.signedTransaction.serializeSignature(signatureString);
      }

    /**
     * validates the signature and checks internal consistency
     * @param {Boolean} [stringError=false] whether to return a string with a dscription of why the validation failed or return a Bloolean
     * @return {Boolean|String}
     */
    validate (stringError) {
        return this.signedTransaction.validate();
      }

    isWellFormed() {
      return this.signedTransaction.isWellFormed();
    }
      
    toFullJSON(labeled) {
      if (labeled) {
        const rawObj = this.signedTransaction.toFullJSON(labeled);
        const txNumberInBlock = ethUtil.bufferToInt(this.txNumberInBlock)
        const obj = {
            txNumberInBlock,
            transactionWithSignature: rawObj
          }
        return obj
      } else {
        return ethUtil.baToJSON(this.raw)
      }
    }
  }

  module.exports = {PlasmaTransactionWithNumberAndSignature}