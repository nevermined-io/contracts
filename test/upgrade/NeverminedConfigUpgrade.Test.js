/* eslint-env mocha */
/* global artifacts, web3, contract, describe, it, beforeEach */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../helpers/constants.js')

function confirmUpgrade() {}

const {
    deploy,
    upgrade
} = require('./Upgrader')

// const NeverminedConfig = artifacts.require('NeverminedConfig')

const NeverminedConfigWithBug = artifacts.require('NeverminedConfigWithBug')
const NeverminedConfigChangeFunctionSignature = artifacts.require('NeverminedConfigChangeFunctionSignature')
const NeverminedConfigChangeInStorage = artifacts.require('NeverminedConfigChangeInStorage')
const NeverminedConfigChangeInStorageAndLogic = artifacts.require('NeverminedConfigChangeInStorageAndLogic')

contract('NeverminedConfig', (accounts) => {
    let nvmConfigAddress

    const verbose = false

    const approver = accounts[2]
    const owner = accounts[8]

    beforeEach('Load wallet each time', async function() {
        const addressBook = await deploy({
            web3,
            artifacts,
            contracts: ['NeverminedConfig'],
            verbose
        })

        nvmConfigAddress = addressBook.NeverminedConfig
        assert(nvmConfigAddress)
    })

    describe('Test upgradability for NeverminedConfig [ @skip-on-coverage ]', () => {
        it('Should be possible to fix/add a bug', async () => {
            const taskBook = await upgrade({
                web3,
                contracts: ['NeverminedConfigWithBug:NeverminedConfig'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.NeverminedConfig,
                approver,
                verbose
            )

            const NeverminedConfigWithBugInstance =
                await NeverminedConfigWithBug.at(nvmConfigAddress)

            await NeverminedConfigWithBugInstance.setMarketplaceFees(100, constants.address.zero, { from: owner })
            // assert
            assert.strictEqual(
                await NeverminedConfigWithBugInstance.getFeeReceiver(),
                constants.address.zero,
                'address(0) can be configured according to the bug'
            )
        })

        it('Should be possible to change function signature', async () => {
            const taskBook = await upgrade({
                web3,
                contracts: ['NeverminedConfigChangeFunctionSignature:NeverminedConfig'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.NeverminedConfig,
                approver,
                verbose
            )

            const NeverminedConfigChangeFunctionSignatureInstance =
                await NeverminedConfigChangeFunctionSignature.at(nvmConfigAddress)

            await NeverminedConfigChangeFunctionSignatureInstance.setMarketplaceFees(100, accounts[0], 1, { from: owner })
            // assert
            assert.strictEqual(
                await NeverminedConfigChangeFunctionSignatureInstance.getFeeReceiver(),
                accounts[0],
                'new parameter was accepted'
            )
        })

        it('Should be possible to append storage variable(s) ', async () => {
            const taskBook = await upgrade({
                web3,
                contracts: ['NeverminedConfigChangeInStorage:NeverminedConfig'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.NeverminedConfig,
                approver,
                verbose
            )

            const NeverminedConfigChangeInStorageInstance =
                await NeverminedConfigChangeInStorage.at(nvmConfigAddress)

            assert.strictEqual(
                (await NeverminedConfigChangeInStorageInstance.newVariable()).toNumber(),
                0
            )
        })

        it('Should be possible to append storage variables and change logic', async () => {
            const taskBook = await upgrade({
                web3,
                contracts: ['NeverminedConfigChangeInStorageAndLogic:NeverminedConfig'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.NeverminedConfig,
                approver,
                verbose
            )

            const NeverminedConfigChangeInStorageAndLogicInstance =
                await NeverminedConfigChangeInStorageAndLogic.at(nvmConfigAddress)

            assert.strictEqual(
                (await NeverminedConfigChangeInStorageAndLogicInstance.newVariable()).toNumber(),
                0
            )

            await NeverminedConfigChangeInStorageAndLogicInstance.setMarketplaceFees(100, accounts[0], 1, { from: owner })
            // assert
            assert.strictEqual(
                await NeverminedConfigChangeInStorageAndLogicInstance.getFeeReceiver(),
                accounts[0],
                'new parameter was accepted'
            )
        })
    })
})
