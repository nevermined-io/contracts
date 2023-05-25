const assert = require('assert')
const { buildBn128 } = require('ffjavascript')
const { ethers } = require('ethers')

function flatten(lst) {
    return lst.reduce((a, b) => a.concat(b), [])
}

// poc for distributed key generation
// use the algorithm from frost

async function round1(t, i, ctx) {
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr
    const G1 = ffCurve.G1
    const G = G1.g

    // generate secrets
    const poly = Array(t).fill().map(_a => Fr.random())

    function evalPoly(x) {
        let xn = Fr.fromObject(1n)
        let res = Fr.fromObject(0n)
        for (const c of poly) {
            res = Fr.add(res, Fr.mul(c, xn))
            xn = Fr.mul(xn, Fr.fromObject(x))
        }
        return res
    }

    function hash(lst) {
        return Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(lst.map(a => 'uint256'), lst)))
    }

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    // proof of knowledge for the secret (Schnorr sig)
    const k = Fr.random()

    const R = G1.timesFr(G, k)
    const a0G = G1.timesFr(G, poly[0])
    const c = hash([i,ctx].concat(toEvm(a0G)).concat(toEvm(R)))

    const mu = Fr.add(k, Fr.mul(poly[0], c))

    const phi = poly.map(a => G1.timesFr(G, a))

    return {
        proof_mu: Fr.toObject(mu),
        proof_R: toEvm(R),
        commit: phi.map(a => toEvm(a)),
        idx: i,
        secrets: poly.map(a => Fr.toObject(a)),
        ctx,
    }

}

// validate signature
async function validate(obj) {

    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr
    const G1 = ffCurve.G1
    const G = G1.g

    // generate secrets
    const poly = Array(t).fill().map(_a => Fr.random())

    function hash(lst) {
        return Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(lst.map(a => 'uint256'), lst)))
    }
    const c = hash([obj.idx,obj.ctx].concat(toEvm(obj.commit[0])).concat(obj.proof_R))

}

// full protocol

async function proto(n, t, ctx) {
    let r1 = []
    for (let i = 0; i < n; i++) {
        r1.push(await round1(t, i, ctx))
    }

    console.log(r1)

    process.exit(0)

}

proto(5,3,23782732837n)
