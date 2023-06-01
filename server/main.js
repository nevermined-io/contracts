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
            idx: obj.idx.toString(),
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
        console.log(obj)
        const c = hash([BigInt(obj.idx),BigInt(obj.ctx)].concat(obj.commit[0]).concat(obj.proof_R))
    
        const R = G1.fromObject([BigInt(obj.proof_R[0]), BigInt(obj.proof_R[1])])
        const mu = fromString(obj.proof_mu)
        const phi0 = G1.fromObject([BigInt(obj.commit[0][0]), BigInt(obj.commit[0][1])])
    
        const check = G1.add(G1.timesFr(G, mu), G1.timesFr(phi0, Fr.neg(c)))
    
        assert(G1.eq(R, check))
        console.log("got valid round 1 message", obj)
        objs[obj.idx] = obj
        return "ok"
    }

    const server = new JSONRPCServer()

    server.addMethod("echo", ({ text }) => text)
    server.addMethod("log", ({ message }) => console.log(message))
    server.addMethod("init_round1", init_round1)
    server.addMethod("validate_round1", validate_round1)

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
makeServer(5, 3, 0, 23452)
makeServer(5, 3, 0, 23453)
makeServer(5, 3, 0, 23454)
makeServer(5, 3, 0, 23455)
