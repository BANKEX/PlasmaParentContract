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
  const TxTypeFund = 4;

  // const secp256k1 = require("secp256k1");
  
  // secp256k1n/2
  const N_DIV_2 = new BN('7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0', 16)
  
  const {TransactionInput, TransactionInputLength} = require("./RLPinput");
  const {TransactionOutput, TransactionOutputLength} = require("./RLPoutput");
  const {PlasmaTransaction} = require("./RLPtx");
  
  class PlasmaTransactionWithSignature {
    constructor (data) {
      data = data || {}
      // Define Properties
      const fields = [{
        name: 'transaction',
        envelope: true,
        array: false,
        class: PlasmaTransaction
      }, {
        name: 'v',
        allowZero: true,
        length: signatureVlength,
        allowLess: false,
        default: Buffer.alloc(signatureVlength)
      }, {
        name: 'r',
        length: signatureRlength,
        allowZero: true,
        allowLess: false,
        default: Buffer.alloc(signatureRlength)
      }, {
        name: 's',
        length: signatureSlength,
        allowZero: true,
        allowLess: false,
        default: Buffer.alloc(signatureSlength)
      }]

      this._from = null;
      this._senderPubKey = null;

      defineProperties(this, fields, data)
      /**
       * @property {Buffer} from (read only) sender address of this transaction, mathematically derived from other parameters.
       * @name from
       * @memberof Transaction
       */
      Object.defineProperty(this, 'from', {
        enumerable: true,
        configurable: true,
        get: this.getSenderAddress.bind(this)
      })
    }

    /**
     * returns the sender's address
     * @return {Buffer}
     */
    getSenderAddress () {
      if (this._from !== null) {
        return this._from
      }
      const pubkey = this.getSenderPublicKey()
      this._from = ethUtil.publicToAddress(pubkey)
      return this._from
    }

    /**
     * returns the public key of the sender
     * @return {Buffer}
     */
    getSenderPublicKey () {
      if (this._senderPubKey === null || this._senderPubKey.length === 0) {
        if (!this.verifySignature()) {
          return null;
        }
      }
      return this._senderPubKey
    }
    
    /**
     * Determines if the signature is valid
     * @return {Boolean}
     */
    verifySignature () {
      const msgHash = this.transaction.hash();

      // check is haldled by secp256k1 itself

      // All transaction signatures whose s-value is greater than secp256k1n/2 are considered invalid.
      if (new BN(this.s).cmp(N_DIV_2) === 1) {
        return false
      }
  
      try {
        
        let v = ethUtil.bufferToInt(this.v);
        this._senderPubKey = ethUtil.ecrecover(msgHash, v, this.r, this.s)

        // let v = ethUtil.bufferToInt(this.v) - 27;
        // const signature = Buffer.concat([this.r, this.s]);
        // this._senderPubKey = secp256k1.recover(msgHash, signature, v, false).slice(1);
      } catch (e) {
        return false
      }
  
      return !!this._senderPubKey
    }
  
    /**
     * sign a transaction with a given a private key
     * @param {Buffer} privateKey
     */
    sign (privateKey) {
      const msgHash = this.transaction.hash()
      const sig = ethUtil.ecsign(msgHash, privateKey)
      if (sig.v < 27){
          sig.v += 27
      }
      Object.assign(this, sig);
      this._from = null;
      this.verifySignature();
    }


    serializeSignature(signatureString) {
        const signature = stripHexPrefix(signatureString);
        let r = ethUtil.addHexPrefix(signature.substring(0,64));
        let s = ethUtil.addHexPrefix(signature.substring(64,128));
        let v = ethUtil.addHexPrefix(signature.substring(128,130));
        r = ethUtil.toBuffer(r);
        s = ethUtil.toBuffer(s);
        v = ethUtil.bufferToInt(ethUtil.toBuffer(v));
        if (v < 27) {
            v = v + 27;
        }
        v = ethUtil.toBuffer(v);
        // this.v = v
        // this.r = r
        // this.s = s
        Object.assign(this, {v, r, s});
        this._from = null;
        this.verifySignature();
      }

    /**
     * validates the signature and checks internal consistency
     * @param {Boolean} [stringError=false] whether to return a string with a dscription of why the validation failed or return a Bloolean
     * @return {Boolean|String}
     */
    validate (stringError) {
        const errors = []
        if (!this.transaction.validate()) {
          error.push("Malformed transaction")
        }
        if (!this.verifySignature()) {
          errors.push('Invalid Signature')
        }
        if (stringError === undefined || stringError === false) {
          return errors.length === 0
        } else {
          return errors.join(', ')
        }
      }
          
    isWellFormed() {
      if (!this.transaction.isWellFormed()){
        return false
      }
      if (this.from === null) {
        return false
      }
      return true
    }

    toFullJSON(labeled) {
      if (labeled) {
        const rawObj = this.transaction.toFullJSON(labeled);
        const obj = {
            transaction: rawObj,
            v: ethUtil.bufferToHex(this.v),
            r: ethUtil.bufferToHex(this.r),
            s: ethUtil.bufferToHex(this.s)
          }
        return obj
      } else {
        return ethUtil.baToJSON(this.raw)
      }
    }
  }

  module.exports = {PlasmaTransactionWithSignature}