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
const TransferNFTCondition = artifacts.require('TransferNFTCondition')
const LockPaymentCondition = artifacts.require('LockPaymentCondition')
const EscrowPaymentCondition = artifacts.require('EscrowPaymentCondition')
const NFT = artifacts.require('NFTUpgradeable')
const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('TransferNFT Condition constructor', (accounts) => {
    let owner
    let seller
    let buyer
    let other
    let provider

    const numberNFTs = 2 // NFTs
    const mintCap = 100
    const paymentAmounts = [10]

    let paymentReceivers
    let token,
        didRegistry,
        templateStoreManager,
        agreementStoreManager,
        conditionStoreManager,
        lockPaymentCondition,
        escrowCondition,
        transferCondition,
        nft

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
        checksum = testUtils.generateId(),
        url = constants.registry.url,
        registerDID = false,
        mintDID = true,
        DIDProvider = provider
    } = {}) {
        if (!transferCondition) {
            token = await NeverminedToken.new()
            await token.initialize(owner, owner)

            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, owner)

            nft = await NFT.new()
            await nft.initialize('')

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, nft.address, constants.address.zero)

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

            transferCondition = await TransferNFTCondition.new()

            await transferCondition.methods['initialize(address,address,address,address,address)'](
                owner,
                conditionStoreManager.address,
                didRegistry.address,
                nft.address,
                owner
            )

            lockPaymentCondition = await LockPaymentCondition.new()

            await lockPaymentCondition.initialize(
                owner,
                conditionStoreManager.address,
                didRegistry.address,
                { from: owner }
            )

            escrowCondition = await EscrowPaymentCondition.new()
            await escrowCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )

            // We allow DIDRegistry and TransferCondition to mint NFTs
            await nft.addMinter(didRegistry.address)
            await nft.addMinter(transferCondition.address)

            // IMPORTANT: Here we give ERC1155 transfer grants to the TransferNFTCondition condition
            // await didRegistry.setProxyApproval(transferCondition.address, true, { from: owner })
        }

        const did = await didRegistry.hashDID(didSeed, seller)

        if (registerDID) {
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, mintCap, 0, constants.activities.GENERATED, '',
                { from: seller }
            )
            if (mintDID) {
                await didRegistry.mint(did, mintCap, { from: seller })
                await nft.safeTransferFrom(seller, other, did, 10, [], { from: seller })
            }
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
                didRegistry.address,
                agreementStoreManager.address,
                owner
            ), undefined)
        })
    })

    describe('fulfill correctly', () => {
        it('should fulfill if condition exist', async () => {
            const {
                rewardAddress,
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

            const hashValues = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
                did, seller, rewardAddress, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            await nft.setApprovalForAll(transferCondition.address, true, { from: seller })
            const result = await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32)'](
                agreementId, did, rewardAddress, numberNFTs,
                conditionIdPayment,
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
            expect(eventArgs._receiver).to.equal(rewardAddress)
            expect(eventArgs._amount.toNumber()).to.equal(numberNFTs)
        })

        it('should fulfill doing lazy minting', async () => {
            const {
                rewardAddress,
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true, mintDID: false })

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

            const hashValues = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
                did, seller, rewardAddress, numberNFTs, conditionIdPayment, nft.address, false
            )

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            await nft.setApprovalForAll(transferCondition.address, true, { from: seller })
            const result = await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](
                agreementId, did, rewardAddress, numberNFTs,
                conditionIdPayment, nft.address, false,
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
            expect(eventArgs._receiver).to.equal(rewardAddress)
            expect(eventArgs._amount.toNumber()).to.equal(numberNFTs)
        })

        it('anyone should be able to fulfill if condition exist', async () => {
            const {
                rewardAddress,
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

            const hashValues = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
                did, other, rewardAddress, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            await nft.setApprovalForAll(transferCondition.address, true, { from: other })
            const result = await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](
                agreementId, did, rewardAddress, numberNFTs,
                conditionIdPayment, nft.address, true, { from: other })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)
            testUtils.assertEmitted(result, 1, 'Fulfilled')
        })
    })

    describe('trying to fulfill invalid conditions', () => {
        it('should not fulfill if condition does not exist or account is invalid', async () => {
            const {
                rewardAddress,
                agreementId,
                did,
                transferCondition,
                conditionStoreManager
            } = await setupTest({ registerDID: true })

            const hashValuesPayment = await lockPaymentCondition.hashValues(
                did, lockPaymentCondition.address, token.address, paymentAmounts, paymentReceivers)
            const conditionIdPayment = await lockPaymentCondition.generateId(agreementId, hashValuesPayment)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionIdPayment,
                lockPaymentCondition.address,
                { from: owner }
            )

            await token.mint(buyer, 10, { from: owner })
            await token.approve(lockPaymentCondition.address, 10, { from: buyer })

            await lockPaymentCondition.fulfill(
                agreementId, did, lockPaymentCondition.address, token.address, paymentAmounts, paymentReceivers,
                { from: buyer }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIdPayment)).toNumber(),
                constants.condition.state.fulfilled)

            const hashValues = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
                did, seller, rewardAddress, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            // Invalid reward address
            await assert.isRejected(
                transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](agreementId, did, other, numberNFTs, conditionIdPayment, nft.address, true, { from: seller }),
                /Invalid UpdateRole/
            )

            // Invalid conditionId
            await assert.isRejected(
                transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](agreementId, did, rewardAddress, numberNFTs, testUtils.generateId(), nft.address, true, { from: seller }),
                /LockCondition needs to be Fulfilled/
            )

            // Invalid agreementID
            await assert.isRejected(
                transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](testUtils.generateId(), did, rewardAddress, numberNFTs, conditionIdPayment, nft.address, true, { from: seller }),
                /Invalid UpdateRole/
            )
        })

        it('should not be able to fulfill the same condition twice if condition exist', async () => {
            const {
                rewardAddress,
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

            const hashValues = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
                did, seller, rewardAddress, numberNFTs, conditionIdPayment, nft.address, true)

            const conditionId = await transferCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.methods['createCondition(bytes32,address)'](
                conditionId,
                transferCondition.address,
                { from: owner }
            )

            const result = await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](
                agreementId, did, rewardAddress, numberNFTs,
                conditionIdPayment, nft.address, true, { from: seller })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled)
            testUtils.assertEmitted(result, 1, 'Fulfilled')

            await assert.isRejected(
                transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32,address,bool)'](agreementId, did, rewardAddress, numberNFTs,
                    conditionIdPayment, nft.address, true, { from: seller }),
                /Invalid state transition/
            )
        })
    })
})
