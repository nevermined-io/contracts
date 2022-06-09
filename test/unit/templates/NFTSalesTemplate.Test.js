/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NFTSalesTemplate = artifacts.require('NFTSalesTemplate')
const LockPaymentCondition = artifacts.require('LockPaymentCondition')
const TransferNFTCondition = artifacts.require('TransferNFTCondition')
const EscrowPayment = artifacts.require('EscrowPaymentCondition')

const constants = require('../../helpers/constants.js')
const deployManagers = require('../../helpers/deployManagers.js')
const testUtils = require('../../helpers/utils')

contract('NFTSalesTemplate', (accounts) => {
    let lockPaymentCondition,
        transferCondition,
        escrowCondition,
        token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager

    async function setupTest({
        deployer = accounts[8],
        owner = accounts[9]
    } = {}) {
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager
        } = await deployManagers(deployer, owner))

        lockPaymentCondition = await LockPaymentCondition.new()

        await lockPaymentCondition.initialize(
            owner,
            conditionStoreManager.address,
            didRegistry.address,
            { from: deployer }
        )

        transferCondition = await TransferNFTCondition.new({ from: deployer })

        await transferCondition.initialize(
            owner,
            conditionStoreManager.address,
            didRegistry.address,
            agreementStoreManager.address,
            owner,
            { from: deployer }
        )

        escrowCondition = await EscrowPayment.new()
        await escrowCondition.initialize(
            owner,
            conditionStoreManager.address,
            { from: deployer }
        )

        const nftSalesTemplate = await NFTSalesTemplate.new({ from: deployer })
        await nftSalesTemplate.methods['initialize(address,address,address,address,address)'](
            owner,
            agreementStoreManager.address,
            lockPaymentCondition.address,
            transferCondition.address,
            escrowCondition.address,
            { from: deployer }
        )

        return {
            token,
            escrowCondition,
            transferCondition,
            lockPaymentCondition,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            nftSalesTemplate,
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
        didSeed = testUtils.generateId()
    } = {}) {
        const did = await didRegistry.hashDID(didSeed, accounts[0])
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
            const {
                didRegistry,
                agreementStoreManager,
                conditionStoreManager,
                templateStoreManager,
                nftSalesTemplate,
                owner
            } = await setupTest()

            const { agreementId, agreement, didSeed } = await prepareAgreement()

            await assert.isRejected(
                nftSalesTemplate.createAgreement(agreementId, ...Object.values(agreement)),
                constants.template.error.templateNotApproved
            )

            // propose and approve template
            const templateId = nftSalesTemplate.address
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })

            await assert.isRejected(
                nftSalesTemplate.createAgreement(agreementId, ...Object.values(agreement)),
                constants.registry.error.didNotRegistered
            )

            // register DID
            await didRegistry.registerAttribute(didSeed, constants.bytes32.one, [], constants.registry.url)

            await nftSalesTemplate.createAgreement(agreementId, ...Object.values(agreement))

            const realAgreementId = await agreementStoreManager.agreementId(agreementId, accounts[0])

            const storedAgreementData = await nftSalesTemplate.getAgreementData(realAgreementId)
            assert.strictEqual(storedAgreementData.accessConsumer, agreement.accessConsumer)
            assert.strictEqual(storedAgreementData.accessProvider, accounts[0])

            const condIds = await testUtils.getAgreementConditionIds(nftSalesTemplate, realAgreementId)
            expect(condIds).to.deep.equal(agreement.conditionIds)

            let i = 0
            const conditionTypes = await nftSalesTemplate.getConditionTypes()
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

    describe('create agreement `AgreementCreated` event', () => {
        it('create agreement should emit `AgreementCreated` event', async () => {
            const {
                didRegistry,
                agreementStoreManager,
                templateStoreManager,
                nftSalesTemplate,
                owner
            } = await setupTest()

            const { agreementId, agreement, didSeed } = await prepareAgreement()
            const realAgreementId = await agreementStoreManager.agreementId(agreementId, accounts[0])

            // register DID
            await didRegistry.registerAttribute(didSeed, constants.bytes32.one, [], constants.registry.url)

            // propose and approve template
            const templateId = nftSalesTemplate.address
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })

            const result = await nftSalesTemplate.createAgreement(agreementId, ...Object.values(agreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            const eventArgs = testUtils.getEventArgsFromTx(result, 'AgreementCreated')
            expect(eventArgs._agreementId).to.equal(realAgreementId)
            expect(eventArgs._did).to.equal(agreement.did)
            // expect(eventArgs._accessProvider).to.equal(accounts[0])
            // expect(eventArgs._accessConsumer).to.equal(agreement.accessConsumer)

            /*
            const storedAgreement = await agreementStoreManager.getAgreement(agreementId)
            expect(storedAgreement.conditionIds)
                .to.deep.equal(agreement.conditionIds)
            expect(storedAgreement.lastUpdatedBy)
                .to.equal(templateId)
            */
        })
    })
})
