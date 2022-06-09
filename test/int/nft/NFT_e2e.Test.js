/* eslint-env mocha */
/* eslint-disable no-console */
/* global contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const { getTokenBalance, getCheckpoint } = require('../../helpers/getBalance.js')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')
const deployManagers = require('../../helpers/deployManagers.js')
const deployConditions = require('../../helpers/deployConditions.js')

contract('End to End NFT Scenarios', (accounts) => {
    const royalties = 100000 // 10% of royalties in the secondary market
    const cappedAmount = 5
    const didSeed = testUtils.generateId()
    const didSeed2 = testUtils.generateId()
    let did
    let agreementId

    const checksum = testUtils.generateId()
    const url = 'https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png'

    const [
        artist,
        collector1,
        collector2,
        gallery,
        market,
        someone
    ] = accounts

    const owner = accounts[8]
    const deployer = accounts[8]
    const governor = accounts[9]

    // Configuration of First Sale:
    // Artist -> Collector1, the gallery get a cut (25%)
    const numberNFTs = 1
    const nftPrice = 20
    const amounts = [15, 5]
    const receivers = [artist, gallery]

    // Configuration of Sale in secondary market:
    // Collector1 -> Collector2, the artist get 10% royalties
    const numberNFTs2 = 1
    const nftPrice2 = 100
    const amounts2 = [90, 10]
    const receivers2 = [collector1, artist]

    let
        didRegistry,
        token,
        nft,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        nftSalesTemplate,
        nftAccessTemplate,
        lockPaymentCondition,
        transferCondition,
        escrowCondition,
        nftHolderCondition,
        accessCondition,
        getBalance,
        royaltyManager

    async function setupTest() {
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            nft,
            royaltyManager
        } = await deployManagers(
            deployer,
            owner,
            governor
        ));

        ({
            lockPaymentCondition,
            escrowCondition
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
            market], deployer)

        accessCondition = await testUtils.deploy('NFTAccessCondition', [
            owner,
            conditionStoreManager.address,
            didRegistry.address], deployer)

        nftHolderCondition = await testUtils.deploy('NFTHolderCondition', [
            owner,
            conditionStoreManager.address,
            nft.address], deployer)

        nftSalesTemplate = await testUtils.deploy('NFTSalesTemplate', [
            owner,
            agreementStoreManager.address,
            lockPaymentCondition.address,
            transferCondition.address,
            escrowCondition.address], deployer)

        // Setup NFT Access Template
        nftAccessTemplate = await testUtils.deploy('NFTAccessTemplate', [
            owner,
            agreementStoreManager.address,
            nftHolderCondition.address,
            accessCondition.address], deployer)

        if (testUtils.deploying) {
            await lockPaymentCondition.grantProxyRole(agreementStoreManager.address, { from: owner })
            await transferCondition.grantProxyRole(agreementStoreManager.address, { from: owner })
            await agreementStoreManager.grantProxyRole(nftSalesTemplate.address, { from: owner })
            await conditionStoreManager.grantProxyRole(escrowCondition.address, { from: owner })

            await templateStoreManager.proposeTemplate(nftSalesTemplate.address)
            await templateStoreManager.approveTemplate(nftSalesTemplate.address, { from: owner })

            await templateStoreManager.proposeTemplate(nftAccessTemplate.address)
            await templateStoreManager.approveTemplate(nftAccessTemplate.address, { from: owner })

            // IMPORTANT: Here we give ERC1155 transfer grants to the TransferNFTCondition condition
            await nft.setProxyApproval(transferCondition.address, true, { from: deployer })
        }

        const checkpoint = await getCheckpoint(token, [artist, collector1, collector2, market, gallery, someone, lockPaymentCondition.address, escrowCondition.address])
        getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

        return {
            didRegistry,
            nft
        }
    }

    async function prepareNFTAccessAgreement({
        did,
        initAgreementId = testUtils.generateId(),
        receiver = collector1
    } = {}) {
        // construct agreement
        const conditionIdNFTHolder = await nftHolderCondition.hashValues(did, receiver, 1)
        const conditionIdNFTAccess = await accessCondition.hashValues(did, receiver)
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])

        const nftAccessAgreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdNFTHolder,
                conditionIdNFTAccess
            ],
            timeLocks: [0, 0],
            timeOuts: [0, 0],
            accessConsumer: receiver
        }
        return {
            conditionIds: [
                await nftHolderCondition.generateId(agreementId, conditionIdNFTHolder),
                await accessCondition.generateId(agreementId, conditionIdNFTAccess)
            ],
            agreementId,
            nftAccessAgreement
        }
    }

    async function prepareNFTSaleAgreement({
        did,
        initAgreementId = testUtils.generateId(),
        _amounts = amounts,
        _receivers = receivers,
        _seller = artist,
        _buyer = collector1,
        _numberNFTs = numberNFTs,
        _from = accounts[0]
    } = {}) {
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, _from)
        const conditionIdLockPayment = await lockPaymentCondition.hashValues(did, escrowCondition.address, token.address, _amounts, _receivers)
        const fullIdLockPayment = await lockPaymentCondition.generateId(agreementId, conditionIdLockPayment)
        const conditionIdTransferNFT = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](
            did, _seller, _buyer, _numberNFTs, fullIdLockPayment, nft.address, true)
        const fullIdTransferNFT = await transferCondition.generateId(agreementId, conditionIdTransferNFT)

        const conditionIdEscrow = await escrowCondition.hashValues(did, _amounts, _receivers, _buyer, escrowCondition.address, token.address, fullIdLockPayment, fullIdTransferNFT)
        const fullIdEscrow = await escrowCondition.generateId(agreementId, conditionIdEscrow)

        const lockParams = await lockPaymentCondition.encodeParams(did, escrowCondition.address, token.address, _amounts, _receivers)
        const transferParams = await transferCondition.encodeParams(did, _seller, _buyer, _numberNFTs, fullIdLockPayment, nft.address, true)
        const escrowParams = await escrowCondition.encodeParams(did, _amounts, _receivers, _buyer, escrowCondition.address, token.address, fullIdLockPayment, [fullIdTransferNFT])

        const nftSalesAgreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdLockPayment,
                conditionIdTransferNFT,
                conditionIdEscrow
            ],
            timeLocks: [0, 0, 0],
            timeOuts: [0, 0, 0],
            accessConsumer: _buyer
        }
        const agreementFullfill = {
            initAgreementId,
            did,
            timeLocks: [0, 0, 0],
            timeOuts: [0, 0, 0],
            accessConsumer: _buyer,
            params: [lockParams, transferParams, escrowParams]
        }
        return {
            conditionIds: [
                fullIdLockPayment,
                fullIdTransferNFT,
                fullIdEscrow
            ],
            agreementId,
            nftSalesAgreement,
            agreementFullfill
        }
    }

    describe('As an artist I want to register a new artwork', () => {
        it('I want to register a new artwork and tokenize (via NFT). I want to get 10% of royalties', async () => {
            const { didRegistry, nft } = await setupTest()

            did = await didRegistry.hashDID(didSeed, artist)

            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, cappedAmount, 0, constants.activities.GENERATED, '', { from: artist }
            )
            await didRegistry.setDIDRoyalties(did, royaltyManager.address, { from: artist })
            await royaltyManager.setRoyalty(did, royalties, { from: artist })
            await didRegistry.mint(did, 5, { from: artist })
            await nft.setApprovalForAll(transferCondition.address, true, { from: artist })

            const balance = await nft.balanceOf(artist, did)
            assert.strictEqual(5, balance.toNumber())
            assert.equal(royaltyManager.address, await didRegistry.getDIDRoyaltyScheme(did))
        })
    })

    describe('As collector I want to buy some art', () => {
        let conditionIds
        it('I am setting an agreement for buying a NFT', async () => {
            const data = await prepareNFTSaleAgreement({
                did: did,
                _seller: artist,
                _buyer: collector1
            })
            agreementId = data.agreementId
            conditionIds = data.conditionIds

            // The Collector creates an agreement on-chain for purchasing a specific NFT attached to a DID
            const result = await nftSalesTemplate.createAgreement(...Object.values(data.nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')
        })

        it('I am locking the payment', async () => {
            await token.mint(collector1, nftPrice, { from: owner })
            await token.approve(lockPaymentCondition.address, nftPrice, { from: collector1 })
            await token.approve(escrowCondition.address, nftPrice, { from: collector1 })

            await lockPaymentCondition.fulfill(agreementId, did, escrowCondition.address, token.address, amounts, receivers, { from: collector1 })

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const collector1Balance = await getBalance(token, collector1)
            assert.strictEqual(collector1Balance, 0)
        })

        it('The artist can check the payment and transfer the NFT to the collector', async () => {
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

            const { state } = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            const nftBalanceArtistAfter = await nft.balanceOf(artist, did)
            const nftBalanceCollectorAfter = await nft.balanceOf(collector1, did)

            assert.strictEqual(nftBalanceArtistAfter.toNumber(), nftBalanceArtistBefore.toNumber() - numberNFTs)
            assert.strictEqual(nftBalanceCollectorAfter.toNumber(), nftBalanceCollectorBefore.toNumber() + numberNFTs)
        })

        it('The artist ask and receives the payment', async () => {
            await escrowCondition.fulfill(
                agreementId,
                did,
                amounts,
                receivers,
                collector1,
                escrowCondition.address,
                token.address,
                conditionIds[0],
                conditionIds[1],
                { from: artist })

            const { state } = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.strictEqual(await getBalance(token, collector1), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowCondition.address), 0)
            assert.strictEqual(await getBalance(token, receivers[0]), amounts[0])
            assert.strictEqual(await getBalance(token, receivers[1]), amounts[1])
        })
    })

    describe('As artist I want to give exclusive access to the collectors owning a specific NFT', () => {
        it('As collector I want get access to a exclusive service provided by the artist', async () => {
            const nftAmount = 1
            // Collector1: Create NFT access agreement
            const { nftAccessAgreement, conditionIds, agreementId } = await prepareNFTAccessAgreement({ did: did })

            // The Collector creates an agreement on-chain for purchasing a specific NFT attached to a DID
            const result = await nftAccessTemplate.createAgreement(...Object.values(nftAccessAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            // Collector1: I demonstrate I have the NFT
            await nftHolderCondition.fulfill(
                agreementId, nftAccessAgreement.did, collector1, nftAmount, { from: someone })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.fulfilled)

            // Artist: I give access to the collector1 to the content
            await accessCondition.methods['fulfill(bytes32,bytes32,address)'](
                agreementId,
                nftAccessAgreement.did,
                collector1,
                { from: artist }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)
        })
    })

    describe('As collector1 I want to sell my NFT to a different collector2 for a higher price', () => {
        it('As collector2 I setup an agreement for buying an NFT to collector1', async () => {
            // Collector2: Create NFT sales agreement
            const { agreementFullfill, conditionIds, agreementId: agreementId2 } = await prepareNFTSaleAgreement({
                did: did,
                _amounts: amounts2,
                _receivers: receivers2,
                _seller: collector1,
                _buyer: collector2,
                _numberNFTs: numberNFTs2,
                _from: collector2
            })

            // Collector2: Lock the payment
            await token.mint(collector2, nftPrice2, { from: owner })
            await token.approve(lockPaymentCondition.address, nftPrice2, { from: collector2 })
            await token.approve(escrowCondition.address, nftPrice2, { from: collector2 })

            await nft.setApprovalForAll(transferCondition.address, true, { from: collector1 })
            await nftSalesTemplate.nftSale(nft.address, did, token.address, amounts2[0], { from: collector1 })

            const result = await nftSalesTemplate.createAgreementFulfill(...Object.values(agreementFullfill), { from: collector2 })

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const collector1Balance = await getBalance(token, collector2)
            assert.strictEqual(collector1Balance, 0)

            let condition = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(condition[1].toNumber(), constants.condition.state.fulfilled)

            const nftBalance1 = await nft.balanceOf(collector1, did)
            assert.strictEqual(nftBalance1.toNumber(), numberNFTs - numberNFTs2)

            const nftBalance2 = await nft.balanceOf(collector2, did)
            assert.strictEqual(nftBalance2.toNumber(), numberNFTs2)

            // Collector1 & Artist: Get the payment
            await escrowCondition.fulfill(
                agreementId2,
                did,
                amounts2,
                receivers2,
                collector2,
                escrowCondition.address,
                token.address,
                conditionIds[0],
                conditionIds[1],
                { from: collector1 })

            condition = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(condition[1].toNumber(), constants.condition.state.fulfilled)

            assert.strictEqual(await getBalance(token, collector2), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowCondition.address), 0)
            assert.strictEqual(await getBalance(token, receivers2[0]), amounts2[0])
        })

        it('As artist I want to receive royalties for the NFT I created and was sold in the secondary market', async () => {
            // Artist check the balance and has the royalties
            assert.strictEqual(await getBalance(token, artist), amounts[0] + amounts2[1])
        })

        it('A sale without proper royalties can not happen', async () => {
            const amountsNoRoyalties = [99, 1]
            const receiversNoRoyalties = [collector1, artist]

            // Collector2: Create NFT sales agreement
            const { nftSalesAgreement, agreementId: agreementIdNoRoyalties } = await prepareNFTSaleAgreement({
                did: did,
                _amounts: amountsNoRoyalties,
                _receivers: receiversNoRoyalties,
                _seller: collector1,
                _buyer: collector2,
                _numberNFTs: numberNFTs2
            })

            const result = await nftSalesTemplate.createAgreement(...Object.values(nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            // Collector2: Lock the payment
            await token.mint(collector2, nftPrice2, { from: owner })
            await token.approve(lockPaymentCondition.address, nftPrice2, { from: collector2 })
            await token.approve(escrowCondition.address, nftPrice2, { from: collector2 })

            await assert.isRejected(
                lockPaymentCondition.fulfill(agreementIdNoRoyalties, did, escrowCondition.address, token.address, amountsNoRoyalties, receiversNoRoyalties, { from: collector2 }),
                /Royalties are not satisfied/
            )
        })
    })

    describe('As market I want to be able to transfer nfts and release rewards on behalf of the artist', () => {
        let nftSalesAgreement
        let conditionIds
        it('Artist registers a new artwork and tokenize (via NFT)', async () => {
            const { didRegistry, nft } = await setupTest()

            did = await didRegistry.hashDID(didSeed2, artist)

            await didRegistry.registerMintableDID(
                didSeed2, checksum, [], url, cappedAmount, 10, constants.activities.GENERATED, '', { from: artist })
            await didRegistry.mint(did, 5, { from: artist })
            await nft.setApprovalForAll(transferCondition.address, true, { from: artist })

            const balance = await nft.balanceOf(artist, did)
            assert.strictEqual(5, balance.toNumber())
        })

        it('Collector sets an agreement for buying a NFT', async () => {
            const data = await prepareNFTSaleAgreement({
                did: did,
                agreementId: agreementId,
                _seller: artist,
                _buyer: collector1
            })
            nftSalesAgreement = data.nftSalesAgreement
            conditionIds = data.conditionIds
            agreementId = data.agreementId

            // The Collector creates an agreement on-chain for purchasing a specific NFT attached to a DID
            const result = await nftSalesTemplate.createAgreement(...Object.values(nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')
        })

        it('Collector locks the payment', async () => {
            await token.mint(collector1, nftPrice, { from: owner })
            await token.approve(lockPaymentCondition.address, nftPrice, { from: collector1 })
            await token.approve(escrowCondition.address, nftPrice, { from: collector1 })

            await lockPaymentCondition.fulfill(agreementId, did, escrowCondition.address, token.address, amounts, receivers, { from: collector1 })

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const collector1Balance = await getBalance(token, collector1)
            assert.strictEqual(collector1Balance, 0)
        })

        it('The market can check the payment and can transfer the NFT to the collector', async () => {
            const nftBalanceArtistBefore = await nft.balanceOf(artist, did)
            const nftBalanceCollectorBefore = await nft.balanceOf(collector1, did)

            await nft.setApprovalForAll(market, true, { from: artist })
            await transferCondition.fulfillForDelegate(
                agreementId,
                did,
                artist,
                collector1,
                numberNFTs,
                conditionIds[0],
                true,
                { from: market }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            const nftBalanceArtistAfter = await nft.balanceOf(artist, did)
            const nftBalanceCollectorAfter = await nft.balanceOf(collector1, did)

            assert.strictEqual(nftBalanceArtistAfter.toNumber(), nftBalanceArtistBefore.toNumber() - numberNFTs)
            assert.strictEqual(nftBalanceCollectorAfter.toNumber(), nftBalanceCollectorBefore.toNumber() + numberNFTs)
        })

        it('The market can release the payment to the artist', async () => {
            await escrowCondition.fulfill(
                agreementId,
                did,
                amounts,
                receivers,
                collector1,
                escrowCondition.address,
                token.address,
                conditionIds[0],
                conditionIds[1],
                { from: market })

            const { state } = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.strictEqual(await getBalance(token, collector1), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowCondition.address), 0)
            assert.strictEqual(await getBalance(token, receivers[0]), amounts[0])
            assert.strictEqual(await getBalance(token, receivers[1]), amounts[1])
        })
    })
})
