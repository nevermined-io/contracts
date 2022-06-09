/* eslint-env mocha */
/* eslint-disable no-console */
/* global contract, describe, it, expect */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const deployConditions = require('../../helpers/deployConditions.js')
const deployManagers = require('../../helpers/deployManagers.js')
const testUtils = require('../../helpers/utils')

const { makeProof } = require('../../helpers/proofHelper')

contract('NFT Sales with Access Proof Template integration test', (accounts) => {
    const didSeed = testUtils.generateId()
    const checksum = testUtils.generateId()
    const url = 'https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png'
    const royalties = 10 // 10% of royalties in the secondary market
    const cappedAmount = 5
    let token,
        didRegistry,
        nft,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        did,
        nftTemplate,
        nftAgreement,
        escrowCondition,
        lockPaymentCondition,
        accessProofCondition
    const [
        owner,
        deployer,
        artist,
        receiver
    ] = accounts
    const collector1 = receiver
    const governor = accounts[9]

    const numberNFTs = 1
    const amount = 1

    async function setupTest() {
        ({
            didRegistry,
            nft,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager
        } = await deployManagers(
            deployer,
            owner,
            governor
        ))

        token = nft;

        ({
            accessProofCondition
        } = await deployConditions(
            deployer,
            owner,
            agreementStoreManager,
            conditionStoreManager,
            didRegistry,
            token
        ))

        escrowCondition = await testUtils.deploy('NFTEscrowPaymentCondition', [
            owner,
            conditionStoreManager.address], deployer
        )

        lockPaymentCondition = await testUtils.deploy('NFTLockCondition', [
            owner,
            conditionStoreManager.address,
            nft.address], deployer
        )
        nftTemplate = await testUtils.deploy('NFTAccessSwapTemplate', [
            owner,
            agreementStoreManager.address,
            lockPaymentCondition.address,
            escrowCondition.address,
            accessProofCondition.address], deployer
        )

        if (testUtils.deploying) {
            await templateStoreManager.proposeTemplate(nftTemplate.address)
            await templateStoreManager.approveTemplate(nftTemplate.address, { from: owner })
        }
    }

    async function prepareAgreement({
        initAgreementId = testUtils.generateId(),
        receiver,
        amount,
        timeLockAccess = 0,
        timeOutAccess = 0
    } = {}) {
        const orig1 = 222n
        const orig2 = 333n

        const buyerK = 123
        const providerK = 234
        const data = await makeProof(orig1, orig2, buyerK, providerK)
        const { origHash, buyerPub, providerPub } = data

        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])
        const conditionIdLockPayment = await lockPaymentCondition.hashValuesMarked(did, escrowCondition.address, amount, receiver, token.address)
        const fullIdLockPayment = await lockPaymentCondition.generateId(agreementId, conditionIdLockPayment)

        const conditionIdAccess = await accessProofCondition.hashValues(origHash, buyerPub, providerPub)
        const fullIdAccess = await accessProofCondition.generateId(agreementId, conditionIdAccess)

        const conditionIdEscrow = await escrowCondition.hashValues(did, amount, receiver, collector1, escrowCondition.address, token.address, fullIdLockPayment, [fullIdAccess])
        const fullIdEscrow = await escrowCondition.generateId(agreementId, conditionIdEscrow)
        nftAgreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdLockPayment,
                conditionIdEscrow,
                conditionIdAccess
            ],
            timeLocks: [0, 0, 0],
            timeOuts: [0, 0, 0]
        }

        return {
            conditionIds: [
                fullIdLockPayment,
                fullIdEscrow,
                fullIdAccess
            ],
            agreementId,
            did,
            data,
            didSeed,
            agreement: nftAgreement,
            timeLockAccess,
            timeOutAccess,
            checksum,
            url,
            buyerK,
            providerPub,
            origHash
        }
    }

    describe('As an artist I want to register a new artwork', () => {
        it('I want to register a new artwork and tokenize (via NFT). I want to get 10% of royalties', async () => {
            await setupTest()

            did = await didRegistry.hashDID(didSeed, artist)

            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, cappedAmount, royalties, constants.activities.GENERATED, '', { from: artist })
            await didRegistry.mint(did, 5, { from: artist })

            const balance = await nft.balanceOf(artist, did)
            assert.strictEqual(5, balance.toNumber())
        })
    })

    describe('create and fulfill access agreement', function() {
        this.timeout(100000)
        it('should create access agreement', async () => {
            const { agreementId, data, agreement, conditionIds } = await prepareAgreement({ receiver, amount })

            // create agreement
            await nftTemplate.createAgreement(...Object.values(agreement))

            // check state of agreement and conditions
            // expect((await agreementStoreManager.getAgreement(agreementId)).did).to.equal(did)

            const conditionTypes = await nftTemplate.getConditionTypes()
            await Promise.all(conditionIds.map(async (conditionId, i) => {
                const storedCondition = await conditionStoreManager.getCondition(conditionId)
                expect(storedCondition.typeRef).to.equal(conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
            }))

            // lock payment
            const nftBalanceArtistBefore = await nft.balanceOf(artist, did)
            const nftBalanceCollectorBefore = await nft.balanceOf(collector1, did)

            await nft.setApprovalForAll(lockPaymentCondition.address, true, { from: artist })
            await lockPaymentCondition.fulfillMarked(agreementId, did, escrowCondition.address, amount, receiver, token.address, { from: artist })

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            // fulfill access
            await accessProofCondition.fulfill(agreementId, ...Object.values(data), { from: collector1 })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                constants.condition.state.fulfilled)

            // escrow
            await escrowCondition.fulfill(
                agreementId,
                did,
                amount,
                receiver,
                collector1,
                escrowCondition.address,
                token.address,
                conditionIds[0],
                [conditionIds[2]],
                { from: collector1 })

            const { state: state3 } = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(state3.toNumber(), constants.condition.state.fulfilled)

            const nftBalanceArtistAfter = await nft.balanceOf(artist, did)
            const nftBalanceCollectorAfter = await nft.balanceOf(collector1, did)

            assert.strictEqual(nftBalanceArtistAfter.toNumber(), nftBalanceArtistBefore.toNumber() - numberNFTs)
            assert.strictEqual(nftBalanceCollectorAfter.toNumber(), nftBalanceCollectorBefore.toNumber() + numberNFTs)
        })
    })
})
