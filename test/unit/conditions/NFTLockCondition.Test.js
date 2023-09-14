/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NFTLockCondition = artifacts.require('NFTLockCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('NFTLockCondition', (accounts) => {
    let conditionStoreManager
    let didRegistry
    let lockCondition
    let nft
    let nvmConfig

    const owner = accounts[1]
    const createRole = accounts[0]
    const url = constants.registry.url
    const checksum = constants.bytes32.one
    const amount = 10

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!conditionStoreManager) {
            ({ didRegistry, conditionStoreManager, nft, nvmConfig } = await testUtils.deployManagers(owner, createRole))

            lockCondition = await NFTLockCondition.new()

            await lockCondition.initialize(
                owner,
                conditionStoreManager.address,
                nft.address,
                { from: createRole }
            )
            console.log(await nft.getNvmConfigAddress())
            await nvmConfig.setOperator(lockCondition.address, { from: owner })
            await nvmConfig.setOperator(accounts[0], { from: owner })
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
                didSeed, nft.address, checksum, [], url, amount, 0, constants.activities.GENERATED, '', '')
            await nft.methods['mint(uint256,uint256)'](did, amount)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            const result = await lockCondition.fulfill(agreementId, did, lockAddress, amount)
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
                didSeed, nft.address, checksum, [], url, amount, 0, true, constants.activities.GENERATED, '', '')

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount),
                constants.acl.error.conditionDoesntExist
            )
        })

        it('out of balance should fail to fulfill', async () => {
            const agreementId = testUtils.generateId()
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const lockAddress = accounts[2]

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], url, amount, 0, constants.activities.GENERATED, '', '')
            await nft.methods['mint(uint256,uint256)'](did, amount)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount + 1),
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
                didSeed, nft.address, checksum, [], url, amount, 0, constants.activities.GENERATED, '', '')
            await nft.methods['mint(uint256,uint256)'](did, amount)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address
            )

            await lockCondition.fulfill(agreementId, did, lockAddress, amount)
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount),
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
                didSeed, nft.address, checksum, [], url, amount, 0, constants.activities.GENERATED, '', '')
            await nft.methods['mint(uint256,uint256)'](did, amount)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount)
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
                lockCondition.fulfill(agreementId, did, lockAddress, amount),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
