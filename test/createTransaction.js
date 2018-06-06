const {PlasmaTransaction,
TxTypeFund, 
TxTypeMerge, 
TxTypeSplit} = require("../lib/Tx/RLPtx.js");

const {PlasmaTransactionWithNumberAndSignature} = require("../lib/Tx/RLPtxWithNumberAndSignature");
const {PlasmaTransactionWithSignature} = require("../lib/Tx/RLPtxWithSignature");

const {TransactionInput} = require("../lib/Tx/RLPinput");
const {TransactionOutput} = require("../lib/Tx/RLPoutput");

const ethUtil = require("ethereumjs-util");
const BN = ethUtil.BN;

function createTransaction(transactionType, transactionNumber, inputs, outputs, privateKey) {
    const allInputs = [];
    const allOutputs = [];

    for (const input of inputs) {
        const inp = new TransactionInput({
            blockNumber: (new BN(input.blockNumber)).toBuffer("be",4),
            txNumberInBlock: (new BN(input.txNumberInBlock)).toBuffer("be",4),
            outputNumberInTransaction: (new BN(input.outputNumberInTransaction)).toBuffer("be",1),
            amountBuffer: (new BN(input.amount)).toBuffer("be",32)
        })
        allInputs.push(inp)
    }

    for (const output of outputs) {
        const out = new TransactionOutput({
            amountBuffer: (new BN(output.amount)).toBuffer("be",32),
            to: ethUtil.toBuffer(output.to)
        })
        allOutputs.push(out)
    }

    const plasmaTransaction = new PlasmaTransaction({
        transactionType: (new BN(transactionType)).toBuffer("be",1),
        inputs: allInputs,
        outputs: allOutputs,
    })

    // const hash = plasmaTransaction.hash();
    // const signature = ethUtil.ecsign(hash, privateKey)
    // const sig = ethUtil.toRpcSig(signature.v, signature.r, signature.s)
    const sigTX = new PlasmaTransactionWithSignature({
        transaction: plasmaTransaction
    });
    sigTX.sign(privateKey);

    // sigTX.serializeSignature(sig)

    const numberedTX = new PlasmaTransactionWithNumberAndSignature({
        transactionNumberInBlock: (new BN(transactionNumber)).toBuffer("be", 4),
        signedTransaction: sigTX
    })
    return numberedTX
}

function parseTransactionIndex(index) {
    let idx = new BN(index)
    const ONE = new BN(1);
    let outputNumber = idx.mod(ONE.ushln(8));
    idx = idx.ushrn(8);
    const txNumber = idx.mod(ONE.ushln(32));
    idx = idx.ushrn(32);
    const blockNumber = idx.mod(ONE.ushln(32));
    return {blockNumber, txNumber, outputNumber}
}

module.exports = {createTransaction, parseTransactionIndex};