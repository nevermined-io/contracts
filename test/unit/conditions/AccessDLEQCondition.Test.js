/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const { makeProof, setupEG } = require('../../helpers/dleq')
const deployManagers = require('../../helpers/deployManagers.js')
// const testUtils = require('../../helpers/utils.js')

const AccessCondition = artifacts.require('AccessDLEQCondition')

async function setup({accounts}) {

    let {
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

    // compute 

    return {
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        accessCondition,
    }
}

contract('AccessDLEQCondition', (accounts) => {
    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            await setup({accounts})
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if condition does not exist', async () => {
            const {
                accessCondition
            } = await setup({accounts})

            const agreementId = constants.bytes32.one

            const info = await setupEG()
            const { secretId, provider, buyer, reencrypt } = info
            const label = constants.bytes32.one
            const { proof, cipher } = await makeProof(info, label)
            // console.log(proof)

            await assert.isRejected(
                accessCondition.fulfill(agreementId, cipher, secretId, provider, buyer, reencrypt, proof),
                'Proof failed'
            )
        })
    })

    /*
    describe('fulfill existing condition', () => {
        it('should fulfill if condition exist', async () => {
            const {
                agreementStoreManager,
                conditionStoreManager,
                templateStoreManager,
                accessCondition

            } = await setup({ accounts: accounts })

            const agreementId = constants.bytes32.one
            const grantee = accounts[1]

            const templateId = accounts[2]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const hashValues = await accessCondition.hashValues(documentId, grantee)
            const conditionId = await accessCondition.generateId(agreementId, hashValues)

            const agreement = {
                did: did,
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

            const result = await accessCondition.fulfill(agreementId, documentId, grantee)

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._documentId).to.equal(documentId)
            expect(eventArgs._grantee).to.equal(grantee)
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('wrong did owner should fail to fulfill if conditions exist', async () => {
            const {
                did,
                agreementStoreManager,
                templateStoreManager,
                accessCondition

            } = await common.setupTest({ accounts: accounts, registerDID: true })

            const agreementId = constants.bytes32.one
            const documentId = did
            const grantee = accounts[1]

            const templateId = accounts[2]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const hashValues = await accessCondition.hashValues(documentId, grantee)

            const agreement = {
                did: did,
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

            await assert.isRejected(
                accessCondition.fulfill(agreementId, documentId, grantee, { from: accounts[1] }),
                'Invalid DID owner/provider'
            )
        })

        it('right did owner should fail to fulfill if conditions already fulfilled', async () => {
            const {
                did,
                agreementStoreManager,
                templateStoreManager,
                accessCondition

            } = await common.setupTest({ accounts: accounts, registerDID: true })

            const agreementId = constants.bytes32.one
            const documentId = did
            const grantee = accounts[1]

            const templateId = accounts[2]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId)

            const hashValues = await accessCondition.hashValues(documentId, grantee)

            const agreement = {
                did: did,
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

            await accessCondition.fulfill(agreementId, documentId, grantee)

            await assert.isRejected(
                accessCondition.fulfill(agreementId, documentId, grantee),
                constants.condition.state.error.invalidStateTransition
            )
        })
    })
    */

})
