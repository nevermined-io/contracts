/* eslint-env mocha */
/* eslint-disable no-console */
/* global contract, describe, it, BigInt */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')
const { getETHBalanceBN } = require('../../helpers/getBalance')
const web3Utils = require('web3-utils')

const deployManagers = require('../../helpers/deployManagers.js')
const deployConditions = require('../../helpers/deployConditions.js')

const toEth = (value) => {
    return Number(web3Utils.fromWei(value.toString(10), 'ether'))
}

contract('End to End NFT Scenarios (with Ether)', (accounts) => {
    const royalties = 10 // 10% of royalties in the secondary market
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

    const governor = accounts[9]
    const owner = accounts[8]
    const deployer = accounts[8]

    // Configuration of First Sale:
    // Artist -> Collector1, the gallery get a cut (25%)
    const numberNFTs = 1

    const marketplaceFee = 2000
    const marketplaceAddress = owner
    let nftPrice = 2
    let amounts = [1.1, 0.5, 0.4]

    const receivers = [artist, gallery, owner]

    // Configuration of Sale in secondary market:
    // Collector1 -> Collector2, the artist get 10% royalties
    const numberNFTs2 = 1

    let nftPrice2 = 5
    let amounts2 = [3, 1, 1]

    const receivers2 = [collector1, artist, owner]

    let
        didRegistry,
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
        accessCondition

    async function setupTest() {
        let nvmConfig, token;
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            nvmConfig,
            nft
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

        await nvmConfig.setMarketplaceFees(
            marketplaceFee,
            marketplaceAddress,
            { from: governor }
        )

        if (testUtils.deploying) {
            // IMPORTANT: Here we give ERC1155 transfer grants to the TransferNFTCondition condition
            await nft.setProxyApproval(transferCondition.address, true, { from: deployer })

            await conditionStoreManager.grantProxyRole(
                escrowCondition.address,
                { from: owner }
            )
            await agreementStoreManager.grantProxyRole(nftSalesTemplate.address, { from: owner })
            await lockPaymentCondition.grantProxyRole(agreementStoreManager.address, { from: owner })

            await templateStoreManager.proposeTemplate(nftSalesTemplate.address)
            await templateStoreManager.approveTemplate(nftSalesTemplate.address, { from: owner })

            await templateStoreManager.proposeTemplate(nftAccessTemplate.address)
            await templateStoreManager.approveTemplate(nftAccessTemplate.address, { from: owner })
        }

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
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])
        const conditionIdNFTHolder = await nftHolderCondition.hashValues(did, receiver, 1)
        const conditionIdNFTAccess = await accessCondition.hashValues(did, receiver)

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
        const conditionIdLockPayment = await lockPaymentCondition.hashValues(did, escrowCondition.address, constants.address.zero, _amounts.map(a => String(a)), _receivers)
        const fullIdLockPayment = await lockPaymentCondition.generateId(agreementId, conditionIdLockPayment)
        const conditionIdTransferNFT = await transferCondition.methods['hashValues(bytes32,address,address,uint256,bytes32,address,bool)'](did, _seller, _buyer, _numberNFTs, fullIdLockPayment, nft.address, true)
        const fullIdTransferNFT = await transferCondition.generateId(agreementId, conditionIdTransferNFT)

        const conditionIdEscrow = await escrowCondition.hashValues(did, _amounts.map(a => String(a)), _receivers, _buyer, escrowCondition.address, constants.address.zero, fullIdLockPayment, fullIdTransferNFT)
        const fullIdEscrow = await escrowCondition.generateId(agreementId, conditionIdEscrow)

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
        return {
            conditionIds: [
                fullIdLockPayment,
                fullIdTransferNFT,
                fullIdEscrow
            ],
            agreementId,
            nftSalesAgreement
        }
    }

    before(() => {
        nftPrice = Number(web3Utils.toWei(String(nftPrice), 'ether'))
        amounts = amounts.map(v => Number(web3Utils.toWei(String(v), 'ether')))

        nftPrice2 = web3Utils.toWei(String(nftPrice2), 'ether')
        amounts2 = amounts2.map(v => web3Utils.toWei(String(v), 'ether'))
    })

    describe('As an artist I want to register a new artwork', () => {
        it('I want to register a new artwork and tokenize (via NFT). I want to get 10% of royalties', async () => {
            const { didRegistry, nft } = await setupTest()

            did = await didRegistry.hashDID(didSeed, artist)

            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, cappedAmount, royalties, constants.activities.GENERATED, '', { from: artist })
            await didRegistry.mint(did, 5, { from: artist })
            await nft.setApprovalForAll(transferCondition.address, true, { from: artist })

            const balance = await nft.balanceOf(artist, did)
            assert.strictEqual(5, balance.toNumber())
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

            conditionIds = data.conditionIds
            agreementId = data.agreementId

            // The Collector creates an agreement on-chain for purchasing a specific NFT attached to a DID
            const result = await nftSalesTemplate.createAgreement(...Object.values(data.nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')
        })

        it('fails because i forgot to add eth "value" to the transactions', async () => {
            await assert.isRejected(
                lockPaymentCondition.fulfill(
                    agreementId, did, escrowCondition.address, constants.address.zero, amounts.map(a => String(a)), receivers,
                    { from: collector1 }
                ),
                'Transaction value does not match amount'
            )
        })

        it('I am locking the payment', async () => {
            const collector1Before = toEth(await getETHBalanceBN(collector1))

            await lockPaymentCondition.fulfill(
                agreementId, did, escrowCondition.address, constants.address.zero, amounts.map(a => String(a)), receivers,
                { from: collector1, value: nftPrice }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.closeTo(
                toEth(await getETHBalanceBN(collector1)),
                collector1Before - toEth(nftPrice),
                0.01
            )
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
            const receiver1Before = toEth(await getETHBalanceBN(receivers[0]))
            const receiver2Before = toEth(await getETHBalanceBN(receivers[1]))

            await escrowCondition.fulfill(
                agreementId,
                did,
                amounts.map(a => String(a)),
                receivers,
                collector1,
                escrowCondition.address,
                constants.address.zero,
                conditionIds[0],
                conditionIds[1],
                { from: artist }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.closeTo(
                toEth(await getETHBalanceBN(receivers[0])),
                receiver1Before + toEth(amounts[0]),
                0.01
            )
            assert.closeTo(
                toEth(await getETHBalanceBN(receivers[1])),
                receiver2Before + toEth(amounts[1]),
                0.01
            )
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
            const { nftSalesAgreement, conditionIds, agreementId: agreementId2 } = await prepareNFTSaleAgreement({
                did,
                _amounts: amounts2,
                _receivers: receivers2,
                _seller: collector1,
                _buyer: collector2,
                _numberNFTs: numberNFTs2,
                _from: collector2
            })

            const extendedAgreement = {
                ...nftSalesAgreement,
                _idx: 0,
                _receiverAddress: escrowCondition.address,
                _tokenAddress: constants.address.zero,
                _amounts: amounts2,
                _receivers: receivers2
            }

            const collector2Before = toEth(await getETHBalanceBN(collector2))

            const totalAmount = amounts2.reduce((a, b) => a + BigInt(b), 0n)

            const result = await nftSalesTemplate.createAgreementAndPayEscrow(
                ...Object.values(extendedAgreement), { value: totalAmount.toString(), from: collector2 })

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            assert.closeTo(
                toEth(await getETHBalanceBN(collector2)),
                collector2Before - toEth(nftPrice2),
                0.01
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            // Collector1: Transfer the NFT
            await nft.setApprovalForAll(transferCondition.address, true, { from: collector1 })
            await transferCondition.methods['fulfill(bytes32,bytes32,address,uint256,bytes32)'](
                agreementId2,
                did,
                collector2,
                numberNFTs2,
                conditionIds[0],
                { from: collector1 })
            await nft.setApprovalForAll(transferCondition.address, true, { from: collector1 })

            let condition = await conditionStoreManager.getCondition(conditionIds[1])
            assert.strictEqual(condition[1].toNumber(), constants.condition.state.fulfilled)

            const nftBalance1 = await nft.balanceOf(collector1, did)
            assert.strictEqual(nftBalance1.toNumber(), numberNFTs - numberNFTs2)

            const nftBalance2 = await nft.balanceOf(collector2, did)
            assert.strictEqual(nftBalance2.toNumber(), numberNFTs2)

            const receiver1Before = toEth(await getETHBalanceBN(receivers2[0]))
            const receiver2Before = toEth(await getETHBalanceBN(receivers2[1]))

            // Collector1 & Artist: Get the payment
            await escrowCondition.fulfill(
                agreementId2,
                did,
                amounts2.map(a => String(a)),
                receivers2,
                collector2,
                escrowCondition.address,
                constants.address.zero,
                conditionIds[0],
                conditionIds[1],
                { from: collector1 })

            condition = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(condition[1].toNumber(), constants.condition.state.fulfilled)

            assert.closeTo(
                toEth(await getETHBalanceBN(receivers2[0])),
                receiver1Before + toEth(amounts2[0]),
                0.01
            )
            assert.closeTo(
                toEth(await getETHBalanceBN(receivers2[1])),
                receiver2Before + toEth(amounts2[1]),
                0.01
            )
        })

        it('As artist I want to receive royalties for the NFT I created and was sold in the secondary market', async () => {
            // Artist check the balance and has the royalties
            // todo
        })

        it.skip('A sale without proper royalties can not happen', async () => {
            const agreementIdNoRoyalties = testUtils.generateId()
            const amountsNoRoyalties = [99, 1]
            const receiversNoRoyalties = [collector1, artist]

            // Collector2: Create NFT sales agreement
            const { nftSalesAgreement } = await prepareNFTSaleAgreement({
                did: did,
                agreementId: agreementIdNoRoyalties,
                _amounts: amountsNoRoyalties,
                _receivers: receiversNoRoyalties,
                _seller: collector1,
                _buyer: collector2,
                _numberNFTs: numberNFTs2
            })

            const result = await nftSalesTemplate.createAgreement(...Object.values(nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')

            // Collector2: Lock the payment
            await assert.isRejected(
                lockPaymentCondition.fulfill(
                    agreementIdNoRoyalties, did, escrowCondition.address, constants.address.zero, amountsNoRoyalties, receiversNoRoyalties,
                    { from: collector2 }
                ),
                /Royalties are not satisfied/
            )
        })
    })

    describe('As market I want to be able to transfer nfts and release rewards on behalf of the artist', () => {
        let conditionIds
        it('Artist registers a new artwork and tokenize (via NFT)', async () => {
            const { didRegistry, nft } = await setupTest()

            did = await didRegistry.hashDID(didSeed2, artist)

            await didRegistry.registerMintableDID(
                didSeed2, checksum, [], url, cappedAmount, royalties, constants.activities.GENERATED, '', { from: artist })
            await didRegistry.mint(did, 5, { from: artist })
            await nft.setApprovalForAll(transferCondition.address, true, { from: artist })

            const balance = await nft.balanceOf(artist, did)
            assert.strictEqual(5, balance.toNumber())
        })

        it('Collector sets an agreement for buying a NFT', async () => {
            const data = await prepareNFTSaleAgreement({
                did: did,
                _seller: artist,
                _buyer: collector1
            })
            conditionIds = data.conditionIds
            agreementId = data.agreementId

            // The Collector creates an agreement on-chain for purchasing a specific NFT attached to a DID
            const result = await nftSalesTemplate.createAgreement(...Object.values(data.nftSalesAgreement))

            testUtils.assertEmitted(result, 1, 'AgreementCreated')
        })

        it('fails because i forgot to add eth "value" to the transactions', async () => {
            await assert.isRejected(
                lockPaymentCondition.fulfill(
                    agreementId, did, escrowCondition.address, constants.address.zero, amounts.map(a => String(a)), receivers,
                    { from: collector1 }
                ),
                'Transaction value does not match amount'
            )
        })

        it('Collector locks the payment', async () => {
            const collector1Before = toEth(await getETHBalanceBN(collector1))

            await lockPaymentCondition.fulfill(
                agreementId, did, escrowCondition.address, constants.address.zero, amounts.map(a => String(a)), receivers,
                { from: collector1, value: nftPrice }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[0])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.closeTo(
                toEth(await getETHBalanceBN(collector1)),
                collector1Before - toEth(nftPrice),
                0.01
            )
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
            const receiver1Before = toEth(await getETHBalanceBN(receivers[0]))
            const receiver2Before = toEth(await getETHBalanceBN(receivers[1]))

            await escrowCondition.fulfill(
                agreementId,
                did,
                amounts.map(a => String(a)),
                receivers,
                collector1,
                escrowCondition.address,
                constants.address.zero,
                conditionIds[0],
                conditionIds[1],
                { from: market }
            )

            const { state } = await conditionStoreManager.getCondition(conditionIds[2])
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)

            assert.closeTo(
                toEth(await getETHBalanceBN(receivers[0])),
                receiver1Before + toEth(amounts[0]),
                0.01
            )

            assert.closeTo(
                toEth(await getETHBalanceBN(receivers[1])),
                receiver2Before + toEth(amounts[1]),
                0.01
            )
        })
    })
})
