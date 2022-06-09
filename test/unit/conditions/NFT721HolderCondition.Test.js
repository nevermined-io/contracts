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
const ERC721 = artifacts.require('TestERC721')
const DIDRegistry = artifacts.require('DIDRegistry')
const NFTHolderCondition = artifacts.require('NFT721HolderCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('NFT721HolderCondition', (accounts) => {
    const owner = accounts[1]
    const createRole = accounts[0]
    const amount = 1
    let didRegistry
    let conditionStoreManager
    let nftHolderCondition
    let token
    let nvmConfig

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
            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)
            token = await ERC721.new()
            await token.initialize()
        }
        if (!conditionStoreManager) {
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(createRole, owner, nvmConfig.address, { from: owner })

            nftHolderCondition = await NFTHolderCondition.new()
            await nftHolderCondition.initialize(
                accounts[0],
                conditionStoreManager.address,
                { from: accounts[0] })
        }
    }

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist for account address', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            const hashValues = await nftHolderCondition.hashValues(did, holderAddress, amount, token.address)
            const conditionId = await nftHolderCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                nftHolderCondition.address)

            await token.mint(did, { from: holderAddress })

            const result = await nftHolderCondition.fulfill(agreementId, did, holderAddress, amount, token.address)
            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._did).to.equal(did)
            expect(eventArgs._address).to.equal(holderAddress)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._amount.toNumber()).to.equal(amount)
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            await token.mint(did, { from: holderAddress })

            await assert.isRejected(
                nftHolderCondition.fulfill(agreementId, did, holderAddress, amount, token.address),
                constants.acl.error.invalidUpdateRole
            )
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('out of balance should fail to fulfill if conditions exist', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            const hashValues = await nftHolderCondition.hashValues(did, holderAddress, amount, token.address)
            const conditionId = await nftHolderCondition.generateId(agreementId, hashValues)

            await token.mint(did, { from: owner })

            await conditionStoreManager.createCondition(
                conditionId,
                nftHolderCondition.address)

            await assert.isRejected(
                nftHolderCondition.fulfill(agreementId, did, holderAddress, amount, token.address),
                constants.condition.nft.error.notEnoughNFTBalance
            )
        })
    })
})
