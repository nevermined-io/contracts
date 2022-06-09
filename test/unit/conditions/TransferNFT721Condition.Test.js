/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const EpochLibrary = artifacts.require('EpochLibrary')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')
const NeverminedToken = artifacts.require('NeverminedToken')
const NeverminedConfig = artifacts.require('NeverminedConfig')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const TemplateStoreManager = artifacts.require('TemplateStoreManager')
const AgreementStoreManager = artifacts.require('AgreementStoreManager')
const TransferNFTCondition = artifacts.require('TransferNFT721Condition')
const LockPaymentCondition = artifacts.require('LockPaymentCondition')
const EscrowPaymentCondition = artifacts.require('EscrowPaymentCondition')
const ERC721 = artifacts.require('TestERC721')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('TransferNFT721 Condition constructor', (accounts) => {
    let owner
    let seller
    let buyer
    let other
    let provider

    const numberNFTs = 1 // NFTs
    const paymentAmounts = [10]
    let paymentReceivers

    let token,
        nft,
        didRegistry,
        templateStoreManager,
        agreementStoreManager,
        conditionStoreManager,
        lockPaymentCondition,
        escrowCondition,
        transferCondition

    before(async () => {
        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
        const didRegistryLibrary = await DIDRegistryLibrary.new()
        await DIDRegistry.link(didRegistryLibrary)
    })

    async function setupTest({
        conditionId = testUtils.generateId(),
        conditionType = constants.address.dummy,
        rewardAddress = testUtils.generateAccount().address,
        agreementId = testUtils.generateId(),
        didSeed = testUtils.generateId(),
        registerDID = false,
        DIDProvider = provider
    } = {}) {
        if (!transferCondition) {
            token = await NeverminedToken.new()
            await token.initialize(owner, owner)

            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, owner)

            nft = await ERC721.new()
            await nft.initialize()

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)

            conditionStoreManager = await ConditionStoreManager.new()

            templateStoreManager = await TemplateStoreManager.new()
            await templateStoreManager.initialize(
                owner,
                { from: owner }
            )

            agreementStoreManager = await AgreementStoreManager.new()
            await agreementStoreManager.methods['initialize(address,address,address,address)'](
                owner,
                conditionStoreManager.address,
                templateStoreManager.address,
                didRegistry.address
            )

            await conditionStoreManager.initialize(
                owner,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            lockPaymentCondition = await LockPaymentCondition.new()

            await lockPaymentCondition.initialize(
                owner,
                conditionStoreManager.address,
                didRegistry.address,
                { from: owner }
            )

            transferCondition = await TransferNFTCondition.new()

            await transferCondition.methods['initialize(address,address,address,address,address)'](
                owner,
                conditionStoreManager.address,
                didRegistry.address,
                nft.address,
                lockPaymentCondition.address
            )

            escrowCondition = await EscrowPaymentCondition.new()
            await escrowCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        }

        const did = await didRegistry.hashDID(didSeed, seller)

        if (registerDID) {
            await nft.mint(did, { from: seller })
            await nft.setApprovalForAll(transferCondition.address, true, { from: seller })
        }

        return {
            owner,
            rewardAddress,
            agreementId,
            did,
            conditionId,
            conditionType,
            DIDProvider,
            didRegistry,
            agreementStoreManager,
            templateStoreManager,
            conditionStoreManager,
            transferCondition,
            lockPaymentCondition,
            escrowCondition
        }
    }

    before(() => {
        ([, owner, seller, buyer, provider, , other] = accounts)

        paymentReceivers = [seller]
    })

    describe('init fail', () => {
        it('initialization fails if needed contracts are 0', async () => {
            const token = await NeverminedToken.new()
            await token.initialize(owner, owner)

            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, owner)

            const didRegistry = await DIDRegistry.new()
            didRegistry.initialize(owner, constants.address.zero, constants.address.zero)

            const conditionStoreManager = await ConditionStoreManager.new()

            const templateStoreManager = await TemplateStoreManager.new()
            await templateStoreManager.initialize(
                owner,
                { from: owner }
            )

            const agreementStoreManager = await AgreementStoreManager.new()
            await agreementStoreManager.methods['initialize(address,address,address,address)'](
                owner,
                conditionStoreManager.address,
                templateStoreManager.address,
                didRegistry.address
            )

            await conditionStoreManager.initialize(
                owner,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            const transferCondition = await TransferNFTCondition.new()

            await assert.isRejected(transferCondition.methods['initialize(address,address,address,address,address)'](
                owner,
                constants.address.zero,
                agreementStoreManager.address,
                constants.address.one
            ), undefined)
        })
    })

    describe('fulfill correctly', () => {
        it('should fulfill if condition exist', async () => {
            const {
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true })

            const hashValuesPayment = await lockPaymentCondition.hashValues(
                did, escrowCondition.address, token.address, paymentAmounts, paymentReceivers)
            const conditionIdPayment = await lockPaymentCondition.generateId(agreementId, hashValuesPayment)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionIdPayment,
                lockPaymentCondition.address,
                { from: owner }
            )

            await token.mint(buyer, 10, { from: owner })
            await token.approve(lockPaymentCondition.address, 10, { from: buyer })

            await lockPaymentCondition.fulfill(
                agreementId, did, escrowCondition.address, token.address, paymentAmounts, paymentReceivers,
                { from: buyer }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIdPayment)).toNumber(),
                constants.condition.state.fulfilled)

            const hashValues = await transferCondition.hashValues(
                did, seller, buyer, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            const result = await transferCondition.fulfill(
                agreementId, did, buyer, numberNFTs,
                conditionIdPayment, nft.address, true,
                { from: seller }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._did).to.equal(did)
            expect(eventArgs._receiver).to.equal(buyer)
            expect(eventArgs._amount.toNumber()).to.equal(numberNFTs)
        })

        it('anyone should be able to fulfill if condition exist', async () => {
            const {
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true })

            const hashValuesPayment = await lockPaymentCondition.hashValues(
                did, escrowCondition.address, token.address, paymentAmounts, paymentReceivers)
            const conditionIdPayment = await lockPaymentCondition.generateId(agreementId, hashValuesPayment)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionIdPayment,
                lockPaymentCondition.address,
                { from: owner }
            )

            await token.mint(buyer, 10, { from: owner })
            await token.approve(lockPaymentCondition.address, 10, { from: buyer })

            await lockPaymentCondition.fulfill(
                agreementId, did, escrowCondition.address, token.address, paymentAmounts, paymentReceivers,
                { from: buyer }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIdPayment)).toNumber(),
                constants.condition.state.fulfilled)

            const hashValues = await transferCondition.hashValues(
                did, other, buyer, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            await nft.safeTransferFrom(seller, other, did, { from: seller })
            await nft.setApprovalForAll(transferCondition.address, true, { from: other })
            const result = await transferCondition.fulfill(
                agreementId, did, buyer, numberNFTs,
                conditionIdPayment, nft.address, true,
                { from: other }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)
            testUtils.assertEmitted(result, 1, 'Fulfilled')
        })
    })

    describe('trying to fulfill invalid conditions', () => {
        it('should not fulfill if condition does not exist or account is invalid', async () => {
            const {
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true })

            const hashValuesPayment = await lockPaymentCondition.hashValues(
                did, buyer, token.address, paymentAmounts, paymentReceivers)
            const conditionIdPayment = await lockPaymentCondition.generateId(agreementId, hashValuesPayment)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionIdPayment,
                lockPaymentCondition.address,
                { from: owner }
            )

            await token.mint(buyer, 10, { from: owner })
            await token.approve(lockPaymentCondition.address, 10, { from: buyer })

            await lockPaymentCondition.fulfill(
                agreementId, did, buyer, token.address, paymentAmounts, paymentReceivers,
                { from: buyer }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIdPayment)).toNumber(),
                constants.condition.state.fulfilled)

            const hashValues = await transferCondition.hashValues(
                did, seller, buyer, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            // Invalid conditionId
            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, buyer, numberNFTs, testUtils.generateId(), nft.address, true, { from: seller }),
                /LockCondition needs to be Fulfilled/
            )

            // Invalid agreementID
            await assert.isRejected(
                transferCondition.fulfill(testUtils.generateId(), did, buyer, numberNFTs, conditionIdPayment, nft.address, true, { from: seller }),
                /Invalid UpdateRole/
            )
        })

        it('should not be able to fulfill the same condition twice if condition exist', async () => {
            const {
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true, rewardAddress: other })

            const hashValuesPayment = await lockPaymentCondition.hashValues(
                did, buyer, token.address, paymentAmounts, paymentReceivers)
            const conditionIdPayment = await lockPaymentCondition.generateId(agreementId, hashValuesPayment)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionIdPayment,
                lockPaymentCondition.address,
                { from: owner }
            )

            await token.mint(buyer, 10, { from: owner })
            await token.approve(lockPaymentCondition.address, 10, { from: buyer })

            await lockPaymentCondition.fulfill(
                agreementId, did, buyer, token.address, paymentAmounts, paymentReceivers,
                { from: buyer }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIdPayment)).toNumber(),
                constants.condition.state.fulfilled)

            const hashValues = await transferCondition.hashValues(
                did, seller, buyer, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            const result = await transferCondition.fulfill(
                agreementId, did, buyer, numberNFTs,
                conditionIdPayment, nft.address, true,
                { from: seller }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)
            testUtils.assertEmitted(result, 1, 'Fulfilled')

            await nft.safeTransferFrom(buyer, seller, did, { from: buyer })

            await assert.isRejected(
                transferCondition.fulfill(agreementId, did, buyer, numberNFTs,
                    conditionIdPayment, nft.address, true, { from: seller }),
                /Invalid state transition/
            )
        })
    })
})
