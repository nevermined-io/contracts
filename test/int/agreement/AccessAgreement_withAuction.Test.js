/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const AccessTemplate = artifacts.require('AccessTemplate')
const EnglishAuction = artifacts.require('EnglishAuction')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const { getBalance } = require('../../helpers/getBalance.js')
const increaseTime = require('../../helpers/increaseTime.js')
const deployConditions = require('../../helpers/deployConditions.js')
const deployManagers = require('../../helpers/deployManagers.js')

contract('Access with Auction integration test', (accounts) => {
    const web3 = global.web3

    //    const deployer = accounts[0]
    //    const owner = accounts[1]
    const manager = accounts[2]
    const creator = accounts[3]
    const bidder1 = accounts[4]
    const bidder2 = accounts[5]
    const bidder3 = accounts[6]

    const auctionId = testUtils.generateId()
    const initAgreementId = testUtils.generateId()
    let agreementId
    const escrowAmounts = [10, 4]
    const totalAmount = escrowAmounts[0] + escrowAmounts[1]
    const receivers = [creator, manager]
    const floor = 10
    const auctionDuration = 10
    const hash = ''

    let token,
        auctionContract,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        conditionIds,
        accessTemplate,
        accessCondition,
        lockPaymentCondition,
        escrowPaymentCondition,
        agreement,
        did,
        startBlock,
        endBlock,
        creatorBalanceBeginning,
        bidder2BalanceBeginning

    async function setupTest({
        deployer = accounts[0],
        owner = accounts[1]
    } = {}) {
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager
        } = await deployManagers(
            deployer,
            owner
        ));

        ({
            accessCondition,
            lockPaymentCondition,
            escrowPaymentCondition
        } = await deployConditions(
            deployer,
            owner,
            agreementStoreManager,
            conditionStoreManager,
            didRegistry,
            token
        ))

        auctionContract = await EnglishAuction.new({ from: deployer })

        await auctionContract.methods['initialize(address)'](owner, { from: deployer })
        await auctionContract.addNVMAgreementRole(lockPaymentCondition.address, { from: owner })

        // We whitelist the auction contract
        await lockPaymentCondition.grantExternalContractRole(
            auctionContract.address, { from: owner })

        accessTemplate = await AccessTemplate.new()
        await accessTemplate.methods['initialize(address,address,address,address,address,address)'](
            owner,
            agreementStoreManager.address,
            didRegistry.address,
            accessCondition.address,
            lockPaymentCondition.address,
            escrowPaymentCondition.address,
            { from: deployer }
        )

        // propose and approve template
        const templateId = accessTemplate.address
        await templateStoreManager.proposeTemplate(templateId)
        await templateStoreManager.approveTemplate(templateId, { from: owner })

        // Lets distribute some tokens
        await token.mint(bidder1, floor * 100, { from: owner })
        await token.mint(bidder2, floor * 100, { from: owner })
        await token.mint(bidder3, floor * 100, { from: owner })
        await token.approve(auctionContract.address, floor * 100, { from: bidder1 })
        await token.approve(auctionContract.address, floor * 100, { from: bidder2 })
        await token.approve(auctionContract.address, floor * 100, { from: bidder3 })

        creatorBalanceBeginning = await getBalance(token, creator)
        bidder2BalanceBeginning = await getBalance(token, bidder2)

        return {
            templateId,
            owner
        }
    }

    async function prepareAccessAgreement({
        didSeed = testUtils.generateId(),
        url = constants.registry.url,
        checksum = constants.bytes32.one
    } = {}) {
        did = await didRegistry.hashDID(didSeed, creator)
        agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])
        // generate IDs from attributes
        //        console.log('Whats my agreement id: ', agreementId)
        const conditionIdLock = await lockPaymentCondition.hashValues(
            did,
            escrowPaymentCondition.address,
            token.address,
            escrowAmounts,
            receivers)
        const fullConditionIdLock = await lockPaymentCondition.generateId(agreementId, conditionIdLock)
        const conditionIdAccess = await accessCondition.hashValues(did, receivers[0])
        const fullConditionIdAccess = await accessCondition.generateId(agreementId, conditionIdAccess)
        const conditionIdEscrow = await escrowPaymentCondition.hashValues(
            did,
            escrowAmounts,
            receivers,
            bidder1,
            escrowPaymentCondition.address,
            token.address,
            fullConditionIdLock,
            fullConditionIdAccess)
        const fullConditionIdEscrow = await escrowPaymentCondition.generateId(agreementId, conditionIdEscrow)

        conditionIds = [
            fullConditionIdAccess,
            fullConditionIdLock,
            fullConditionIdEscrow
        ]

        // construct agreement
        agreement = {
            did: did,
            conditionIds: [
                conditionIdAccess,
                conditionIdLock,
                conditionIdEscrow
            ],
            timeLocks: [0, 0, 0],
            timeOuts: [0, 0, 0],
            consumer: creator
        }
        return {
            did,
            didSeed,
            agreement,
            receivers,
            escrowAmounts,
            checksum,
            url
        }
    }

    describe('Create and fulfill Access Agreement', () => {
        it('should create access agreement', async () => {
            await setupTest()

            // prepare: nft agreement
            const { didSeed, agreement, checksum, url } = await prepareAccessAgreement({ timeOutAccess: 10 })

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, 10, 0, constants.activities.GENERATED, '', { from: creator })

            // create agreement
            await accessTemplate.createAgreement(initAgreementId, ...Object.values(agreement))
        })

        it('the auction takes place', async () => {
            const currentBlockNumber = await ethers.provider.getBlockNumber()
            startBlock = currentBlockNumber + 3
            endBlock = startBlock + auctionDuration

            const result = await auctionContract.create(auctionId, did, floor, startBlock, endBlock, token.address, hash,
                { from: creator })

            testUtils.assertEmitted(
                result,
                1,
                'AuctionCreated'
            )

            // wait: for start
            await increaseTime.mineBlocks(web3, 3)
            // bidders place their bids
            await auctionContract.placeERC20Bid(auctionId, floor + 1, { from: bidder1 })
            await auctionContract.placeERC20Bid(auctionId, floor + 2, { from: bidder2 })
            await auctionContract.placeERC20Bid(auctionId, 3, { from: bidder1 })

            // auction state checks
            const { state, price, whoCanClaim } = await auctionContract.getStatus(auctionId)
            assert.strictEqual(2, state.toNumber()) // In progress
            assert.strictEqual(floor + 1 + 3, price.toNumber())
            assert.strictEqual(bidder1, whoCanClaim)

            // we wait for finishing the auction
            await increaseTime.mineBlocks(web3, 10)

            const withdrawResult = await auctionContract.withdraw(auctionId, bidder2, { from: bidder2 })

            testUtils.assertEmitted(
                withdrawResult,
                1,
                'AuctionWithdrawal'
            )

            const bidder2BalanceAfter = await getBalance(token, bidder2)
            assert.strictEqual(bidder2BalanceBeginning, bidder2BalanceAfter)
        })

        it('bidder winning the auction should be able to lock', async () => {
            const auctionBalanceBefore = await getBalance(token, auctionContract.address)
            const lockBalanceBefore = await getBalance(token, lockPaymentCondition.address)
            const escrowBalanceBefore = await getBalance(token, escrowPaymentCondition.address)

            await lockPaymentCondition.fulfillExternal(
                agreementId,
                did,
                escrowPaymentCondition.address,
                auctionContract.address,
                auctionId,
                escrowAmounts,
                receivers,
                { from: bidder1 }
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            assert.strictEqual(await getBalance(token, auctionContract.address), auctionBalanceBefore - totalAmount)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), lockBalanceBefore)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), escrowBalanceBefore + totalAmount)
        })

        it('bidder winning the auction can not get the funds more than once', async () => {
            await assert.isRejected(
                lockPaymentCondition.fulfillExternal(
                    agreementId,
                    did,
                    escrowPaymentCondition.address,
                    auctionContract.address,
                    auctionId,
                    escrowAmounts,
                    receivers,
                    { from: bidder1 }
                ),
                'AbstractAuction: Zero amount'
            )
        })

        it('at this point the auction should be finished', async () => {
            const { state, price, whoCanClaim } = await auctionContract.getStatus(auctionId)
            assert.strictEqual(1, state.toNumber()) // Finished
            assert.strictEqual(totalAmount, price.toNumber())
            assert.strictEqual(bidder1, whoCanClaim)
        })

        it('the LockPayment was fulfilled using the auction winner funds and access condition can be fulfilled', async () => {
            await accessCondition.fulfill(
                agreementId, did, creator, { from: creator })

            assert.strictEqual( // Lock Condition
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)
            assert.strictEqual( // Access Condition
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.fulfilled)
        })

        it('escrow payment can be fulfilled and funds distributed', async () => {
            const escrowBalanceBefore = await getBalance(token, escrowPaymentCondition.address)

            await escrowPaymentCondition.fulfill(
                agreementId,
                did,
                escrowAmounts,
                receivers,
                bidder1,
                escrowPaymentCondition.address,
                token.address,
                conditionIds[1],
                conditionIds[0],
                { from: creator }
            )
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                constants.condition.state.fulfilled
            )

            assert.strictEqual(
                await getBalance(token, escrowPaymentCondition.address), escrowBalanceBefore - totalAmount)

            assert.strictEqual(
                await getBalance(token, creator), creatorBalanceBeginning + escrowAmounts[0])
        })
    })
})
