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
const { getTokenBalance, getCheckpoint } = require('../../helpers/getBalance.js')

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
        transferCondition,
        nftSalesTemplate,
        escrowCondition,
        lockPaymentCondition,
        accessProofCondition,
        getBalance
    const [
        artist,
        receiver,
        gallery,
        market
    ] = accounts
    const owner = accounts[8]
    const deployer = accounts[8]
    const governor = accounts[9]

    const collector1 = receiver

    const numberNFTs = 1
    const nftPrice = 20
    const amounts = [15, 5]
    const receivers = [artist, gallery]

    async function setupTest() {
        ({
            token,
            didRegistry,
            nft,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager
        } = await deployManagers(
            deployer,
            owner,
            governor
        ));

        ({
            accessProofCondition,
            escrowPaymentCondition: escrowCondition,
            lockPaymentCondition,
            transferCondition
        } = await deployConditions(
            deployer,
            owner,
            agreementStoreManager,
            conditionStoreManager,
            didRegistry,
            token
        ))
        transferCondition = await testUtils.deploy('TransferNFTCondition', [owner,
            conditionStoreManager.address,
            didRegistry.address,
            nft.address,
            market], deployer
        )
        nftSalesTemplate = await testUtils.deploy('NFTSalesWithAccessTemplate', [
            owner,
            agreementStoreManager.address,
            lockPaymentCondition.address,
            transferCondition.address,
            escrowCondition.address,
            accessProofCondition.address], deployer
        )

        if (testUtils.deploying) {
            await nft.setProxyApproval(transferCondition.address, true, { from: deployer })
            await templateStoreManager.proposeTemplate(nftSalesTemplate.address)
            await templateStoreManager.approveTemplate(nftSalesTemplate.address, { from: owner })
        }
        const checkpoint = await getCheckpoint(token, [artist, collector1, market, gallery, lockPaymentCondition.address, escrowCondition.address])
        getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)
    }

    async function prepareAgreement({
        initAgreementId = testUtils.generateId(),
        receivers,
        amounts,
        timeLockAccess = 0,
        timeOutAccess = 0
    } = {}) {
        const orig1 = 222n
        const orig2 = 333n

        const buyerK = 123
        const providerK = 234

        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])

        const data = await makeProof(orig1, orig2, buyerK, providerK)
        const { origHash, buyerPub, providerPub } = data
        const conditionIdLockPayment = await lockPaymentCondition.hashValues(did, escrowCondition.address, token.address, amounts, receivers)
        const fullIdLockPayment = await lockPaymentCondition.generateId(agreementId, conditionIdLockPayment)

        const conditionIdTransferNFT = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
            did, artist, receiver, numberNFTs, fullIdLockPayment, nft.address, true)
        const fullIdTransferNFT = await transferCondition.generateId(agreementId, conditionIdTransferNFT)

        const conditionIdAccess = await accessProofCondition.hashValues(origHash, buyerPub, providerPub)
        const fullIdAccess = await accessProofCondition.generateId(agreementId, conditionIdAccess)

        const conditionIdEscrow = await escrowCondition.hashValuesMulti(did, amounts, receivers, collector1, escrowCondition.address, token.address, fullIdLockPayment, [fullIdTransferNFT, fullIdAccess])
        const fullIdEscrow = await escrowCondition.generateId(agreementId, conditionIdEscrow)

        const nftSalesAgreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdLockPayment,
                conditionIdTransferNFT,
                conditionIdEscrow,
                conditionIdAccess
            ],
            timeLocks: [0, 0, 0, 0],
            timeOuts: [0, 0, 0, 0]
        }

        return {
            conditionIds: [
                fullIdLockPayment,
                fullIdTransferNFT,
                fullIdEscrow,
                fullIdAccess
            ],
            agreementId,
            did,
            data,
            didSeed,
            agreement: nftSalesAgreement,
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

            await nft.safeTransferFrom(artist, receiver, did, 2, '0x', { from: artist })
        })
    })

    describe('create and fulfill access agreement', function() {
        this.timeout(100000)
        it('should create access agreement', async () => {
            const { agreementId, data, agreement, conditionIds } = await prepareAgreement({ receivers, amounts })

            // create agreement
            await nftSalesTemplate.createAgreement(...Object.values(agreement))

            // check state of agreement and conditions
            // expect((await agreementStoreManager.getAgreement(agreementId)).did).to.equal(did)

            const conditionTypes = await nftSalesTemplate.getConditionTypes()
            await Promise.all(conditionIds.map(async (conditionId, i) => {
                const storedCondition = await conditionStoreManager.getCondition(conditionId)
                expect(storedCondition.typeRef).to.equal(conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
            }))

            // lock payment
            await token.mint(collector1, nftPrice, { from: owner })
            await token.approve(lockPaymentCondition.address, nftPrice, { from: collector1 })
            await token.approve(escrowCondition.address, nftPrice, { from: collector1 })

            await lockPaymentCondition.fulfill(agreementId, did, escrowCondition.address, token.address, amounts, receivers, { from: collector1 })

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const collector1Balance = await getBalance(token, collector1)
            assert.strictEqual(collector1Balance, 0)

            // transfer
            const nftBalanceArtistBefore = await nft.balanceOf(artist, did)
            const nftBalanceCollectorBefore = await nft.balanceOf(collector1, did)

            await nft.setApprovalForAll(transferCondition.address, true, { from: artist })
            await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32)'](
                agreementId,
                did,
                collector1,
                numberNFTs,
                conditionIds[0],
                { from: artist })
            await nft.setApprovalForAll(transferCondition.address, false, { from: artist })

            const { state: state2 } = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(state2.toNumber(), constants.condition.state.fulfilled)

            const nftBalanceArtistAfter = await nft.balanceOf(artist, did)
            const nftBalanceCollectorAfter = await nft.balanceOf(collector1, did)

            assert.strictEqual(nftBalanceArtistAfter.toNumber(), nftBalanceArtistBefore.toNumber() - numberNFTs)
            assert.strictEqual(nftBalanceCollectorAfter.toNumber(), nftBalanceCollectorBefore.toNumber() + numberNFTs)

            // fulfill access
            await accessProofCondition.fulfill(agreementId, ...Object.values(data), { from: artist })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            // escrow
            await escrowCondition.fulfillMulti(
                agreementId,
                did,
                amounts,
                receivers,
                collector1,
                escrowCondition.address,
                token.address,
                conditionIds[0],
                [conditionIds[1], conditionIds[3]],
                { from: artist })

            const { state: state3 } = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(state3.toNumber(), constants.condition.state.fulfilled)

            assert.strictEqual(await getBalance(token, collector1), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowCondition.address), 0)
            assert.strictEqual(await getBalance(token, receivers[0]), amounts[0])
            assert.strictEqual(await getBalance(token, receivers[1]), amounts[1])
        })
    })
})
