/* eslint-env mocha */
/* global artifacts, assert, web3 */

const { ethers, hardhatArguments } = require('hardhat')
const network = hardhatArguments.network || 'hardhat'
const deploying = network === 'hardhat' || network === 'coverage' || network === 'testing'
const constants = require('./constants')

const utils = {
    deploying,

    generateId: () => {
        return web3.utils.sha3(Math.random().toString())
    },

    sha3: (message) => {
        return web3.utils.sha3(message)
    },

    generateAccount: () => {
        return web3.eth.accounts.create()
    },

    assertEmitted: (result, n, name) => {
        let gotEvents = 0
        for (let i = 0; i < result.logs.length; i++) {
            const ev = result.logs[i]
            if (ev.event === name) {
                gotEvents++
            }
        }
        assert.strictEqual(n, gotEvents, `Event ${name} was not emitted.`)
    },

    getEventArgsFromTx: (txReceipt, eventName) => {
        return txReceipt.logs.filter((log) => {
            return log.event === eventName
        })[0].args
    },

    fixSignature: (signature) => {
        // in geth its always 27/28, in ganache its 0/1. Change to 27/28 to prevent
        // signature malleability if version is 0/1
        // see https://github.com/ethereum/go-ethereum/blob/v1.8.23/internal/ethapi/api.go#L465
        let v = parseInt(signature.slice(130, 132), 16)
        if (v < 27) {
            v += 27
        }
        const vHex = v.toString(16)
        return signature.slice(0, 130) + vHex
    },

    getAgreementConditionIds: async (template, agreementId) => {
        const evs = await template.getPastEvents('AgreementCreated', { fromBlock: 0, filter: { agreementId } })
        return evs.length > 0 ? evs[0].returnValues._conditionIdSeeds : []
    },

    toEthSignedMessageHash: (messageHex) => {
        const messageBuffer = Buffer.from(messageHex.substring(2), 'hex')
        const prefix = Buffer.from(`\u0019Ethereum Signed Message:\n${messageBuffer.length}`)
        return web3.utils.sha3(Buffer.concat([prefix, messageBuffer]))
    },

    deploy: async (name, args, deployer, libs = [], initMethod = 'initialize') => {
        if (deploying) {
            const afact = artifacts.require(name)
            for (const e of libs) {
                afact.link(e)
            }
            const c = await afact.new()
            await c[initMethod](...args, { from: deployer })
            return c
        } else {
            const afact = artifacts.require(name)
            // eslint-disable-next-line security/detect-non-literal-require
            const addr = require(`../../artifacts/${name}.external.json`).address
            return afact.at(addr)
        }
    },

    deployManagers: async (owner, createRole) => {
        const DIDRegistry = artifacts.require('DIDRegistry')
        const NeverminedConfig = artifacts.require('NeverminedConfig')
        const ConditionStoreManager = artifacts.require('ConditionStoreManager')
        const NFT = artifacts.require('NFT1155Upgradeable')
        const Royalties = artifacts.require('StandardRoyalties')

        const nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, owner, false)
        const royalties = await Royalties.new()
        const didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, nvmConfig.address, royalties.address)
        await royalties.initialize(didRegistry.address)
        const nft = await NFT.new()
        await nft.initialize(owner, didRegistry.address, 'NFT1155', 'NVM', '')
        const conditionStoreManager = await ConditionStoreManager.new()
        await conditionStoreManager.initialize(createRole, owner, nvmConfig.address, { from: owner })
        return {
            didRegistry,
            nvmConfig,
            conditionStoreManager,
            nft
        }
    },

    approveProxy: async (name, owner, nftAddress, contractAddress) => {
        const signer = await ethers.provider.getSigner(owner)
        const instance = await ethers.getContractAt(name, nftAddress, signer)
        await instance.grantOperatorRole(contractAddress, { gasLimit: 100000 })
    }

}

module.exports = utils
