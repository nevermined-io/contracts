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

    function hash(lst) {
        return Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(lst.map(a => 'uint256'), lst)))
    }
    const c = hash([obj.idx,obj.ctx].concat(obj.commit[0]).concat(obj.proof_R))

    const R = G1.fromObject([BigInt(obj.proof_R[0]), BigInt(obj.proof_R[1])])
    const mu = Fr.fromObject(obj.proof_mu)
    const phi0 = G1.fromObject([BigInt(obj.commit[0][0]), BigInt(obj.commit[0][1])])

    const check = G1.add(G1.timesFr(G, mu), G1.timesFr(phi0, Fr.neg(c)))

    assert(G1.eq(R, check))

}

async function makeShares(obj, n) {
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr
    const G1 = ffCurve.G1
    const G = G1.g

    const poly = obj.secrets.map(a => Fr.fromObject(a))

    function evalPoly(x) {
        let xn = Fr.fromObject(1n)
        let res = Fr.fromObject(0n)
        for (const c of poly) {
            res = Fr.add(res, Fr.mul(c, xn))
            xn = Fr.mul(xn, Fr.fromObject(x))
        }
        return res
    }

    let shares = []
    for (let i = 1; i <= n; i++) {
        let share = evalPoly(i)
        shares.push(Fr.toObject(share))
    }

    console.log("share", shares)

    return shares
}

async function verifyShares(obj, commits) {
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr
    const G1 = ffCurve.G1
    const G = G1.g

    function sumG1(lst) {
        return lst.reduce((a, b) => G1.add(a, b), G1.fromObject([0n, 0n]))
    }

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    function pow(a, n) {
        let res = Fr.fromObject(1n)
        for (let i = 0; i < n; i++) {
            res = Fr.mul(res, a)
        }
        return res
    } 

    const n = obj.shares.length
    const t = obj.secrets.length

    const idx = Fr.fromObject(BigInt(obj.idx+1))

    for (let l = 0; l < n; l++) {
        let share = Fr.fromObject(obj.shares[l])
        let pub = G1.timesFr(G, share)
        let asd = []
        for (let k = 0; k < t; k++) {
            let c = commits[l][k]
            let cp = G1.fromObject([BigInt(c[0]),BigInt(c[1])])
            let exp = pow(idx, k)
            // console.log("exp",Fr.toObject(exp))
            asd.push(G1.timesFr(cp, exp))
        }
        let check = sumG1(asd)
        // console.log("check", toEvm(check), "pub", toEvm(pub), obj.idx)
        assert(G1.eq(check, pub))
    }
}

// full protocol

async function proto(n, t, ctx) {
    let r1 = []
    let commits = []
    for (let i = 0; i < n; i++) {
        let obj = await round1(t, i, ctx)
        r1.push(obj)
        commits.push(obj.commit)
    }

    console.log(r1)

    for (let obj of r1) {
        await validate(obj)
    }

    console.log("validated proofs")

    // generate and send shares p2p
    let shares = []
    for (let obj of r1) {
        shares.push(await makeShares(obj, n))
        obj.shares = []
    }
    for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
            r1[i].shares.push(shares[j][i])
        }
    }
    console.log("sent shares")

    // each participant verifies shares and computes own key
    for (let obj of r1) {
        await verifyShares(obj, commits)
    }

    console.log("verified shares")


    process.exit(0)

}

proto(5,3,23782732837n)
