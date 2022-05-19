/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
const { ethers } = require('hardhat')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

describe('NFT721HolderCondition', () => {
    let accounts
    let owner
    let createRole
    const amount = 1
    let didRegistry
    let conditionStoreManager
    let nftHolderCondition
    let token

    before(async () => {
        accounts = await ethers.getSigners()
        owner = accounts[1]
        createRole = accounts[0]
    })

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        
        if (!didRegistry) {
            const NeverminedConfig = await ethers.getContractFactory('NeverminedConfig')
            const EpochLibrary = await ethers.getContractFactory('EpochLibrary')
            const DIDRegistryLibrary = await ethers.getContractFactory('DIDRegistryLibrary')
            const nvmConfig = await NeverminedConfig.deploy()
            await nvmConfig.initialize(owner.address, owner.address)
            const epochLibrary = await EpochLibrary.deploy()
            // await ConditionStoreManager.link(epochLibrary)
            const didRegistryLibrary = await DIDRegistryLibrary.deploy()
            // await DIDRegistry.link(didRegistryLibrary)
            const ConditionStoreManager = await ethers.getContractFactory('ConditionStoreManager', {libraries: { EpochLibrary: epochLibrary.address }})
            const ERC721 = await ethers.getContractFactory('TestERC721')
            const DIDRegistry = await ethers.getContractFactory('DIDRegistry', {libraries: { DIDRegistryLibrary: didRegistryLibrary.address }})
            const NFTHolderCondition = await ethers.getContractFactory('NFT721HolderCondition')
            didRegistry = await DIDRegistry.deploy()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)
            token = await ERC721.deploy()
            await token.initialize()
            conditionStoreManager = await ConditionStoreManager.deploy()
            await conditionStoreManager.connect(owner).initialize(createRole.address, owner.address, nvmConfig.address)

            nftHolderCondition = await NFTHolderCondition.deploy()
            await nftHolderCondition.connect(accounts[0]).initialize(
                accounts[0].address,
                conditionStoreManager.address,
            )
        }
    }

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist for account address', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner.address)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            const hashValues = await nftHolderCondition.hashValues(did, holderAddress.address, amount, token.address)
            const conditionId = await nftHolderCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition2(
                conditionId,
                nftHolderCondition.address)

            await token.connect(holderAddress).mint(did)

            const result = await nftHolderCondition.fulfill(agreementId, did, holderAddress.address, amount, token.address)
            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state, constants.condition.state.fulfilled)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._did).to.equal(did)
            expect(eventArgs._address).to.equal(holderAddress.address)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._amount.toNumber()).to.equal(amount)
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner.address)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            await token.connect(holderAddress).mint(did)

            await assert.isRejected(
                nftHolderCondition.fulfill(agreementId, did, holderAddress.address, amount, token.address),
                constants.acl.error.invalidUpdateRole
            )
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('out of balance should fail to fulfill if conditions exist', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner.address)

            const agreementId = testUtils.generateId()
            const holderAddress = accounts[2]

            const hashValues = await nftHolderCondition.hashValues(did, holderAddress.address, amount, token.address)
            const conditionId = await nftHolderCondition.generateId(agreementId, hashValues)

            await token.connect(owner).mint(did)

            await conditionStoreManager.createCondition2(
                conditionId,
                nftHolderCondition.address)

            await assert.isRejected(
                nftHolderCondition.fulfill(agreementId, did, holderAddress.address, amount, token.address),
                constants.condition.nft.error.notEnoughNFTBalance
            )
        })
    })
})
