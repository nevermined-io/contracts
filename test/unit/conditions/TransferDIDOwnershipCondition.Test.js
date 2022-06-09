/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const deployManagers = require('../../helpers/deployManagers.js')
const TransferDIDOwnershipCondition = artifacts.require('TransferDIDOwnershipCondition')
const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('TransferDIDOwnership Condition constructor', (accounts) => {
    let didRegistry,
        templateStoreManager,
        agreementStoreManager,
        conditionStoreManager,
        transferCondition

    async function setupTest({
        accounts = [],
        conditionId = testUtils.generateId(),
        conditionType = constants.address.dummy,
        didSeed = testUtils.generateId(),
        checksum = testUtils.generateId(),
        value = constants.registry.url,
        deployer = accounts[8],
        owner = accounts[0],
        registerDID = false,
        DIDProvider = accounts[9]
    } = {}) {
        if (!transferCondition) {
            ({
                didRegistry,
                agreementStoreManager,
                conditionStoreManager,
                templateStoreManager
            } = await deployManagers(
                deployer,
                owner
            ))

            transferCondition = await TransferDIDOwnershipCondition.new({ from: deployer })

            await transferCondition.methods['initialize(address,address,address)'](
                owner,
                conditionStoreManager.address,
                didRegistry.address,
                { from: deployer }
            )

            await didRegistry.setManager(transferCondition.address, { from: owner })
        }

        const did = await didRegistry.hashDID(didSeed, owner)

        if (registerDID) {
            await didRegistry.registerAttribute(didSeed, checksum, [DIDProvider], value, { from: owner })
        }

        return {
            owner,
            did,
            conditionId,
            conditionType,
            DIDProvider,
            didRegistry,
            agreementStoreManager,
            templateStoreManager,
            conditionStoreManager,
            transferCondition
        }
    }

    describe('init fail', () => {
        it('initialization fails if needed contracts are 0', async () => {
            const deployer = accounts[8]
            const owner = accounts[0]
            const {
                agreementStoreManager
            } = await deployManagers(
                deployer,
                owner
            )

            const transferCondition = await TransferDIDOwnershipCondition.new({ from: deployer })

            await assert.isRejected(transferCondition.methods['initialize(address,address,address)'](
                owner,
                constants.address.zero,
                agreementStoreManager.address,
                { from: deployer }
            ), 'Invalid address')
        })
    })

    describe('trying to fulfill invalid conditions', () => {
        it('should not fulfill if condition does not exist', async () => {
            const {
                transferCondition
            } = await setupTest({ accounts: accounts })

            const agreementId = testUtils.generateId()
            const did = testUtils.generateId()
            const receiver = accounts[1]

            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, receiver, { from: receiver }),
                'Only owner'
            )
        })

        it('should not fulfill if condition does not exist', async () => {
            const {
                transferCondition
            } = await setupTest({ accounts: accounts })

            const agreementId = testUtils.generateId()
            const did = testUtils.generateId()
            const receiver = accounts[1]

            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, receiver),
                'Only owner'
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if condition exist', async () => {
            const {
                owner,
                did,
                agreementStoreManager,
                didRegistry,
                transferCondition,
                conditionStoreManager,
                templateStoreManager
            } = await setupTest({ accounts: accounts, registerDID: true })

            const agreementId = testUtils.generateId()
            const receiver = accounts[1]

            const templateId = accounts[6]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const hashValues = await transferCondition.hashValues(did, receiver)
            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            const agreement = {
                did: did,
                conditionTypes: [transferCondition.address],
                conditionIds: [hashValues],
                timeLocks: [0],
                timeOuts: [2]

            }

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, receiver, { from: receiver }),
                'Only owner'
            )

            const storedDIDRegister = await didRegistry.getDIDRegister(did)
            assert.strictEqual(
                storedDIDRegister.owner,
                owner
            )

            assert.strictEqual(didRegistry.address, await agreementStoreManager.getDIDRegistryAddress())
            const result = await transferCondition.fulfill(agreementId, did, receiver, { from: owner })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._did).to.equal(did)
            expect(eventArgs._receiver).to.equal(receiver)
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('wrong did owner should fail to fulfill if conditions exist', async () => {
            const {
                owner,
                did,
                agreementStoreManager,
                transferCondition,
                templateStoreManager
            } = await setupTest({ accounts: accounts, registerDID: true })

            const agreementId = testUtils.generateId()
            const receiver = accounts[1]

            const templateId = accounts[7]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const hashValues = await transferCondition.hashValues(did, receiver)

            const agreement = {
                did: did,
                conditionTypes: [transferCondition.address],
                conditionIds: [hashValues],
                timeLocks: [0],
                timeOuts: [2]

            }

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            await transferCondition.fulfill(agreementId, did, receiver, { from: owner })

            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, receiver, { from: accounts[1] })
            )
        })
    })
})
