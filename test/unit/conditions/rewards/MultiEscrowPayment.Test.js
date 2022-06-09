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
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const NeverminedToken = artifacts.require('NeverminedToken')
const NeverminedConfig = artifacts.require('NeverminedConfig')
const LockPaymentCondition = artifacts.require('LockPaymentCondition')
const NFTLockCondition = artifacts.require('NFTLockCondition')
const NFT721LockCondition = artifacts.require('NFT721LockCondition')
const EscrowPaymentCondition = artifacts.require('EscrowPaymentCondition')
const NFTEscrowPaymentCondition = artifacts.require('NFTEscrowPaymentCondition')
const NFT721EscrowPaymentCondition = artifacts.require('NFT721EscrowPaymentCondition')

const NFT = artifacts.require('NFTUpgradeable')
const NFT721 = artifacts.require('NFT721Upgradeable')

const constants = require('../../../helpers/constants.js')
const testUtils = require('../../../helpers/utils.js')

const wrapper = require('./wrapper')

function testMultiEscrow(EscrowPaymentCondition, LockPaymentCondition, Token, nft, wrappers, amount1, amount2, label) {
    contract(`EscrowPaymentCondition contract (multi) for ${label}`, (accounts) => {
        const { lockWrapper, escrowWrapper, tokenWrapper } = wrappers

        let conditionStoreManager
        let token
        let lockPaymentCondition
        let escrowPayment
        let didRegistry
        let nvmConfig

        const createRole = accounts[0]
        const owner = accounts[9]
        const deployer = accounts[8]

        before(async () => {
            if (!nft) {
                const epochLibrary = await EpochLibrary.new()
                await ConditionStoreManager.link(epochLibrary)
                const didRegistryLibrary = await DIDRegistryLibrary.new()
                await DIDRegistry.link(didRegistryLibrary)
            }
        })

        beforeEach(async () => {
            await setupTest()
        })

        async function setupTest({
            conditionId = testUtils.generateId(),
            conditionType = testUtils.generateId()
        } = {}) {
            if (!escrowPayment) {
                nvmConfig = await NeverminedConfig.new()
                await nvmConfig.initialize(owner, owner)

                conditionStoreManager = await ConditionStoreManager.new()
                await conditionStoreManager.initialize(
                    createRole,
                    owner,
                    nvmConfig.address,
                    { from: owner }
                )

                token = tokenWrapper(await Token.new())

                didRegistry = await DIDRegistry.new()
                await didRegistry.initialize(owner, token.address, token.address)

                await token.initWrap(owner, owner, didRegistry)

                lockPaymentCondition = lockWrapper(await LockPaymentCondition.new())
                await lockPaymentCondition.initWrap(
                    owner,
                    conditionStoreManager.address,
                    didRegistry.address,
                    { from: deployer }
                )

                escrowPayment = escrowWrapper(await EscrowPaymentCondition.new())
                await escrowPayment.initialize(
                    owner,
                    conditionStoreManager.address,
                    { from: deployer }
                )

                await conditionStoreManager.grantProxyRole(
                    escrowPayment.address,
                    { from: owner }
                )
            }

            return {
                escrowPayment,
                lockPaymentCondition,
                token,
                conditionStoreManager,
                conditionId,
                conditionType,
                createRole,
                owner
            }
        }

        describe('fulfill with two release conditions', () => {
            it('should fulfill if both are fulfilled', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const receivers2 = [accounts[2]]
                const amounts2 = [amount2]
                const totalAmount = amounts[0] + amounts2[0]
                const balanceBefore = await token.getBalance(escrowPayment.address)

                const did = await token.makeDID(sender, didRegistry)
                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)
                const hashValuesLock2 = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts2, receivers2)
                const conditionLockId2 = await lockPaymentCondition.generateId(agreementId, hashValuesLock2)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                await conditionStoreManager.createCondition(
                    conditionLockId2,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])
                )

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])
                )

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts2, receivers2)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                const result = await escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                testUtils.assertEmitted(result, 1, 'Fulfilled')
                const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
                expect(eventArgs._agreementId).to.equal(agreementId)
                expect(eventArgs._conditionId).to.equal(escrowConditionId)
                if (nft) {
                    expect(eventArgs._receivers).to.equal(receivers[0])
                    expect(eventArgs._amounts.toNumber()).to.equal(amounts[0])
                } else {
                    expect(eventArgs._receivers[0]).to.equal(receivers[0])
                    expect(eventArgs._amounts[0].toNumber()).to.equal(amounts[0])
                }

                assert.strictEqual(await token.getBalance(escrowPayment.address), amounts2[0])
                assert.strictEqual(await token.getBalance(receivers[0]), amounts[0])
            })

            it('should cancel if conditions were aborted', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const receivers2 = [accounts[2]]
                const amounts2 = [amount2]
                const totalAmount = amounts[0] + amounts2[0]
                const did = await token.makeDID(sender, didRegistry)

                const balanceBefore = await token.getBalance(escrowPayment.address)
                const senderBefore = await token.getBalance(sender)
                const receiverBefore = await token.getBalance(receivers[0])

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)
                const hashValuesLock2 = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts2, receivers2)
                const conditionLockId2 = await lockPaymentCondition.generateId(agreementId, hashValuesLock2)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                await conditionStoreManager.createCondition(
                    conditionLockId2,
                    lockPaymentCondition.address,
                    1,
                    2
                )

                const lockConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])
                )

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])
                )

                await lockPaymentCondition.abortByTimeOut(conditionLockId2)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + amounts[0])

                const result = await escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers,
                    sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    [conditionLockId, conditionLockId2])

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                testUtils.assertEmitted(result, 1, 'Fulfilled')
                const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
                expect(eventArgs._agreementId).to.equal(agreementId)
                expect(eventArgs._conditionId).to.equal(escrowConditionId)
                if (nft) {
                    expect(eventArgs._receivers).to.equal(sender)
                    expect(eventArgs._amounts.toNumber()).to.equal(amounts[0])
                } else {
                    expect(eventArgs._receivers[0]).to.equal(sender)
                    expect(eventArgs._amounts[0].toNumber()).to.equal(amounts[0])
                }

                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore)
                assert.strictEqual(await token.getBalance(receivers[0]), receiverBefore)
                assert.strictEqual(await token.getBalance(sender), senderBefore + totalAmount)
            })
        })
    })
}

testMultiEscrow(EscrowPaymentCondition, LockPaymentCondition, NeverminedToken, false, wrapper.normal, 10, 12, 'ERC-20')
testMultiEscrow(NFTEscrowPaymentCondition, NFTLockCondition, NFT, true, wrapper.nft, 10, 12, 'ERC-1155')
testMultiEscrow(NFT721EscrowPaymentCondition, NFT721LockCondition, NFT721, true, wrapper.nft721, 1, 0, 'ERC-721')
