/* eslint-env mocha */
/* global artifacts, web3, contract, describe, it, beforeEach */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const testUtils = require('../helpers/utils.js')

function confirmUpgrade() {}

const {
    deploy,
    upgrade
} = require('./Upgrader')

const DIDRegistry = artifacts.require('DIDRegistry')

const DIDRegistryChangeFunctionSignature = artifacts.require('DIDRegistryChangeFunctionSignature')
const DIDRegistryChangeInStorage = artifacts.require('DIDRegistryChangeInStorage')
const DIDRegistryChangeInStorageAndLogic = artifacts.require('DIDRegistryChangeInStorageAndLogic')
const DIDRegistryExtraFunctionality = artifacts.require('DIDRegistryExtraFunctionality')
const DIDRegistryWithBug = artifacts.require('DIDRegistryWithBug')

contract('DIDRegistry', (accounts) => {
    let DIDRegistryProxyAddress

    // define the roles
    const didOwner = accounts[5]
    const approver = accounts[2]

    const verbose = true

    async function setupTest({
        didSeed = testUtils.generateId(),
        checksum = testUtils.generateId(),
        value = 'https://nevermined.io/did/test.txt'
    } = {}) {
        const DIDRegistryInstance = await DIDRegistry.at(DIDRegistryProxyAddress)
        const did = await DIDRegistryInstance.hashDID(didSeed, didOwner)
        const result = await DIDRegistryInstance.registerAttribute(
            didSeed, checksum, [], value,
            { from: didOwner }
        )
        // some quick checks

        testUtils.assertEmitted(result, 1, 'DIDAttributeRegistered')

        const payload = result.logs[0].args

        assert.strictEqual(did, payload._did)
        assert.strictEqual(didOwner, payload._owner)
        assert.strictEqual(checksum, payload._checksum)
        assert.strictEqual(value, payload._value)

        return { did, didSeed, checksum, value }
    }

    describe('Test upgradability for DIDRegistry [ @skip-on-coverage ]', () => {
        beforeEach('Load wallet each time', async () => {
            const addressBook = await deploy({
                web3,
                artifacts,
                contracts: ['DIDRegistry'],
                verbose
            })

            DIDRegistryProxyAddress = addressBook.DIDRegistry
            assert(DIDRegistryProxyAddress)
        })

        it('Should be possible to fix/add a bug', async () => {
            const { did } = await setupTest()

            // Upgrade to new version
            const taskBook = await upgrade({
                web3,
                contracts: ['DIDRegistryWithBug:DIDRegistry'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.DIDRegistry,
                approver,
                verbose
            )

            const DIDRegistryWithBugInstance =
                await DIDRegistryWithBug.at(DIDRegistryProxyAddress)

            assert.strictEqual(
                await DIDRegistryWithBugInstance.getDIDOwner(did),
                didOwner
            )

            // check functionality works
            const newDidSeed = testUtils.generateId()
            const newDid = await DIDRegistryWithBugInstance.hashDID(newDidSeed, didOwner)
            const newChecksum = testUtils.generateId()
            const newValue = 'https://example.com/newdid/ocean/test.txt'
            const result = await DIDRegistryWithBugInstance.registerAttribute(
                newChecksum, newDidSeed, [], newValue,
                { from: didOwner }
            )

            testUtils.assertEmitted(result, 1, 'DIDAttributeRegistered')

            const payload = result.logs[0].args
            assert.strictEqual(newDid, payload._did, 'did is not as expected')
            assert.strictEqual(didOwner, payload._owner, 'owner is not as expected')
            assert.strictEqual(newChecksum, payload._checksum)
            assert.strictEqual(newValue, payload._value)

            // test for bug
            assert.equal(
                (await DIDRegistryWithBugInstance.getBlockNumberUpdated(newDid)).toNumber(), 42,
                'getUpdatedAt value is not 42 (according to bug)')
        })

        it('Should be possible to change function signature', async () => {
            await setupTest()

            // Upgrade to new version
            const taskBook = await upgrade({
                web3,
                contracts: ['DIDRegistryChangeFunctionSignature:DIDRegistry'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.DIDRegistry,
                approver,
                verbose
            )

            const DIDRegistryChangeFunctionSignatureInstance =
                            await DIDRegistryChangeFunctionSignature.at(DIDRegistryProxyAddress)

            // check functionality works

            const newChecksum = testUtils.generateId()
            const newDidSeed = testUtils.generateId()
            const newDid = await DIDRegistryChangeFunctionSignatureInstance.hashDID(newDidSeed, didOwner)
            const newValue = 'https://example.com/newdid/test.txt'

            // act
            const result = await DIDRegistryChangeFunctionSignatureInstance.registerAttribute(
                newDidSeed, [], newChecksum, newValue,
                { from: didOwner }
            )

            // eval
            testUtils.assertEmitted(result, 1, 'DIDAttributeRegistered')

            const payload = result.logs[0].args

            assert.strictEqual(payload._did, newDid, 'DID did not match')
            assert.strictEqual(payload._owner, didOwner, 'owner did not match')
            assert.strictEqual(payload._checksum, newChecksum, 'checksum did not match')
            assert.strictEqual(payload._value, newValue, 'value did not match')
        })

        it('Should be possible to append storage variables ', async () => {
            const { did } = await setupTest()

            const DIDRegistryChangeInStorageInstance =
                            await DIDRegistryChangeInStorage.at(DIDRegistryProxyAddress)

            // should not be able to be called before upgrade is approved
            await assert.isRejected(DIDRegistryChangeInStorageInstance.timeOfRegister(did))

            // Upgrade to new version
            const taskBook = await upgrade({
                web3,
                contracts: ['DIDRegistryChangeInStorage:DIDRegistry'],
                verbose
            })

            // call again after approved
            await confirmUpgrade(
                web3,
                taskBook.DIDRegistry,
                approver,
                verbose
            )

            assert.equal(
                (await DIDRegistryChangeInStorageInstance.timeOfRegister(did)).toNumber(), 0,
                'Error calling added storage variable')
        })

        it('Should be possible to append storage variables and change logic', async () => {
            const { did } = await setupTest()

            const DIDRegistryChangeInStorageAndLogicInstance =
                            await DIDRegistryChangeInStorageAndLogic.at(DIDRegistryProxyAddress)

            // should not be able to be called before upgrade is approved
            await assert.isRejected(DIDRegistryChangeInStorageAndLogicInstance.timeOfRegister(did))

            // Upgrade to new version
            const taskBook = await upgrade({
                web3,
                contracts: ['DIDRegistryChangeInStorageAndLogic:DIDRegistry'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.DIDRegistry,
                approver,
                verbose
            )

            // Approve and call again
            assert.equal(
                (await DIDRegistryChangeInStorageAndLogicInstance.timeOfRegister(did)).toNumber(),
                0, 'Error calling added storage variable'
            )

            // check functionality works
            const didSeed = testUtils.generateId()
            const newDid = await DIDRegistryChangeInStorageAndLogicInstance.hashDID(didSeed, didOwner)

            const newChecksum = testUtils.generateId()
            const newValue = 'https://example.com/newdid/test.txt'

            // act
            const result = await DIDRegistryChangeInStorageAndLogicInstance.registerAttribute(
                didSeed, [], newChecksum, newValue,
                { from: didOwner }
            )

            // eval
            testUtils.assertEmitted(result, 1, 'DIDAttributeRegistered')

            const payload = result.logs[0].args

            assert.strictEqual(newDid, payload._did)
            assert.strictEqual(didOwner, payload._owner)
            assert.strictEqual(newChecksum, payload._checksum)
            assert.strictEqual(newValue, payload._value)

            assert.equal(
                (await DIDRegistryChangeInStorageAndLogicInstance.timeOfRegister(did)).toNumber(), 0,
                'Error calling added storage variable')
        })

        it('Should be able to call new method added after upgrade is approved', async () => {
            await setupTest()

            const DIDRegistryExtraFunctionalityInstance =
                            await DIDRegistryExtraFunctionality.at(DIDRegistryProxyAddress)

            // should not be able to be called before upgrade is approved
            await assert.isRejected(DIDRegistryExtraFunctionalityInstance.getNumber())

            // Upgrade to new version
            const taskBook = await upgrade({
                web3,
                contracts: ['DIDRegistryExtraFunctionality:DIDRegistry'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.DIDRegistry,
                approver,
                verbose
            )

            // Approve and call again
            assert.equal((await DIDRegistryExtraFunctionalityInstance.getNumber()).toNumber(),
                42, 'Error calling getNumber')
        })
    })
})
