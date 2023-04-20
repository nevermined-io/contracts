/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const { makeProof, setupEG } = require('../../helpers/dleq')
const deployManagers = require('../../helpers/deployManagers.js')
const testUtils = require('../../helpers/utils.js')

const AccessCondition = artifacts.require('AccessDLEQCondition')

async function setup({ accounts }) {
    const {
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager
    } = await deployManagers(
        accounts[8],
        accounts[0]
    )
    const accessCondition = await AccessCondition.new()

    await accessCondition.methods['initialize(address,address,address)'](
        accounts[0],
        conditionStoreManager.address,
        agreementStoreManager.address,
        { from: accounts[0] }
    )
    const didSeed = constants.bytes32.one
    const checksum = testUtils.generateId()
    const value = constants.registry.url
    const did = await didRegistry.hashDID(didSeed, accounts[0])
    await didRegistry.registerAttribute(didSeed, checksum, [accounts[9]], value, { from: accounts[0] })

    return {
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        accessCondition,
        did
    }
}

contract('AccessDLEQCondition', (accounts) => {
    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            await setup({ accounts })
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if condition does not exist', async () => {
            const {
                accessCondition
            } = await setup({ accounts })

            const agreementId = constants.bytes32.one

            const info = await setupEG()
            const { secretId, provider, buyer, reencrypt } = info
            const label = constants.bytes32.one
            const { proof, cipher } = await makeProof(info, label)

            await assert.isRejected(
                accessCondition.fulfill(agreementId, cipher, secretId, provider, buyer, reencrypt, proof),
                'Proof failed'
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if condition exist', async () => {
            const {
                agreementStoreManager,
                conditionStoreManager,
                templateStoreManager,
                accessCondition,
                did
            } = await setup({ accounts: accounts })

            const agreementId = constants.bytes32.one

            const templateId = accounts[2]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const info = await setupEG()
            const { secretId, provider, buyer, reencrypt } = info
            const cipher = 1234n

            const hashValues = await accessCondition.hashValues(cipher, secretId, provider, buyer)
            const conditionId = await accessCondition.generateId(agreementId, hashValues)

            const agreement = {
                did,
                conditionTypes: [accessCondition.address],
                conditionIds: [hashValues],
                timeLocks: [0],
                timeOuts: [2]
            }

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            const { proof } = await makeProof(info, conditionId)

            const result = await accessCondition.fulfill(agreementId, cipher, secretId, provider, buyer, reencrypt, proof)

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
        })
    })
})
