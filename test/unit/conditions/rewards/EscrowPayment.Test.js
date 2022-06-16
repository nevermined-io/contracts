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
const EscrowPaymentCondition = artifacts.require('EscrowPaymentCondition')

const NFTLockCondition = artifacts.require('NFTLockCondition')
const NFT721LockCondition = artifacts.require('NFT721LockCondition')
const NFTEscrowPaymentCondition = artifacts.require('NFTEscrowPaymentCondition')
const NFT721EscrowPaymentCondition = artifacts.require('NFT721EscrowPaymentCondition')

const NFT = artifacts.require('NFTUpgradeable')
const NFT721 = artifacts.require('NFT721Upgradeable')

const constants = require('../../../helpers/constants.js')
const { getETHBalance } = require('../../../helpers/getBalance.js')
const testUtils = require('../../../helpers/utils.js')

const wrapper = require('./wrapper')

function escrowTest(EscrowPaymentCondition, LockPaymentCondition, Token, nft, nft721, wrappers, amount1, amount2, label) {
    const multi = a => [a]
    const { lockWrapper, escrowWrapper, tokenWrapper } = wrappers
    contract(`EscrowPaymentCondition contract for ${label}`, (accounts) => {
        let conditionStoreManager
        let token
        let lockPaymentCondition
        let escrowPayment
        let didRegistry
        let nvmConfig

        const createRole = accounts[0]
        const owner = accounts[9]
        const deployer = accounts[8]
        const checksum = testUtils.generateId()
        const url = 'https://nevermined.io/did/test-attr-example.txt'

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

        describe('init failure', () => {
            it('needed contract addresses cannot be 0', async () => {
                const conditionStoreManager = await ConditionStoreManager.new()
                await conditionStoreManager.initialize(
                    createRole,
                    owner,
                    nvmConfig.address,
                    { from: owner }
                )

                const didRegistry = await DIDRegistry.new()
                await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)

                const token = tokenWrapper(await Token.new())
                await token.initWrap(owner, owner, didRegistry)
                const lockPaymentCondition = lockWrapper(await LockPaymentCondition.new())
                await lockPaymentCondition.initWrap(
                    owner,
                    conditionStoreManager.address,
                    didRegistry.address,
                    { from: deployer }
                )

                const escrowPayment = escrowWrapper(await EscrowPaymentCondition.new())
                await assert.isRejected(escrowPayment.initialize(
                    owner,
                    constants.address.zero,
                    { from: deployer }
                ), undefined)
            })
        })

        describe('fulfill non existing condition', () => {
            it('should not fulfill if conditions do not exist', async () => {
                const agreementId = testUtils.generateId()
                const did = testUtils.generateId()
                const lockConditionId = accounts[2]
                const releaseConditionId = accounts[3]
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [10]

                await assert.isRejected(
                    escrowPayment.fulfillWrap(
                        agreementId,
                        did,
                        amounts,
                        receivers, sender,
                        sender,
                        token.address,
                        lockConditionId,
                        multi(releaseConditionId)),
                    constants.condition.reward.escrowReward.error.lockConditionIdDoesNotMatch
                )
            })
        })

        describe('fulfill existing condition', () => {
            it('ERC20: should fulfill if conditions exist for account address', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const totalAmount = amounts[0]

                const did = await token.makeDID(sender, didRegistry)

                const balanceBefore = await token.getBalance(escrowPayment.address)
                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                const result = await escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

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

                assert.strictEqual(await token.getBalance(escrowPayment.address), 0)
                assert.strictEqual(await token.getBalance(receivers[0]), totalAmount)

                if (nft721) {
                    await token.transferWrap(escrowPayment.address, totalAmount, { from: receivers[0] })
                } else {
                    await token.mintWrap(didRegistry, sender, totalAmount, owner)
                    await token.approveWrap(
                        lockPaymentCondition.address,
                        totalAmount,
                        { from: sender })
                    await token.transferWrap(escrowPayment.address, totalAmount, { from: sender })
                }

                assert.strictEqual(await token.getBalance(escrowPayment.address), totalAmount)
                await assert.isRejected(
                    escrowPayment.fulfillWrap(agreementId, did, amounts, receivers, sender, escrowPayment.address, token.address, lockConditionId, multi(releaseConditionId)),
                    undefined
                )
            })

            it('ETH: should fulfill if conditions exist for account address', async () => {
                if (nft) {
                    return
                }
                const sender = accounts[0]
                const agreementId = testUtils.generateId()
                const didSeed = testUtils.generateId()
                const did = await didRegistry.hashDID(didSeed, accounts[0])
                const totalAmount = 500000000000n
                const amounts = [totalAmount]
                const receivers = [accounts[1]]

                // register DID
                await didRegistry.registerMintableDID(
                    didSeed, checksum, [], url, amounts[0], 0, false, constants.activities.GENERATED, '')

                const hashValuesLock = await lockPaymentCondition.hashValues(
                    did, escrowPayment.address, constants.address.zero, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashValuesMulti(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    constants.address.zero,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                const balanceSenderBefore = await getETHBalance(sender)
                const balanceContractBefore = await getETHBalance(escrowPayment.address)
                const balanceReceiverBefore = await getETHBalance(receivers[0])

                assert(balanceSenderBefore >= totalAmount)

                await lockPaymentCondition.fulfill(
                    agreementId, did, escrowPayment.address, constants.address.zero, amounts, receivers,
                    { from: sender, value: Number(totalAmount), gasPrice: 0 })

                const balanceSenderAfterLock = await getETHBalance(sender)
                const balanceContractAfterLock = await getETHBalance(escrowPayment.address)

                assert(balanceSenderAfterLock >= balanceSenderBefore - totalAmount)
                assert(balanceContractAfterLock <= balanceContractBefore + totalAmount)

                const result = await escrowPayment.fulfillMulti(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    constants.address.zero,
                    lockConditionId,
                    multi(releaseConditionId))

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                testUtils.assertEmitted(result, 1, 'Fulfilled')
                const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
                expect(eventArgs._agreementId).to.equal(agreementId)
                expect(eventArgs._conditionId).to.equal(escrowConditionId)
                expect(eventArgs._receivers[0]).to.equal(receivers[0])
                expect(eventArgs._amounts[0].toNumber()).to.equal(Number(amounts[0]))

                const balanceSenderAfterEscrow = await getETHBalance(sender)
                const balanceContractAfterEscrow = await getETHBalance(escrowPayment.address)
                const balanceReceiverAfterEscrow = await getETHBalance(receivers[0])

                assert(balanceSenderAfterEscrow <= balanceSenderBefore - totalAmount)
                assert(balanceContractAfterEscrow <= balanceContractBefore)
                assert(balanceReceiverAfterEscrow >= balanceReceiverBefore + totalAmount)
                await assert.isRejected(
                    escrowPayment.fulfillMulti(agreementId, did, amounts, receivers, sender, escrowPayment.address, constants.address.zero, lockConditionId, multi(releaseConditionId)),
                    undefined
                )
            })

            it('ETH: fail if escrow is receiver', async () => {
                if (nft) {
                    return
                }
                const agreementId = testUtils.generateId()
                const didSeed = testUtils.generateId()
                const did = await didRegistry.hashDID(didSeed, accounts[0])
                const totalAmount = 500000000000n
                const sender = accounts[0]
                const amounts = [totalAmount]
                const receivers = [escrowPayment.address]

                // register DID
                await didRegistry.registerMintableDID(
                    didSeed, checksum, [], url, amounts[0], 0, false, constants.activities.GENERATED, '')

                const hashValuesLock = await lockPaymentCondition.hashValues(
                    did, escrowPayment.address, constants.address.zero, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashValues(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    constants.address.zero,
                    lockConditionId,
                    releaseConditionId)

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                const balanceSenderBefore = await getETHBalance(sender)
                const balanceContractBefore = await getETHBalance(escrowPayment.address)

                assert(balanceSenderBefore >= totalAmount)

                await lockPaymentCondition.fulfill(
                    agreementId, did, escrowPayment.address, constants.address.zero, amounts, receivers,
                    { from: sender, value: String(totalAmount) })

                const balanceSenderAfterLock = await getETHBalance(sender)
                const balanceContractAfterLock = await getETHBalance(escrowPayment.address)

                assert(balanceSenderAfterLock <= balanceSenderBefore - totalAmount)
                assert(balanceContractAfterLock >= balanceContractBefore + totalAmount)

                await assert.isRejected(
                    escrowPayment.fulfill(agreementId, did, amounts, receivers, sender, escrowPayment.address, constants.address.zero, lockConditionId, releaseConditionId),
                    undefined
                )
            })

            it('receiver and amount lists need to have same length', async () => {
                if (nft) {
                    return
                }
                const agreementId = testUtils.generateId()
                const did = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const amounts2 = [amount1, amount2]

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                await assert.isRejected(escrowPayment.hashWrap(
                    did,
                    amounts2,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId)),
                undefined)
            })

            it('lock condition not fulfilled', async () => {
                const agreementId = testUtils.generateId()
                const did = await token.makeDID(accounts[0], didRegistry)
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const sender = accounts[0]

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId)),
                'LockCondition needs to be Fulfilled')
            })

            it('release condition not fulfilled', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const receivers2 = [accounts[5]]
                const amounts2 = [amount2]
                const totalAmount = amounts[0]
                const balanceBefore = await token.getBalance(escrowPayment.address)
                const did = await token.makeDID(sender, didRegistry)

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const lockConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    lockConditionId,
                    lockPaymentCondition.address)

                const hashValuesLock2 = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts2, receivers2)
                const releaseConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock2)

                await conditionStoreManager.createCondition(
                    releaseConditionId,
                    lockPaymentCondition.address)

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId)))

                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)
            })

            it('ERC20: release condition aborted', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const receivers2 = [accounts[5]]
                const amounts2 = [amount2]
                const totalAmount = amounts[0]
                const did = await token.makeDID(sender, didRegistry)
                const balanceBefore = await token.getBalance(escrowPayment.address)

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const lockConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    lockConditionId,
                    lockPaymentCondition.address)

                const hashValuesLock2 = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts2, receivers2)
                const releaseConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock2)

                await conditionStoreManager.createCondition(
                    releaseConditionId,
                    lockPaymentCondition.address,
                    1,
                    2
                )

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                // abort release
                await lockPaymentCondition.abortByTimeOut(releaseConditionId)

                await escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                assert.strictEqual(await token.getBalance(sender), totalAmount)
            })

            it('ETH: release condition aborted', async () => {
                if (nft) {
                    return
                }
                const agreementId = testUtils.generateId()
                const did = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [1000000000000]
                const receivers2 = [accounts[5]]
                const amounts2 = [20]
                const totalAmount = amounts[0]

                const hashValuesLock = await lockPaymentCondition.hashValues(did, escrowPayment.address, constants.address.zero, amounts, receivers)
                const lockConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    lockConditionId,
                    lockPaymentCondition.address
                )

                const hashValuesLock2 = await lockPaymentCondition.hashValues(did, escrowPayment.address, constants.address.zero, amounts2, receivers2)
                const releaseConditionId = await lockPaymentCondition.generateId(agreementId, hashValuesLock2)

                await conditionStoreManager.createCondition(
                    releaseConditionId,
                    lockPaymentCondition.address,
                    1,
                    2
                )

                const hashValues = await escrowPayment.hashValues(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    constants.address.zero,
                    lockConditionId,
                    releaseConditionId)

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address
                )

                const balanceBefore = await getETHBalance(sender)
                await lockPaymentCondition.fulfill(agreementId, did, escrowPayment.address, constants.address.zero, amounts, receivers,
                    { from: sender, value: totalAmount, gasPrice: 0 })

                // abort release
                await lockPaymentCondition.abortByTimeOut(releaseConditionId, { from: sender, gasPrice: 0 })

                await escrowPayment.fulfill(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    constants.address.zero,
                    lockConditionId,
                    releaseConditionId, { from: sender, gasPrice: 0 })

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )
                assert.strictEqual(
                    await getETHBalance(sender),
                    balanceBefore
                )
            })

            it('should not fulfill in case of null addresses', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [constants.address.zero]
                const amounts = [amount1]
                const totalAmount = amounts[0]
                const did = await token.makeDID(sender, didRegistry)
                const balanceBefore = await token.getBalance(escrowPayment.address)

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    sender,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))
                const conditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    testUtils.generateId(),
                    escrowPayment.address)

                await conditionStoreManager.createCondition(
                    conditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                await assert.isRejected(
                    escrowPayment.fulfillWrap(
                        agreementId,
                        did,
                        amounts,
                        receivers, sender,
                        escrowPayment.address,
                        token.address,
                        lockConditionId,
                        multi(releaseConditionId)
                    ),
                    'transfer to the zero address'
                )
            })
            it('should not fulfill if the receiver address is Escrow contract address', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [escrowPayment.address]
                const amounts = [amount1]
                const totalAmount = amounts[0]
                const did = await token.makeDID(sender, didRegistry)
                const balanceBefore = await token.getBalance(escrowPayment.address)

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    sender,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))
                const conditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    testUtils.generateId(),
                    escrowPayment.address)

                await conditionStoreManager.createCondition(
                    conditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                await assert.isRejected(
                    escrowPayment.fulfillWrap(
                        agreementId,
                        did,
                        amounts,
                        receivers, sender,
                        escrowPayment.address,
                        token.address,
                        lockConditionId,
                        multi(releaseConditionId)
                    ),
                    'Escrow contract can not be a receiver'
                )
            })
        })

        describe('only fulfill conditions once', () => {
            it('do not allow rewards to be fulfilled twice', async () => {
                if (nft721) {
                    return
                }
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const attacker = [accounts[2]]
                const receivers = [escrowPayment.address]
                const amounts = [amount1]
                const totalAmount = amounts[0]
                const did = await token.makeDID(sender, didRegistry)

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                await conditionStoreManager.createCondition(
                    testUtils.generateId(),
                    escrowPayment.address)

                /* simulate a real environment by giving the EscrowPayment contract a bunch of tokens: */
                await token.mintWrap(didRegistry, sender, 100, owner)
                await token.transferWrap(escrowPayment.address, 100, { from: sender })

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                /* fulfill the lock condition */

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                const escrowPaymentBalance = 110

                /* attacker creates escrowPaymentBalance/amount bogus conditions to claim the locked reward: */

                for (let i = 0; i < escrowPaymentBalance / amounts; ++i) {
                    let agreementId = (3 + i).toString(16)
                    while (agreementId.length < 32 * 2) {
                        agreementId = '0' + agreementId
                    }
                    const attackerAgreementId = '0x' + agreementId
                    const attackerHashValues = await escrowPayment.hashWrap(
                        did,
                        amounts,
                        attacker,
                        sender,
                        attacker[0],
                        token.address,
                        lockConditionId,
                        multi(releaseConditionId))
                    const attackerConditionId = await escrowPayment.generateId(attackerAgreementId, attackerHashValues)

                    await conditionStoreManager.createCondition(
                        attackerConditionId,
                        escrowPayment.address)

                    /* attacker tries to claim the escrow before the legitimate users: */
                    await assert.isRejected(
                        escrowPayment.fulfillWrap(
                            attackerAgreementId,
                            did,
                            amounts,
                            attacker,
                            sender,
                            attacker[0],
                            token.address,
                            lockConditionId,
                            multi(releaseConditionId)),
                        constants.condition.reward.escrowReward.error.lockConditionIdDoesNotMatch
                    )
                }

                /* make sure the EscrowPayment contract didn't get drained */
                assert.notStrictEqual(
                    await token.getBalance(escrowPayment.address),
                    0
                )
            })

            it('ERC20: should bit fulfill if was already fulfilled', async () => {
                const agreementId = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const amounts = [amount1]
                const totalAmount = amounts[0]
                const did = await token.makeDID(sender, didRegistry)

                const balanceContractBefore = await token.getBalance(escrowPayment.address)
                const balanceReceiverBefore = await token.getBalance(receivers[0])

                const hashValuesLock = await lockPaymentCondition.hashWrap(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashWrap(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfillWrap(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceContractBefore + totalAmount)

                await escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceContractBefore)
                assert.strictEqual(await token.getBalance(receivers[0]), balanceReceiverBefore + totalAmount)

                await assert.isRejected(escrowPayment.fulfillWrap(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    multi(releaseConditionId))
                )

                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceContractBefore)
                assert.strictEqual(await token.getBalance(receivers[0]), balanceReceiverBefore + totalAmount)
            })
            /*
            it('Should not be able to reuse the condition', async () => {
                if (nft) {
                    return
                }
                const agreementId = testUtils.generateId()
                const did = testUtils.generateId()
                const sender = accounts[0]
                const receivers = [accounts[1]]
                const receivers2 = [accounts[2]]
                const amounts = [amount1]
                const totalAmount = amounts[0]
                const balanceBefore = await token.getBalance(escrowPayment.address)

                const hashValuesLock = await lockPaymentCondition.hashValues(did, escrowPayment.address, token.address, amounts, receivers)
                const conditionLockId = await lockPaymentCondition.generateId(agreementId, hashValuesLock)

                await conditionStoreManager.createCondition(
                    conditionLockId,
                    lockPaymentCondition.address)

                const lockConditionId = conditionLockId
                const releaseConditionId = conditionLockId

                const hashValues = await escrowPayment.hashValues(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    releaseConditionId)

                const escrowConditionId = await escrowPayment.generateId(agreementId, hashValues)

                await conditionStoreManager.createCondition(
                    escrowConditionId,
                    escrowPayment.address)

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfill(agreementId, did, escrowPayment.address, token.address, amounts, receivers)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                const result = await escrowPayment.fulfill(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    releaseConditionId)

                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(escrowConditionId)).toNumber(),
                    constants.condition.state.fulfilled
                )

                testUtils.assertEmitted(result, 1, 'Fulfilled')
                const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
                expect(eventArgs._agreementId).to.equal(agreementId)
                expect(eventArgs._conditionId).to.equal(escrowConditionId)
                expect(eventArgs._receivers[0]).to.equal(receivers[0])
                expect(eventArgs._amounts[0].toNumber()).to.equal(amounts[0])

                const conditionLockId2 = await lockPaymentCondition.generateId(agreementId, await lockPaymentCondition.hashValues(did, escrowPayment.address, token.address, amounts, receivers2))

                await conditionStoreManager.createCondition(
                    conditionLockId2,
                    lockPaymentCondition.address)

                const releaseConditionId2 = conditionLockId2

                await token.mintWrap(didRegistry, sender, totalAmount, owner)
                await token.approveWrap(
                    lockPaymentCondition.address,
                    totalAmount,
                    { from: sender })

                await lockPaymentCondition.fulfill(agreementId, did, escrowPayment.address, token.address, amounts, receivers2)

                assert.strictEqual(await token.getBalance(lockPaymentCondition.address), 0)
                assert.strictEqual(await token.getBalance(escrowPayment.address), balanceBefore + totalAmount)

                const escrowConditionId2 = await escrowPayment.generateId(agreementId, await escrowPayment.hashValues(
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    releaseConditionId2))

                await conditionStoreManager.createCondition(
                    escrowConditionId2,
                    escrowPayment.address)

                await assert.isRejected(escrowPayment.fulfill(
                    agreementId,
                    did,
                    amounts,
                    receivers, sender,
                    escrowPayment.address,
                    token.address,
                    lockConditionId,
                    releaseConditionId2),
                /Lock condition already used/)
            })
            */
        })
    })
}

escrowTest(EscrowPaymentCondition, LockPaymentCondition, NeverminedToken, false, false, wrapper.normal, 10, 12, 'ERC-20')
escrowTest(NFTEscrowPaymentCondition, NFTLockCondition, NFT, true, false, wrapper.nft, 10, 12, 'ERC-1155')
escrowTest(NFT721EscrowPaymentCondition, NFT721LockCondition, NFT721, true, true, wrapper.nft721, 1, 0, 'ERC-721')
