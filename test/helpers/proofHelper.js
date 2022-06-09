const circomlib = require('circomlibjs')

const snarkjs = require('snarkjs')
const { unstringifyBigInts } = require('ffjavascript').utils

exports.makeProof = async function(orig1, orig2, buyerK, providerK) {
    const poseidon = await circomlib.buildPoseidonReference()
    const babyJub = await circomlib.buildBabyjub()
    const mimcjs = await circomlib.buildMimcSponge()
    const F = poseidon.F
    function conv(x) {
        const res = F.toObject(x)
        return res
    }
    const origHash = poseidon([F.e(orig1), F.e(orig2)])

    const buyerPub = babyJub.mulPointEscalar(babyJub.Base8, buyerK)
    const providerPub = babyJub.mulPointEscalar(babyJub.Base8, providerK)

    const k = babyJub.mulPointEscalar(buyerPub, providerK)

    const cipher = mimcjs.hash(orig1, orig2, k[0])

    const snarkParams = {
        // private
        xL_in: orig1,
        xR_in: orig2,
        provider_k: providerK,
        // public
        buyer_x: conv(buyerPub[0]),
        buyer_y: conv(buyerPub[1]),
        provider_x: conv(providerPub[0]),
        provider_y: conv(providerPub[1]),
        cipher_xL_in: conv(cipher.xL),
        cipher_xR_in: conv(cipher.xR),
        hash_plain: conv(origHash)
    }

    const { proof } = await snarkjs.plonk.fullProve(
        snarkParams,
        'circuits/keytransfer.wasm',
        'circuits/keytransfer.zkey'
    )

    const signals = [
        buyerPub[0],
        buyerPub[1],
        providerPub[0],
        providerPub[1],
        cipher.xL,
        cipher.xR,
        origHash
    ]

    const proofSolidity = (await snarkjs.plonk.exportSolidityCallData(unstringifyBigInts(proof), signals))
    const proofData = proofSolidity.split(',')[0]

    return {
        origHash: conv(origHash),
        buyerPub: [conv(buyerPub[0]), conv(buyerPub[1])],
        providerPub: [conv(providerPub[0]), conv(providerPub[1])],
        cipher: [conv(cipher.xL), conv(cipher.xR)],
        proof: proofData
    }
}
