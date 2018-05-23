const {blockNumberLength,
    txNumberLength,
    txTypeLength, 
    signatureVlength,
    signatureRlength,
    signatureSlength,
    merkleRootLength,
    previousHashLength} = require('../dataStructureLengths');

const assert = require('assert');
const ethUtil = require('ethereumjs-util');
const BN = ethUtil.BN
const {PlasmaTransactionWithNumberAndSignature} = require('../Tx/RLPtxWithNumberAndSignature');
const MerkleTools = require('../merkle-tools');
const {BlockHeader, BlockHeaderLength, BlockHeaderNumItems} = require('./blockHeader'); 
const stripHexPrefix = require('strip-hex-prefix');

// secp256k1n/2
const N_DIV_2 = new BN('7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0', 16);

class Block {
  constructor (data) {
    if (data instanceof Object && data.constructor === Object ){ 
        this.blockNumber = data.blockNumber || Buffer.alloc(blockNumberLength);
        this.parentHash = data.parentHash || Buffer.alloc(previousHashLength);
        this.transactions = data.transactions || [];
        this.numberOfTransactions = data.transactions.length || 0;
        const numberOfTransactionsBuffer = ethUtil.setLengthLeft(ethUtil.toBuffer(this.numberOfTransactions), txNumberLength);

        assert(this.transactions && Array.isArray(this.transactions), "TXs should be an array");
        const treeOptions = {
            hashType: 'sha3'
        }
        
        this.merkleTree = new MerkleTools(treeOptions)
        for (let i = 0; i < this.transactions.length; i++) {
            const tx = this.transactions[i];
            assert(tx.validate());
            const txHash = tx.hash();
            this.merkleTree.addLeaf(txHash);
        }  
        assert (this.merkleTree.getLeafCount() == this.numberOfTransactions);
        this.merkleTree.makeTree(false);
        const rootValue = this.merkleTree.getMerkleRoot() || Buffer.alloc(merkleRootLength);
        // console.log("Merkle root of block is " + ethUtil.bufferToHex(rootValue));
        const headerParams = {
            blockNumber: this.blockNumber,
            parentHash: this.parentHash,
            merkleRootHash: rootValue,
            numberOfTransactions: numberOfTransactionsBuffer
        }
        this.header = new BlockHeader(headerParams);
    } else if (Buffer.isBuffer(data)) {
        this.transactions = [];
        const head = data.slice(0, BlockHeaderLength);
        let i = 0;
        const headerArray = [];
        for (let sliceLen of [blockNumberLength, txNumberLength, previousHashLength, merkleRootLength, signatureVlength, signatureRlength, signatureSlength]) {
            headerArray.push(head.slice(i, i + sliceLen));
            i += sliceLen;
        }
        this.header = new BlockHeader(headerArray);
        const transactionsBuffer = data.slice(BlockHeaderLength, data.length);
        const transactionsList = ethUtil.rlp.decode(transactionsBuffer);
        for (let rawTX of transactionsList) {
            const TX = new PlasmaTransactionWithNumberAndSignature(rawTX);
            assert(TX.validate());
            this.transactions.push(TX);
        }
        assert(this.transactions.length == ethUtil.bufferToInt(this.header.numberOfTransactions));
        const treeOptions = {
            hashType: 'sha3'
          }
        this.merkleTree = new MerkleTools(treeOptions)
        for (let j = 0; j < this.transactions.length; j++) {
            const tx = this.transactions[j];
            const txHash = tx.hash();
            this.merkleTree.addLeaf(txHash);
        }  
        assert(this.merkleTree.getLeafCount() == this.transactions.length);
        this.merkleTree.makeTree(false);
        const rootValue = this.merkleTree.getMerkleRoot();
        assert(rootValue.equals(this.header.merkleRootHash))
        // assert(this.header.validate());
    }
    Object.defineProperty(this, 'from', {
      enumerable: true,
      configurable: true,
      get: this.getSenderAddress.bind(this)
    })

    Object.defineProperty(this, 'raw', {
        get: function () {
        return this.serialize()
        }
    })
    
}

serializeSignature(signatureString) {
    this.header.serializeSignature(signatureString);
  }
   
serialize() {
    var txRaws = [];
    for (var i=0; i < this.transactions.length; i++) {
        const tx = this.transactions[i];
        assert(tx.validate());
        txRaws.push(tx.rlpEncode());
    }
    return this.header.raw.concat(ethUtil.rlp.encode(txRaws));
}  

clearRaw(includeSignature) {
    return this.header.clearRaw(includeSignature);
  }

  /**
   * Computes a sha3-256 hash of the serialized tx
   * @param {Boolean} [includeSignature=true] whether or not to inculde the signature
   * @return {Buffer}
   */
  hash (includeSignature) {
      return this.header.hash(includeSignature)
  }

  /**
   * returns the sender's address
   * @return {Buffer}
   */
  getSenderAddress () {
      return this.header.getSenderAddress()
  }

  /**
   * returns the public key of the sender
   * @return {Buffer}
   */
  getSenderPublicKey () {
      return this.header._senderPubKey
  }

  getMerkleHash () {
    return this.header.merkleRootHash;
  }

  /**
   * Determines if the signature is valid
   * @return {Boolean}
   */
  verifySignature () {
      return this.header.verifySignature()
  }

  /**
   * sign a transaction with a given a private key
   * @param {Buffer} privateKey
   */
  sign (privateKey) {
      this.header.sign(privateKey)
  }


  /**
   * validates the signature and checks to see if it has enough gas
   * @param {Boolean} [stringError=false] whether to return a string with a dscription of why the validation failed or return a Bloolean
   * @return {Boolean|String}
   */
  validate (stringError) {
    const errors = []
    if (this.transactions.length !== ethUtil.bufferToInt(this.header.numberOfTransactions)) {
        errors.push("Invalid number of transactions")
    }
    if (!this.verifySignature()) {
        errors.push('Invalid Signature')
    }
    if (stringError === undefined || stringError === false) {
        return errors.length === 0
    } else {
        return errors.join(' ')
    }
  }

}

Block.prototype.toJSON = function (labeled) {
    if (labeled) {
      var obj = {
        header: this.header.toJSON(labeled),
        transactions: []
      }
  
      this.transactions.forEach(function (tx) {
        const txJSON = tx.toJSON(labeled)
        obj.transactions.push(txJSON);
      })
  
      return obj
    } else {
      return ethUtil.baToJSON(this.raw)
    }
  }

Block.prototype.toFullJSON = function (labeled) {
    if (labeled) {
      var obj = {
        header: this.header.toFullJSON(labeled),
        transactions: []
      }
  
      this.transactions.forEach(function (tx) {
        const txJSON = tx.toFullJSON(labeled)
        obj.transactions.push(txJSON);
      })
      return obj
    } else {
      return ethUtil.baToJSON(this.raw)
    }
  }

module.exports = Block