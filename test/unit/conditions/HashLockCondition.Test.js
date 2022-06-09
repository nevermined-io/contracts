/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')
const EpochLibrary = artifacts.require('EpochLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const HashLockCondition = artifacts.require('HashLockCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('HashLockCondition constructor', (accounts) => {
    let conditionStoreManager
    let hashLockCondition
    let nvmConfig

    //    let conditionType = constants.address.dummy
    const conditionId = constants.bytes32.one
    const owner = accounts[1]
    const createRole = accounts[0]

    before(async () => {
        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
        nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, owner)
    })

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!hashLockCondition) {
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            hashLockCondition = await HashLockCondition.new()
            await hashLockCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        }
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            const conditionStoreManager = await ConditionStoreManager.new()
            const hashLockCondition = await HashLockCondition.new()
            await hashLockCondition.initialize(
                accounts[0],
                conditionStoreManager.address,
                { from: accounts[0] }
            )
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist for uint preimage', async () => {
            await assert.isRejected(
                hashLockCondition.fulfill(
                    conditionId,
                    constants.condition.hashlock.uint.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('should not fulfill if conditions do not exist for string preimage', async () => {
            await assert.isRejected(
                hashLockCondition.methods['fulfill(bytes32,string)'](
                    conditionId,
                    constants.condition.hashlock.string.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('should not fulfill if conditions do not exist for bytes32 preimage', async () => {
            await assert.isRejected(
                hashLockCondition.methods['fulfill(bytes32,bytes32)'](
                    conditionId,
                    constants.condition.hashlock.bytes32.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist for uint preimage', async () => {
            const agreementId = testUtils.generateId()

            const conditionId = await hashLockCondition.generateId(
                agreementId,
                constants.condition.hashlock.uint.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await hashLockCondition.fulfill(
                agreementId,
                constants.condition.hashlock.uint.preimage
            )

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
        })

        it('should fulfill if conditions exist for string preimage', async () => {
            const agreementId = testUtils.generateId()

            const conditionId = await hashLockCondition.generateId(
                agreementId,
                constants.condition.hashlock.string.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)
            await hashLockCondition.hashValues(
                constants.condition.hashlock.string.preimage
            )
            // DEV: Uncomment in case you need to update the preimage variable
            // console.log('Hash of preImage: ' + _hash)

            await hashLockCondition.methods['fulfill(bytes32,string)'](
                agreementId,
                constants.condition.hashlock.string.preimage
            )

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
        })

        it('should fulfill if conditions exist for bytes32 preimage', async () => {
            const agreementId = testUtils.generateId()

            const conditionId = await hashLockCondition.generateId(
                agreementId,
                constants.condition.hashlock.bytes32.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await hashLockCondition.methods['fulfill(bytes32,bytes32)'](
                agreementId,
                constants.condition.hashlock.bytes32.preimage
            )

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(state.toNumber(), constants.condition.state.fulfilled)
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('wrong preimage should fail to fulfill if conditions exist for uint preimage', async () => {
            const conditionId = await hashLockCondition.generateId(
                testUtils.generateId(),
                constants.condition.hashlock.uint.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await assert.isRejected(
                hashLockCondition.fulfill(
                    constants.bytes32.one,
                    constants.condition.hashlock.uint.preimage + 333
                ),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('wrong preimage should fail to fulfill if conditions exist for uint preimage with string', async () => {
            const conditionId = await hashLockCondition.generateId(
                testUtils.generateId(),
                constants.condition.hashlock.uint.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await assert.isRejected(
                hashLockCondition.methods['fulfill(bytes32,string)'](
                    constants.bytes32.one,
                    constants.condition.hashlock.uint.preimage + 'some bogus'
                ),
                constants.acl.error.invalidUpdateRoled
            )
        })

        it('wrong preimage should fail to fulfill if conditions exist for string preimage', async () => {
            const conditionId = await hashLockCondition.generateId(
                testUtils.generateId(),
                constants.condition.hashlock.string.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await assert.isRejected(
                hashLockCondition.fulfill(
                    constants.bytes32.one,
                    constants.condition.hashlock.uint.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('wrong preimage should fail to fulfill if conditions exist for uint preimage with bytes32', async () => {
            const conditionId = await hashLockCondition.generateId(
                testUtils.generateId(),
                constants.condition.hashlock.uint.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            await assert.isRejected(
                hashLockCondition.methods['fulfill(bytes32,bytes32)'](
                    constants.bytes32.one,
                    constants.condition.hashlock.bytes32.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })

        it('right preimage should fail to fulfill if conditions already fulfilled for uint', async () => {
            const agreementId = testUtils.generateId()
            const conditionId = await hashLockCondition.generateId(
                agreementId,
                constants.condition.hashlock.uint.keccak
            )
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address)

            // fulfill once
            await hashLockCondition.fulfill(
                agreementId,
                constants.condition.hashlock.uint.preimage
            )
            // try to fulfill another time
            await assert.isRejected(
                hashLockCondition.fulfill(
                    agreementId,
                    constants.condition.hashlock.uint.preimage
                ),
                constants.condition.state.error.invalidStateTransition
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            const conditionId = await hashLockCondition.generateId(
                testUtils.generateId(),
                constants.condition.hashlock.uint.keccak
            )

            // create a condition of a type different than hashlockcondition
            await conditionStoreManager.createCondition(
                conditionId,
                hashLockCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            // try to fulfill from hashlockcondition
            await assert.isRejected(
                hashLockCondition.fulfill(
                    constants.bytes32.one,
                    constants.condition.hashlock.uint.preimage
                ),
                constants.acl.error.invalidUpdateRole
            )
        })
    })
})
