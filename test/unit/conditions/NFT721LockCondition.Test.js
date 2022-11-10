/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NFTLockCondition = artifacts.require('NFT721LockCondition')
const NFT721Upgradeable = artifacts.require('NFT721Upgradeable')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('NFT721LockCondition', (accounts) => {
    let conditionStoreManager
    let didRegistry
    let lockCondition
    let erc721
    let nftTokenAddress

    const owner = accounts[1]
    const createRole = accounts[0]
    const url = constants.registry.url
    const checksum = constants.bytes32.one
    const amount = 1

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!conditionStoreManager) {
            ({ didRegistry, conditionStoreManager } = await testUtils.deployManagers(owner, createRole))

            lockCondition = await NFTLockCondition.new()

            await lockCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: createRole }
            )
        }

        // We deploy the ERC-721 in each test iteration
        erc721 = await NFT721Upgradeable.new()
        await erc721.initialize({ from: accounts[0] })
        nftTokenAddress = erc721.address
        console.log('ERC-721 deployed on address ' + nftTokenAddress)
    }

    describe('fulfill correctly', () => {
        it('should fulfill if conditions exist for account address', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, accounts[0])

            const agreementId = testUtils.generateId()
            const lockAddress = lockCondition.address

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '', '')
            const tokenId = did
            await erc721.mint(accounts[0], tokenId)
            await erc721.approve(lockCondition.address, did)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount, nftTokenAddress)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            const result = await lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress)
            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            assert.strictEqual(lockAddress, await erc721.ownerOf(did))

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
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '', '')
            await erc721.mint(accounts[0], did)

            await erc721.approve(lockCondition.address, did)

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress),
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
<<<<<<< HEAD
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '', '')
            await erc721.mint(did)
||||||| d65359a4
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '')
            await erc721.mint(did)
=======
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '')
            await erc721.mint(accounts[0], did)
>>>>>>> develop
            await erc721.approve(lockCondition.address, did)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount, nftTokenAddress)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address)

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress, { from: accounts[2] }),
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
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '', '')
            await erc721.mint(did)
            await erc721.approve(lockCondition.address, did)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount, nftTokenAddress)
            const conditionId = await lockCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockCondition.address
            )

            await lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress)
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )

            await assert.isRejected(
                lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress),
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
                didSeed, checksum, [], url, amount, 0, false, constants.activities.GENERATED, '', '')
            await erc721.mint(did)
            await erc721.approve(lockCondition.address, did)

            const hashValues = await lockCondition.hashValues(did, lockAddress, amount, nftTokenAddress)
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
                lockCondition.fulfill(agreementId, did, lockAddress, amount, nftTokenAddress),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
