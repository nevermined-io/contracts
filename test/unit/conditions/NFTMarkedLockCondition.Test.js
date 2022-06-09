/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')
const EpochLibrary = artifacts.require('EpochLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')
const NFTLockCondition = artifacts.require('NFTLockCondition')
const NFT = artifacts.require('NFTUpgradeable')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('NFTMarkedLockCondition', (accounts) => {
    let conditionStoreManager
    let didRegistry
    let lockCondition
    let nft
    let nvmConfig

    const receiver = accounts[2]
    const owner = accounts[1]
    const createRole = accounts[0]
    const url = constants.registry.url
    const checksum = constants.bytes32.one
    const amount = 10

    before(async () => {
        nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, owner)
        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
        const didRegistryLibrary = await DIDRegistryLibrary.new()
        await DIDRegistry.link(didRegistryLibrary)
    })

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!didRegistry) {
            nft = await NFT.new()
            await nft.initialize('')

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, nft.address, constants.address.zero)
            await nft.addMinter(didRegistry.address)
        }
        if (!conditionStoreManager) {
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            lockCondition = await NFTLockCondition.new()

            await lockCondition.initialize(
                owner,
                conditionStoreManager.address,
                nft.address,
                { from: createRole }
            )
        }
    }

    describe('fulfill correctly', () => {
        it('should fulfill if conditions exist for account address', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const agreementId = testUtils.generateId()
            const lockAddress = lockCondition.address

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, constants.activities.GENERATED, '')
            await didRegistry.mint(did, amount)
            await nft.setApprovalForAll(lockCondition.address, true)

            const hashValues = await lockCondition.hashValuesMarked(did, lockAddress, amount, receiver, nft.address)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            const result = await lockCondition.fulfillMarked(agreementId, did, lockAddress, amount, receiver, nft.address)
            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const nftBalance = await nft.balanceOf(lockCondition.address, did)
            assert.strictEqual(nftBalance.toNumber(), amount)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._did).to.equal(did)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._lockAddress).to.equal(lockAddress)
            expect(eventArgs._amount.toNumber()).to.equal(amount)
        })
    })

    describe('trying to fulfill but is invalid', () => {
        it('should not fulfill if conditions do not exist', async () => {
            const agreementId = testUtils.generateId()
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const lockAddress = accounts[2]

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, true, constants.activities.GENERATED, '')

            await nft.setApprovalForAll(lockCondition.address, true)

            await assert.isRejected(
                lockCondition.fulfillMarked(agreementId, did, lockAddress, amount, receiver, nft.address),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('out of balance should fail to fulfill', async () => {
            const agreementId = testUtils.generateId()
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const lockAddress = accounts[2]

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, constants.activities.GENERATED, '')
            await didRegistry.mint(did, amount)
            await nft.setApprovalForAll(lockCondition.address, true)

            const hashValues = await lockCondition.hashValuesMarked(did, lockAddress, amount, receiver, nft.address)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            await assert.isRejected(
                lockCondition.fulfillMarked(agreementId, did, lockAddress, amount + 1, receiver, nft.address),
                undefined
            )
        })

        it('right transfer should fail to fulfill if conditions already fulfilled', async () => {
            const agreementId = testUtils.generateId()
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const lockAddress = accounts[2]

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, constants.activities.GENERATED, '')
            await didRegistry.mint(did, amount)
            await nft.setApprovalForAll(lockCondition.address, true)

            const hashValues = await lockCondition.hashValuesMarked(did, lockAddress, amount, receiver, nft.address)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address
            )

            await lockCondition.fulfillMarked(agreementId, did, lockAddress, amount, receiver, nft.address)
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )

            await assert.isRejected(
                lockCondition.fulfillMarked(agreementId, did, lockAddress, amount, receiver, nft.address),
                undefined
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            const agreementId = testUtils.generateId()
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const lockAddress = accounts[2]

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, constants.activities.GENERATED, '')
            await didRegistry.mint(did, amount)
            await nft.setApprovalForAll(lockCondition.address, true)

            const hashValues = await lockCondition.hashValuesMarked(did, lockAddress, amount, receiver, nft.address)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            await assert.isRejected(
                lockCondition.fulfillMarked(agreementId, did, lockAddress, amount, receiver, nft.address),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
