/* eslint-env mocha */
/* eslint-disable no-console */
/* global contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const { ethers } = require('hardhat')
const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

const { getTokenBalance, getCheckpoint } = require('../../helpers/getBalance.js')
const deployManagers = require('../../helpers/deployManagers.js')
const deployConditions = require('../../helpers/deployConditions.js')

contract('End to End NFT721 Scenarios', (accounts) => {
    const royalties = 10 // 10% of royalties in the secondary market
    const didSeed = testUtils.generateId()
    let did
    let agreementId
    const checksum = testUtils.generateId()
    const url = 'https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png'
    const transfer_nft = false // If true the NFT is transferred but if false is minted

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
        getBalance

    async function setupTest() {
        let nft721
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            nft721
        } = await deployManagers(
            deployer,
            owner,
            governor
        ))
        nft = nft721;
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

        transferCondition = await testUtils.deploy('TransferNFT721Condition', [owner,
            conditionStoreManager.address,
            didRegistry.address,
            nft.address,
            market], deployer)

        accessCondition = await testUtils.deploy('NFTAccessCondition', [
            owner,
            conditionStoreManager.address,
            didRegistry.address], deployer)

        nftHolderCondition = await testUtils.deploy('NFT721HolderCondition', [
            owner,
            conditionStoreManager.address
        ], deployer)

        nftSalesTemplate = await testUtils.deploy('NFT721SalesTemplate', [
            owner,
            agreementStoreManager.address,
            lockPaymentCondition.address,
            transferCondition.address,
            escrowCondition.address], deployer)

        // Setup NFT Access Template
        nftAccessTemplate = await testUtils.deploy('NFT721AccessTemplate', [
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

            // IMPORTANT: Here we give ERC-721 transfer grants to the TransferNFTCondition condition
            await nft.setProxyApproval(transferCondition.address, true, { from: deployer })
        }

        const checkpoint = await getCheckpoint(token, [artist, collector1, collector2, gallery, someone, lockPaymentCondition.address, escrowCondition.address])
        getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

        return {
            didRegistry,
            nft
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
        const conditionIdTransferNFT = await transferCondition.hashValues(did, _seller, _buyer, _numberNFTs, fullIdLockPayment, nft.address, transfer_nft)
        const fullIdTransferNFT = await transferCondition.generateId(agreementId, conditionIdTransferNFT)

        const conditionIdEscrow = await escrowCondition.hashValues(did, _amounts, _receivers, _buyer, escrowCondition.address, token.address, fullIdLockPayment, fullIdTransferNFT)
        const fullIdEscrow = await escrowCondition.generateId(agreementId, conditionIdEscrow)

        const lockParams = await lockPaymentCondition.encodeParams(did, escrowCondition.address, token.address, _amounts, _receivers)
        const transferParams = await transferCondition.encodeParams(did, _seller, _buyer, _numberNFTs, fullIdLockPayment, nft.address, transfer_nft)
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
            agreementFullfill,
            nftSalesAgreement
        }
    }

    describe('As market I want to be able to sell Subscriptions based in NFTs ERC-721', () => {
        let nft721
        let nftSubscriptionAddress
        let nftSalesAgreement
        let conditionIds
        let currentBlockNumber
        const blocksDuration = 5

        it('Artist registers a new asset and tokenize (via NFT)', async () => {
            const { didRegistry, nft } = await setupTest()
            nft721 = nft
            nftSubscriptionAddress = nft721.address
            console.log('SubscriptionERC721 contract deployed to ' + nftSubscriptionAddress)
            await nft.addMinter(transferCondition.address, { from: owner })

            did = await didRegistry.hashDID(didSeed, artist)

            await didRegistry.registerMintableDID721(
                didSeed, checksum, [], url, royalties, false, constants.activities.GENERATED, '', { from: artist })
            await nft721.setApprovalForAll(transferCondition.address, true, { from: artist })
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
            await nft721.setApprovalForAll(market, true, { from: artist })
            currentBlockNumber = await ethers.provider.getBlockNumber()

            await transferCondition.methods['fulfillForDelegate(bytes32,bytes32,address,address,uint256,bytes32,bool,address,uint256)'](
                agreementId,
                did,
                artist,
                collector1,
                numberNFTs,
                conditionIds[0],
                transfer_nft,
                nftSubscriptionAddress,
                currentBlockNumber + blocksDuration,
                { from: market }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.strictEqual(collector1, await nft721.ownerOf(did))
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
