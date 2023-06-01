const express = require("express")
const bodyParser = require("body-parser")
const { JSONRPCServer, JSONRPCClient } = require("json-rpc-2.0")
const { buildBn128 } = require('ffjavascript')
const { ethers, BigNumber } = require('ethers')
const fetch = require('cross-fetch')
const assert = require('assert')

function flatten(lst) {
    return lst.reduce((a, b) => a.concat(b), [])
}

let addresses = [
    "http://localhost:23451",
    "http://localhost:23452",
    "http://localhost:23453",
    "http://localhost:23454",
    "http://localhost:23455",
]

async function makeServer(n, t, i, port) {

    // each address will have it's own client
    function makeClient(addr) {
        const client = new JSONRPCClient((jsonRPCRequest) =>
            fetch(`${addr}/json-rpc`, {
                method: "POST",
                headers: {
                "content-type": "application/json",
                },
                body: JSON.stringify(jsonRPCRequest),
            }).then((response) => {
                if (response.status === 200) {
                // Use client.receive when you received a JSON-RPC response.
                return response
                    .json()
                    .then((jsonRPCResponse) => client.receive(jsonRPCResponse));
                } else if (jsonRPCRequest.id !== undefined) {
                    return Promise.reject(new Error(response.statusText));
                }
        }))
        return client
    }
    let clients = addresses.map(makeClient)

    // crypto utils
    const ffCurve = await buildBn128()
    const Fr = ffCurve.Fr
    const G1 = ffCurve.G1
    const G = G1.g

    function hash(lst) {
        return Fr.fromObject(BigInt(ethers.utils.solidityKeccak256(lst.map(a => 'uint256'), lst)))
    }

    function toEvm(p) {
        const obj = G1.toObject(G1.toAffine(p))
        return [obj[0].toString(10), obj[1].toString(10)]
    }

    function fromEvm(arr) {
        return G1.fromObject([BigInt(arr[0]),BigInt(arr[1])])
    }

    function toString(n) {
        return Fr.toObject(n).toString(10)
    }

    function fromString(n) {
        return Fr.fromObject(BigInt(n))
    }

    function evalPoly(poly, x) {
        let xn = Fr.fromObject(1n)
        let res = Fr.fromObject(0n)
        for (const c of poly) {
            res = Fr.add(res, Fr.mul(c, xn))
            xn = Fr.mul(xn, Fr.fromObject(x))
        }
        return res
    }

    function sum(lst) {
        return lst.reduce((a, b) => Fr.add(a, b), Fr.fromObject(0n))
    }

    function sumG1(lst) {
        return lst.reduce((a, b) => G1.add(a, b), G1.fromObject([0n, 0n]))
    }

    function pow(a, n) {
        let res = Fr.fromObject(1n)
        for (let i = 0; i < n; i++) {
            res = Fr.mul(res, a)
        }
        return res
    } 

    // lagrange coefficient
    function coeff(ids, i) {
        let res = Fr.fromObject(1n)
        for (const id of ids) {
            if (id === i) continue
            const idneg = Fr.neg(Fr.fromObject(id + 1))
            res = Fr.mul(res, Fr.div(idneg, Fr.add(Fr.fromObject(i + 1), idneg)))
        }
        return res
    }

    let obj = {
        idx: i,
        used: {},
        shares: [],
    }

    // methods needed for DKG
    async function init_round1(params) {
        let ctx = BigInt(params.ctx)
        if (obj.used[ctx]) {
            return {error: "Context label used"}
        }
        obj.used[ctx] = true
        console.log("Initializing round 1")

        // generate secrets
        const poly = Array(t).fill().map(_a => Fr.random())
    
        // proof of knowledge for the secret (Schnorr sig)
        const k = Fr.random()
    
        const R = G1.timesFr(G, k)
        const a0G = G1.timesFr(G, poly[0])
        const c = hash([i,ctx].concat(toEvm(a0G)).concat(toEvm(R)))

        const mu = Fr.add(k, Fr.mul(poly[0], c))
    
        const phi = poly.map(a => G1.timesFr(G, a))

        obj.proof_mu = toString(mu)
        obj.proof_R = toEvm(R)
        obj.commit = phi.map(a => toEvm(a))
        obj.secrets = poly.map(a => Fr.toObject(a))
        obj.ctx = ctx

        // return commitments and proof
        let resp = {
            proof_mu: obj.proof_mu,
            proof_R: obj.proof_R,
            commit: obj.commit,
            idx: obj.idx,
            ctx: obj.ctx.toString(),
        }

        for (let c of clients) {
            await c.request("validate_round1", resp)
        }

        return "ok"
    }

    let objs = []
    objs[i] = obj

    // validate message received from round 1
    async function validate_round1(obj) {
        // console.log(obj)
        const c = hash([BigInt(obj.idx),BigInt(obj.ctx)].concat(obj.commit[0]).concat(obj.proof_R))
    
        const R = fromEvm(obj.proof_R)
        const mu = fromString(obj.proof_mu)
        const phi0 = fromEvm(obj.commit[0])
    
        const check = G1.add(G1.timesFr(G, mu), G1.timesFr(phi0, Fr.neg(c)))
    
        assert(G1.eq(R, check))
        console.log(i, "got valid round 1 message", obj.idx)
        objs[obj.idx] = obj
        return "ok"
    }

    async function coordinate_round1({ctx}) {
        for (let c of clients) {
            await c.request("init_round1", {ctx})
        }

        return "ok"
    }

    function computeKey(commits) {
        let pubkey = sumG1(commits.map(a => fromEvm(a[0])))
    
        console.log("got public key", toEvm(pubkey))
    
        return toEvm(pubkey)
    }   

    async function makeShares({commits}) {
        obj.commits = commits
        const poly = obj.secrets.map(a => fromString(a))
    
        let shares = []
        for (let i = 1; i <= n; i++) {
            let share = evalPoly(poly, i)
            shares.push(toString(share))
        }

        console.log("share", shares)
        obj.backup = shares
        for (let i = 0; i < clients.length; i++) {
            let c = clients[i]
            await c.request("set_share", {idx: obj.idx, share: shares[i]})
        }

        return "ok"
    }

    async function verifyShares() {
    
        const n = obj.shares.length
        const t = obj.secrets.length
    
        const idx = Fr.fromObject(BigInt(obj.idx+1))
    
        let secret = Fr.fromObject(0n)
    
        for (let l = 0; l < n; l++) {
            let share = fromString(obj.shares[l])
            let pub = G1.timesFr(G, share)
            let asd = []
            for (let k = 0; k < t; k++) {
                let cp = fromEvm(obj.commits[l][k])
                let exp = pow(idx, k)
                // console.log("exp",Fr.toObject(exp))
                asd.push(G1.timesFr(cp, exp))
            }
            let check = sumG1(asd)
            // console.log("check", toEvm(check), "pub", toEvm(pub), obj.idx, n, t)
            assert(G1.eq(check, pub))
            secret = Fr.add(share, secret)
        }
        console.log("found share", Fr.toObject(secret))
    
        obj.share = toString(secret)
        obj.pubkey = computeKey(obj.commits)
    }

    async function setShare(dta) {
        obj.shares[dta.idx] = dta.share
        console.log("Member", obj.idx, "got share from", dta.idx)
        let flag = true
        for (let i = 0; i < n; i++) {
            if (!obj.shares[i]) flag = false
        }
        if (flag) {
            verifyShares()
        }
        return "ok"
    }

    async function coordinate_round2({}) {
        // send commits
        let commits = []
        for (let i = 0; i < n; i++) {
            if (!objs[i] || !objs[i].commit) {
                console.log("Round 2 not finished: did not receive all commits", i)
            }
            commits.push(objs[i].commit)
        }
        computeKey(commits)

        for (let c of clients) {
            await c.request("make_shares", {commits})
        }

        return "ok"
    }

    async function crypt(dta) {
        let R = fromEvm(dta.key)
        let res = G1.timesFr(R, fromString(obj.share))
        return toEvm(res)
    }

    async function frost_round1(dta) {
        let R = fromEvm(dta.key)
        const s1 = Fr.random()
        const s2 = Fr.random()
        const c1 = G1.timesFr(G, s1)
        const c2 = G1.timesFr(G, s2)
        const c3 = G1.timesFr(R, s1)
        const c4 = G1.timesFr(R, s2)
        const pub1 = G1.timesFr(G, fromString(obj.share))
        const pub2 = G1.timesFr(R, fromString(obj.share))
        if (obj.s1) {
            console.log("overriding secret!!!!!!!!!!!!!!!")
        }
        obj.s1 = toString(s1)
        obj.s2 = toString(s2)
        return {
            c1: toEvm(c1),
            c2: toEvm(c2),
            c3: toEvm(c3),
            c4: toEvm(c4),
            pub1: toEvm(pub1),
            pub2: toEvm(pub2),
            // TODO: remove these
            s1: toString(s1),
            s2: toString(s2),
        }
    }

    function computeChallenge(nonces, label, yG, yR) {
        // compute binding values
        nonces.forEach(a => {
            a.bind = hash([a.idx, label].concat(flatten(nonces.map(({ c1, c2, c3, c4 }) => [].concat(c1).concat(c2).concat(c3).concat(c4)))))
            a.commit1 = G1.add(fromEvm(a.c1), G1.timesFr(fromEvm(a.c2), a.bind))
            a.commit2 = G1.add(fromEvm(a.c3), G1.timesFr(fromEvm(a.c4), a.bind))
        })

        // compute group commitment
        const rCommit1 = sumG1(nonces.map(a => a.commit1))
        console.log('group commitment1', toEvm(rCommit1))
        const rCommit2 = sumG1(nonces.map(a => a.commit2))
        console.log('group commitment2', toEvm(rCommit2))

        // compute challenge
        const chal = hash([label].concat(yG).concat(yR).concat(toEvm(rCommit1)).concat(toEvm(rCommit2)))
        console.log('challenge', Fr.toObject(chal))

        return chal

    }

    async function frost_round2(dta) {
        let nonces = dta.nonces

        const chal = computeChallenge(nonces, dta.label, dta.yG, dta.yR)

        // compute response
        let a = nonces.find(a => a.idx == obj.idx)
        // let num = nonces.findIndex(a => a.idx == obj.idx)
        let s1 = fromString(obj.s1)
        let s2 = fromString(obj.s2)
        let share = fromString(obj.share)
        console.log("coeff", obj.idx, ":", toString(coeff(dta.ids, obj.idx)))
        let resp = Fr.add(s1, Fr.add(Fr.mul(s2, a.bind), Fr.neg(Fr.mul(coeff(dta.ids, obj.idx), Fr.mul(share, chal)))))
        console.log('response', toString(resp))
        return toString(resp)
    }

    async function reencrypt(dta) {
        let ids = dta.ids
        
        const coeffs = ids.map(i => coeff(ids, i))
        console.log('coeffs', coeffs.map(a => Fr.toObject(a)))

        // network id
        let yG = G1.fromObject([BigInt(obj.pubkey[0]),BigInt(obj.pubkey[1])])

        // secret id
        let xG = G1.fromObject([BigInt(dta.id[0]),BigInt(dta.id[1])])

        // consumer id
        let zG = G1.fromObject([BigInt(dta.consumer[0]),BigInt(dta.consumer[1])])

        // reencrypt target
        const R = G1.add(xG, zG)
        console.log("R", toEvm(R))

        let parts = await Promise.all(coeffs.map(async (c,i) => G1.timesFr(fromEvm(await clients[ids[i]].request("crypt", {key: toEvm(R)})), c)))
        let yR = sumG1(parts)

        console.log("yR", toEvm(yR), "yG", toEvm(yG))

        // frost round 1 (pre-process)
        let nonces = await Promise.all(ids.map(async (idx, i) => {
            let nonce = await clients[idx].request("frost_round1", {key: toEvm(R)})
            nonce.idx = idx
            nonce.coeff = coeffs[i]
            return nonce
        }))

        console.log("frost round 1")
        console.log(JSON.stringify(nonces))

        // collect round 2 responses
        for (let a of nonces) {
            let req = {
                ids,
                key: toEvm(R),
                nonces,
                label: dta.label,
                yG: toEvm(yG),
                yR: toEvm(yR),
            }
            a.resp = await clients[a.idx].request("frost_round2", req)
        }

        // aggregating signatures
        const chal = computeChallenge(nonces, dta.label, toEvm(yG), toEvm(yR))

        console.log("frost round 2")
        // verify partial signatures
        nonces.forEach(a => {
            const resp1 = G1.timesFr(G, fromString(a.resp))
            const resp2 = G1.timesFr(R, fromString(a.resp))
            let pub1 = fromEvm(a.pub1)
            let pub2 = fromEvm(a.pub2)
            const committedResp1 = G1.add(a.commit1, G1.neg(G1.timesFr(pub1, Fr.mul(chal, a.coeff))))
            const committedResp2 = G1.add(a.commit2, G1.neg(G1.timesFr(pub2, Fr.mul(chal, a.coeff))))
            console.log('resp1', toEvm(resp1), 'should be', toEvm(committedResp1))
            console.log('resp2', toEvm(resp2), 'should be', toEvm(committedResp2))
        })

        const rResp = sum(nonces.map(a => fromString(a.resp)))
        console.log('group response', Fr.toObject(rResp))

        // verify DLEQ
        const check1 = G1.add(G1.timesFr(G, rResp), G1.timesFr(yG, chal))
        console.log('checking DLEQ', toEvm(check1))
        const check2 = G1.add(G1.timesFr(R, rResp), G1.timesFr(yR, chal))
        console.log('checking DLEQ', toEvm(check2))

        const chalV = hash([dta.label].concat(toEvm(yG)).concat(toEvm(yR)).concat(toEvm(check1)).concat(toEvm(check2)))
        console.log('challenge', Fr.toObject(chalV))

        return {
            R: toEvm(R),
            yR: toEvm(yR),
            response: toString(rResp),
            chal: toString(chal),
        }

    }

    const server = new JSONRPCServer()

    server.addMethod("echo", ({ text }) => text)
    server.addMethod("log", ({ message }) => console.log(message))

    server.addMethod("init_round1", init_round1)
    server.addMethod("validate_round1", validate_round1)
    server.addMethod("coordinate_round1", coordinate_round1)
    server.addMethod("make_shares", makeShares)
    server.addMethod("set_share", setShare)
    server.addMethod("coordinate_round2", coordinate_round2)

    server.addMethod("reencrypt", reencrypt)
    server.addMethod("crypt", crypt)
    server.addMethod("frost_round1", frost_round1)
    server.addMethod("frost_round2", frost_round2)

    server.addMethod("test_account", () => {
        const x = Fr.random()
        const xG = G1.timesFr(G, x)
        return {
            secret: toString(x),
            public: toEvm(xG),
        }
    })

    /*
    server.addMethod("test_share", () => {
        return obj.share
    })
    */

    const app = express()
    app.use(bodyParser.json())

    app.post("/json-rpc", (req, res) => {
        const jsonRPCRequest = req.body;
        // server.receive takes a JSON-RPC request and returns a promise of a JSON-RPC response.
        // It can also receive an array of requests, in which case it may return an array of responses.
        // Alternatively, you can use server.receiveJSON, which takes JSON string as is (in this case req.body).
        server.receive(jsonRPCRequest).then((jsonRPCResponse) => {
            if (jsonRPCResponse) {
                res.json(jsonRPCResponse);
            } else {
                // If response is absent, it was a JSON-RPC notification method.
                // Respond with no content status (204).
                res.sendStatus(204);
            }
        })
    })

    app.listen(port)
    console.log("running at port", port)
}

makeServer(5, 3, 0, 23451)
makeServer(5, 3, 1, 23452)
makeServer(5, 3, 2, 23453)
makeServer(5, 3, 3, 23454)
makeServer(5, 3, 4, 23455)
