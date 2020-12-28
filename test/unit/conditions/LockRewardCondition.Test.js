/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const EpochLibrary = artifacts.require('EpochLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const NeverminedToken = artifacts.require('NeverminedToken')
const LockRewardCondition = artifacts.require('LockRewardCondition')

const constants = require('../../helpers/constants.js')
const getBalance = require('../../helpers/getBalance.js')
const testUtils = require('../../helpers/utils.js')

contract('LockRewardCondition', (accounts) => {
    let epochLibrary
    let conditionStoreManager
    let token
    let lockRewardCondition

    //    const conditionId = constants.bytes32.one
    //    const conditionType = constants.address.dummy
    const owner = accounts[1]
    const createRole = accounts[0]

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!conditionStoreManager) {
            epochLibrary = await EpochLibrary.new()
            await ConditionStoreManager.link('EpochLibrary', epochLibrary.address)

            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                owner,
                { from: owner }
            )

            await conditionStoreManager.delegateCreateRole(
                createRole,
                { from: owner }
            )

            token = await NeverminedToken.new()
            await token.initialize(owner, owner)

            lockRewardCondition = await LockRewardCondition.new()

            await lockRewardCondition.initialize(
                owner,
                conditionStoreManager.address,
                token.address,
                { from: createRole }
            )
        }
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            const epochLibrary = await EpochLibrary.new()
            await ConditionStoreManager.link('EpochLibrary', epochLibrary.address)

            const conditionStoreManager = await ConditionStoreManager.new()
            const token = await NeverminedToken.new()
            const lockRewardCondition = await LockRewardCondition.new()

            await lockRewardCondition.initialize(
                accounts[0],
                conditionStoreManager.address,
                token.address,
                { from: accounts[0] })
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist', async () => {
            const agreementId = constants.bytes32.one
            const rewardAddress = accounts[2]
            const sender = accounts[0]
            const amount = 10

            await token.mint(sender, amount, { from: owner })
            await token.approve(
                lockRewardCondition.address,
                amount,
                { from: sender })

            await assert.isRejected(
                lockRewardCondition.fulfill(agreementId, rewardAddress, amount),
                constants.acl.error.invalidUpdateRole
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist for account address', async () => {
            const agreementId = constants.bytes32.one
            const rewardAddress = accounts[2]
            const sender = accounts[0]
            const amount = 10

            const hashValues = await lockRewardCondition.hashValues(rewardAddress, amount)
            const conditionId = await lockRewardCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockRewardCondition.address)

            await token.mint(sender, amount, { from: owner })
            await token.approve(
                lockRewardCondition.address,
                amount,
                { from: sender })

            const result = await lockRewardCondition.fulfill(agreementId, rewardAddress, amount)
            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
            const rewardBalance = await getBalance(token, rewardAddress)
            assert.strictEqual(rewardBalance, amount)

            testUtils.assertEmitted(result, 1, 'Fulfilled')
            const eventArgs = testUtils.getEventArgsFromTx(result, 'Fulfilled')
            expect(eventArgs._agreementId).to.equal(agreementId)
            expect(eventArgs._conditionId).to.equal(conditionId)
            expect(eventArgs._rewardAddress).to.equal(rewardAddress)
            expect(eventArgs._amount.toNumber()).to.equal(amount)
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('out of balance should fail to fulfill if conditions exist', async () => {
            const agreementId = testUtils.generateId()
            const rewardAddress = accounts[2]
            const amount = 10

            const hashValues = await lockRewardCondition.hashValues(rewardAddress, amount)
            const conditionId = await lockRewardCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockRewardCondition.address)

            await assert.isRejected(
                lockRewardCondition.fulfill(agreementId, rewardAddress, amount),
                undefined
            )
        })

        it('not approved should fail to fulfill if conditions exist', async () => {
            const agreementId = testUtils.generateId()
            const rewardAddress = accounts[2]
            const amount = 10
            const sender = accounts[0]

            const hashValues = await lockRewardCondition.hashValues(rewardAddress, amount)
            const conditionId = await lockRewardCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockRewardCondition.address)

            await token.mint(sender, amount, { from: owner })

            await assert.isRejected(
                lockRewardCondition.fulfill(agreementId, rewardAddress, amount),
                undefined
            )
        })

        it('right transfer should fail to fulfill if conditions already fulfilled', async () => {
            const agreementId = testUtils.generateId()
            const rewardAddress = accounts[2]
            const amount = 10
            const sender = accounts[0]

            const hashValues = await lockRewardCondition.hashValues(rewardAddress, amount)
            const conditionId = await lockRewardCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockRewardCondition.address
            )

            await token.mint(sender, amount, { from: owner })
            await token.approve(
                lockRewardCondition.address,
                amount,
                { from: sender }
            )

            await lockRewardCondition.fulfill(agreementId, rewardAddress, amount)
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )

            await assert.isRejected(
                lockRewardCondition.fulfill(agreementId, rewardAddress, amount),
                undefined
            )

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            const agreementId = testUtils.generateId()
            const rewardAddress = accounts[2]
            const amount = 10
            const sender = accounts[0]

            const hashValues = await lockRewardCondition.hashValues(rewardAddress, amount)
            const conditionId = await lockRewardCondition.generateId(agreementId, hashValues)

            await conditionStoreManager.createCondition(
                conditionId,
                lockRewardCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            await token.mint(sender, amount, { from: owner })
            await token.approve(
                lockRewardCondition.address,
                amount,
                { from: sender })

            await assert.isRejected(
                lockRewardCondition.fulfill(agreementId, rewardAddress, amount),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
