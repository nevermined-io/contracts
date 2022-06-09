/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')
const EpochLibrary = artifacts.require('EpochLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const SignCondition = artifacts.require('SignCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('SignCondition constructor', (accounts) => {
    const createRole = accounts[0]
    const owner = accounts[1]
    let conditionStoreManager
    let signCondition
    let nvmConfig

    before(async () => {
        nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, owner)
        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
    })

    async function setupTest({
        conditionId = constants.bytes32.one,
        conditionType = constants.address.dummy,
        createRole = accounts[0],
        owner = accounts[1]
    } = {}) {
        if (!signCondition) {
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: accounts[0] }
            )

            signCondition = await SignCondition.new()
            await signCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: accounts[0] }
            )
        }

        return { signCondition, conditionStoreManager, conditionId, conditionType, createRole, owner }
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            const conditionStoreManager = await ConditionStoreManager.new()
            const signCondition = await SignCondition.new()
            await signCondition.initialize(
                accounts[0],
                conditionStoreManager.address,
                { from: accounts[0] }
            )
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist for bytes32 message', async () => {
            const { signCondition } = await setupTest()

            const agreementId = constants.bytes32.one
            const {
                message,
                publicKey,
                signature
            } = constants.condition.sign.bytes32

            await assert.isRejected(
                signCondition.fulfill(agreementId, message, publicKey, signature, { from: accounts[2] }),
                constants.condition.state.error.conditionNeedsToBeUnfulfilled
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist for bytes32 message', async () => {
            const { signCondition, conditionStoreManager } = await setupTest()

            const agreementId = constants.bytes32.one
            const {
                message,
                publicKey,
                signature
            } = constants.condition.sign.bytes32

            const hashValues = await signCondition.hashValues(message, publicKey)
            const conditionId = await signCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                signCondition.address
            )

            await signCondition.fulfill(agreementId, message, publicKey, signature)

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(constants.condition.state.fulfilled, state.toNumber())
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('wrong signature should fail to fulfill if conditions exist for bytes32 message', async () => {
            //            const { signCondition, conditionStoreManager } = await setupTest()

            const agreementId = testUtils.generateId()
            const {
                message,
                publicKey
            } = constants.condition.sign.bytes32

            const hashValues = await signCondition.hashValues(message, publicKey)
            const conditionId = await signCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                signCondition.address
            )

            await assert.isRejected(
                signCondition.fulfill(
                    agreementId, message, publicKey,
                    agreementId
                )
            )
        })

        it('right signature should fail to fulfill if conditions already fulfilled for bytes32', async () => {
            //            const { signCondition, conditionStoreManager } = await setupTest()

            const agreementId = testUtils.generateId()
            const {
                message,
                publicKey,
                signature
            } = constants.condition.sign.bytes32

            const hashValues = await signCondition.hashValues(message, publicKey)
            const conditionId = await signCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                signCondition.address
            )

            // fulfill once
            await signCondition.fulfill(agreementId, message, publicKey, signature)
            // try to fulfill another time
            await assert.isRejected(
                signCondition.fulfill(agreementId, message, publicKey, signature),
                constants.condition.state.error.invalidStateTransition
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            //            const { signCondition, conditionStoreManager, createRole, owner } = await setupTest()

            const agreementId = testUtils.generateId()
            const {
                message,
                publicKey,
                signature
            } = constants.condition.sign.bytes32

            const hashValues = await signCondition.hashValues(message, publicKey)
            const conditionId = await signCondition.generateId(agreementId, hashValues)

            // create a condition of a type different than sign condition
            await conditionStoreManager.createCondition(
                conditionId,
                signCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            // try to fulfill from sign condition
            await assert.isRejected(
                signCondition.fulfill(agreementId, message, publicKey, signature),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
