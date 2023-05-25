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

async function computeKey(commits) {
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

    let pubkey = sumG1(commits.map(a => G1.fromObject([BigInt(a[0][0]), BigInt(a[0][1])])))

    console.log("got public key", toEvm(pubkey))

    return toEvm(pubkey)
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

    let secret = Fr.fromObject(0n)

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
        secret = Fr.add(share, secret)
    }
    console.log("found share", Fr.toObject(secret))

    obj.share = secret
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

    let pubkey = await computeKey(commits)

    return {
        shares: r1.map(a => a.share),
        pubkey,
    }
}

async function frostDLEQ(n, t) {
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr

    // generate secrets
    const { shares } = await proto(n,t,23782732837n)

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

    process.exit(0)
}

frostDLEQ(5, 3)

