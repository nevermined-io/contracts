
const assert = require('assert')
const { buildBn128 } = require('ffjavascript')
const { ethers } = require('ethers')

function flatten(lst) {
    return lst.reduce((a, b) => a.concat(b), [])
}

async function frostDLEQ(n, t) {
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr

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

    // compute shares
    const shares = Array(n).fill().map((_a, i) => evalPoly(BigInt(i + 1)))

    console.log('secrets', poly.map(a => Fr.toObject(a)), 'shares', shares.map(a => Fr.toObject(a)))

    const ids = [2, 3, 4]

    function coeff(i) {
        let res = Fr.fromObject(1n)
        for (const id of ids) {
            if (id === i) continue
            const idneg = Fr.neg(Fr.fromObject(id + 1))
            res = Fr.mul(res, Fr.div(idneg, Fr.add(Fr.fromObject(i + 1), idneg)))
        }
        return res
    }

    // compute coefficients
    const coeffs = ids.map(coeff)

    console.log('coeffs', coeffs.map(a => Fr.toObject(a)))

    // reconstruct secret
    function sum(lst) {
        return lst.reduce((a, b) => Fr.add(a, b), Fr.fromObject(0n))
    }

    function sumG1(lst) {
        return lst.reduce((a, b) => G1.add(a, b), G1.fromObject([0n, 0n]))
    }

    const secret = sum(coeffs.map((c, i) => Fr.mul(c, shares[ids[i]])))

    console.log('secret?', Fr.toObject(secret))

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    // recomputing public key

    const G1 = ffCurve.G1
    const G = G1.g

    const y = secret
    const yG = G1.timesFr(G, y)

    console.log('public key', toEvm(yG))

    const pubkey = sumG1(coeffs.map((c, i) => G1.timesFr(G1.timesFr(G, shares[ids[i]]), c)))

    console.log('public key?', toEvm(pubkey))

    // generate secret for encypting the password
    const x = Fr.random()
    const xG = G1.timesFr(G, x)

    assert(G1.eq(xG, G1.timesFr(G, x)))

    // shared secret
    const xyG = G1.timesFr(xG, y)
    assert(G1.eq(xyG, G1.timesFr(yG, x)))

    // generate secret for consumer
    const z = Fr.random()
    const zG = G1.timesFr(G, z)

    // re-encrypt the secret
    const R = G1.add(xG, zG)
    const yR = G1.timesFr(R, y)

    // re-encrypt with threshold
    const yR_ = sumG1(coeffs.map((c, i) => G1.timesFr(G1.timesFr(R, shares[ids[i]]), c)))
    console.log('re-encrypted', toEvm(yR))
    console.log('re-encrypted?', toEvm(yR_))

    // consumer figures out the shared secret
    const R1 = G1.add(yR, G1.neg(G1.timesFr(yG, z)))
    assert(G1.eq(R1, xyG))

    /// /////////////////////////////////////////////////////
    // DLEQ aggregation

    // commitment round, participants give their commitments (and store secrets)
    const nonces = ids.map((id, i) => {
        const s1 = Fr.random()
        const s2 = Fr.random()
        const c1 = G1.timesFr(G, s1)
        const c2 = G1.timesFr(G, s2)
        const c3 = G1.timesFr(R, s1)
        const c4 = G1.timesFr(R, s2)
        const pub1 = G1.timesFr(G, shares[id])
        const pub2 = G1.timesFr(R, shares[id])
        return { id, coeff: coeffs[i], share: shares[id], s1, s2, c1, c2, c3, c4, pub1, pub2 }
    })

    // starting signing for each participant in the network

    // for public commitments, compute hash
    function hash(lst) {
        return Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(lst.map(a => 'uint256'), lst)))
    }

    const label = 1234n

    // compute binding values
    nonces.forEach(a => {
        a.bind = hash([a.id, label].concat(flatten(nonces.map(({ c1, c2, c3, c4 }) => [].concat(toEvm(c1)).concat(toEvm(c2)).concat(toEvm(c3)).concat(toEvm(c4))))))
        a.commit1 = G1.add(a.c1, G1.timesFr(a.c2, a.bind))
        a.commit2 = G1.add(a.c3, G1.timesFr(a.c4, a.bind))
    })

    console.log('b hash', nonces.map(a => Fr.toObject(a.bind)))

    // compute group commitment
    const rCommit1 = sumG1(nonces.map(a => a.commit1))
    console.log('group commitment1', toEvm(rCommit1))
    const rCommit2 = sumG1(nonces.map(a => a.commit2))
    console.log('group commitment2', toEvm(rCommit2))

    // compute challenge
    const chal = hash([label].concat(toEvm(yG)).concat(toEvm(yR)).concat(toEvm(rCommit1)).concat(toEvm(rCommit2)))
    console.log('challenge', Fr.toObject(chal))

    // compute response for each participant
    nonces.forEach(a => {
        a.resp = Fr.add(a.s1, Fr.add(Fr.mul(a.s2, a.bind), Fr.neg(Fr.mul(a.coeff, Fr.mul(a.share, chal)))))
    })
    console.log('responses', nonces.map(a => Fr.toObject(a.resp)))

    // aggregating signatures

    // verify partial signatures
    nonces.forEach(a => {
        const resp1 = G1.timesFr(G, a.resp)
        const committedResp1 = G1.add(a.commit1, G1.neg(G1.timesFr(a.pub1, Fr.mul(chal, a.coeff))))
        const resp2 = G1.timesFr(R, a.resp)
        const committedResp2 = G1.add(a.commit2, G1.neg(G1.timesFr(a.pub2, Fr.mul(chal, a.coeff))))
        console.log('resp1', toEvm(resp1), 'should be', toEvm(committedResp1))
        console.log('resp2', toEvm(resp2), 'should be', toEvm(committedResp2))
    })

    const rResp = sum(nonces.map(a => a.resp))
    console.log('group response', Fr.toObject(rResp))

    // verify schnorr signature

    const check1 = G1.add(G1.timesFr(G, rResp), G1.timesFr(yG, chal))
    console.log('checking DLEQ', toEvm(check1))
    const check2 = G1.add(G1.timesFr(R, rResp), G1.timesFr(yR, chal))
    console.log('checking DLEQ', toEvm(check2))

    console.log('group commitment1', toEvm(rCommit1))
    console.log('group commitment2', toEvm(rCommit2))

    // these were reconstructed from resp and chal
    // so it is enough to construct challenge from these and check it's correct

    // process.exit(0)
}

