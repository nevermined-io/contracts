
const assert = require('assert')
const { buildBn128 } = require('ffjavascript')
const { ethers } = require('ethers')

async function main() {
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
    console.log(xG, yG, zG)

    // re-encrypt the secret
    const R = G1.add(xG, zG)
    const yR = G1.timesFr(R, y)

    // consumer figures out the shared secret
    const R1 = G1.add(yR, G1.neg(G1.timesFr(yG, z)))
    assert(G1.eq(R1, xyG))

    // DLEQ prove, yG == yR
    const t = Fr.random()
    const w1 = G1.timesFr(G, t)
    const w2 = G1.timesFr(R, t)

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    // console.log(ethers.utils.solidityKeccak256(['uint256'], ['123']))
    // console.log(ethers.utils.solidityKeccak256([{x: 'uint256', y:'uint256'}], [{x: '123', y: '123'}]))
    const arr = toEvm(w1).concat(toEvm(w2)).concat(toEvm(G)).concat(toEvm(R))
    const e = Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(arr.map(a => 'uint256'), arr)))
    console.log('challenge', e)
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

    const chal = Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(arr.map(a => 'uint256'), arr)))
    assert(Fr.eq(chal, e))

    process.exit()
}

main()
