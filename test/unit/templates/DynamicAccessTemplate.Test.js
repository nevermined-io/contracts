/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DynamicAccessTemplate = artifacts.require('DynamicAccessTemplate')
const AccessCondition = artifacts.require('AccessCondition')
const NFTHolderCondition = artifacts.require('NFTHolderCondition')
const EscrowPayment = artifacts.require('EscrowPaymentCondition')

const constants = require('../../helpers/constants.js')
const deployManagers = require('../../helpers/deployManagers.js')
const testUtils = require('../../helpers/utils')

contract('DynamicAccessTemplate', (accounts) => {
    let token
    let didRegistry
    let agreementStoreManager
    let conditionStoreManager
    let templateStoreManager
    let dynamicAccessTemplate
    let accessCondition
    let nftHolderCondition
    let escrowPayment
    const deployer = accounts[8]
    const owner = accounts[9]

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!dynamicAccessTemplate) {
            const deployment = await deployManagers(deployer, owner)
            token = deployment.token
            didRegistry = deployment.didRegistry
            agreementStoreManager = deployment.agreementStoreManager
            conditionStoreManager = deployment.conditionStoreManager
            templateStoreManager = deployment.templateStoreManager

            dynamicAccessTemplate = await DynamicAccessTemplate.new({ from: deployer })

            await dynamicAccessTemplate.methods['initialize(address,address,address)'](
                owner,
                agreementStoreManager.address,
                didRegistry.address,
                { from: deployer }
            )

            accessCondition = await AccessCondition.new()

            await accessCondition.methods['initialize(address,address,address)'](
                owner,
                conditionStoreManager.address,
                agreementStoreManager.address,
                { from: owner }
            )

            nftHolderCondition = await NFTHolderCondition.new()
            await nftHolderCondition.initialize(
                owner,
                conditionStoreManager.address,
                deployment.nft.address,
                { from: owner }
            )

            escrowPayment = await EscrowPayment.new()
            await escrowPayment.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        }

        return {
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            dynamicAccessTemplate,
            deployer,
            owner
        }
    }

    async function prepareAgreement({
        agreementId = testUtils.generateId(),
        conditionIds = [
            testUtils.generateId(),
            testUtils.generateId(),
            testUtils.generateId()
        ],
        timeLocks = [0, 0, 0],
        timeOuts = [0, 0, 0],
        sender = accounts[0],
        receiver = accounts[1],
        amount = 1,
        didSeed = constants.did[0]
    } = {}) {
        const did = await didRegistry.hashDID(didSeed, sender)
        // construct agreement
        const agreement = {
            did,
            conditionIds,
            timeLocks,
            timeOuts,
            accessConsumer: receiver
        }
        return {
            agreementId,
            agreement,
            didSeed
        }
    }

    describe('create agreement', () => {
        it('correct create should get data, agreement & conditions', async () => {
            const { agreementId, agreement, didSeed } = await prepareAgreement()

            await assert.isRejected(
                dynamicAccessTemplate.createAgreement(agreementId, ...Object.values(agreement)),
                constants.template.error.templateNotApproved
            )

            // propose and approve template
            const templateId = dynamicAccessTemplate.address
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })

            await assert.isRejected(
                dynamicAccessTemplate.createAgreement(agreementId, ...Object.values(agreement)),
                constants.registry.error.didNotRegistered
            )

            // register DID
            await didRegistry.registerAttribute(didSeed, constants.bytes32.one, [], constants.registry.url)

            await assert.isRejected(
                dynamicAccessTemplate.createAgreement(agreementId, ...Object.values(agreement)),
                'Arguments have wrong length'
            )

            await dynamicAccessTemplate.addTemplateCondition(accessCondition.address, { from: owner })
            await dynamicAccessTemplate.addTemplateCondition(nftHolderCondition.address, { from: owner })
            await dynamicAccessTemplate.addTemplateCondition(escrowPayment.address, { from: owner })
            const templateConditionTypes = await dynamicAccessTemplate.getConditionTypes()
            assert.strictEqual(3, templateConditionTypes.length)

            const result = await dynamicAccessTemplate.createAgreement(agreementId, ...Object.values(agreement))
            testUtils.assertEmitted(result, 1, 'AgreementCreated')
            const realAgreementId = await agreementStoreManager.agreementId(agreementId, accounts[0])

            const eventArgs = testUtils.getEventArgsFromTx(result, 'AgreementCreated')
            expect(eventArgs._agreementId).to.equal(realAgreementId)
            expect(eventArgs._did).to.equal(agreement.did)

            const condIds = await testUtils.getAgreementConditionIds(dynamicAccessTemplate, agreementId)
            expect(condIds).to.deep.equal(agreement.conditionIds)

            let i = 0
            const conditionTypes = await dynamicAccessTemplate.getConditionTypes()
            for (const conditionId of agreement.conditionIds) {
                const fullId = await agreementStoreManager.fullConditionId(realAgreementId, conditionTypes[i], conditionId)
                const storedCondition = await conditionStoreManager.getCondition(fullId)
                expect(storedCondition.typeRef).to.equal(conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
                expect(storedCondition.timeLock.toNumber()).to.equal(agreement.timeLocks[i])
                expect(storedCondition.timeOut.toNumber()).to.equal(agreement.timeOuts[i])
                i++
            }
        })
    })
})