// frostDLEQ(10, 3)

async function setupEG() {
    const ffCurve = await buildBn128()
    const G1 = ffCurve.G1
    const Fr = ffCurve.Fr

    const G = G1.g

    // generate secret for gateway / network
    const y = Fr.random()
    const yG = G1.timesFr(G, y)

    // generate secret for encypting the password
    const x = Fr.random()
    const xG = G1.timesFr(G, x)

    assert(G1.eq(xG, G1.timesFr(G, x)))

    // shared secret
    const xyG = G1.timesFr(xG, y)
    assert(G1.eq(xyG, G1.timesFr(yG, x)))

    // generate secret for consumer
    const z = Fr.random()
    const zG = G1.timesFr(G, z)

    // re-encrypt the secret
    const R = G1.add(xG, zG)
    const yR = G1.timesFr(R, y)

    // consumer figures out the shared secret
    const R1 = G1.add(yR, G1.neg(G1.timesFr(yG, z)))
    assert(G1.eq(R1, xyG))

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    return {
        provider: toEvm(yG),
        buyer: toEvm(zG),
        secretId: toEvm(xG),
        reencrypt: toEvm(yR),
        yG,
        xG,
        zG,
        R,
        yR,
        y,
        z,
        providerSecret: y,
        buyerSecret: z,
        Fr,
        G1,
        toEvm
    }
}

async function makeProof({ Fr, G1, yG, xG, zG, R, yR, y, z, toEvm }, label) {
    const G = G1.g

    // DLEQ prove, yG/G == yR/R
    const t = Fr.random()
    const w1 = G1.timesFr(G, t)
    const w2 = G1.timesFr(R, t)

    const arr = [label].concat(toEvm(yG)).concat(toEvm(yR)).concat(toEvm(w1)).concat(toEvm(w2))
    const e = Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(arr.map(a => 'uint256'), arr)))
    const f = Fr.add(t, Fr.neg(Fr.mul(y, e)))

    // consumer will get e and f

    // w1 = f*G + yG * e
    const ww1 = G1.add(G1.timesFr(G, f), G1.timesFr(yG, e))
    // w2 = f*R + yR * e
    const ww2 = G1.add(G1.timesFr(R, f), G1.timesFr(yR, e))

    // should get the same w1 and w2
    // note: actually consumer doesn't know what original w1 and w2 were
    assert(G1.eq(w1, ww1))
    assert(G1.eq(w2, ww2))

    const arr2 = [label].concat(toEvm(yG)).concat(toEvm(yR)).concat(toEvm(ww1)).concat(toEvm(ww2))
    const chal = Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(arr2.map(a => 'uint256'), arr2)))
    assert(Fr.eq(chal, e))

    return {
        proof: [Fr.toObject(e), Fr.toObject(f)],
        cipher: 0
    }
}

module.exports = {
    setupEG,
    makeProof,
    frostDLEQ
}
