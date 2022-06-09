/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')
const HashLists = artifacts.require('HashLists')
const EpochLibrary = artifacts.require('EpochLibrary')
const HashListLibrary = artifacts.require('HashListLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const WhitelistingCondition = artifacts.require('WhitelistingCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('Whitelisting Condition', (accounts) => {
    const owner = accounts[1]
    const createRole = accounts[0]
    const governor = accounts[2]
    let hashList
    let conditionStoreManager
    let whitelistingCondition

    before(async () => {
        const epochLibrary = await EpochLibrary.new()
        const hashListLibrary = await HashListLibrary.new()
        await HashLists.link(hashListLibrary)
        await ConditionStoreManager.link(epochLibrary)
    })

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest({
        conditionId = constants.bytes32.one,
        conditionType = constants.address.dummy,
        createRole = accounts[0],
        owner = accounts[1]
    } = {}) {
        if (!whitelistingCondition) {
            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, governor)

            hashList = await HashLists.new()
            await hashList.initialize(
                owner,
                {
                    from: owner
                }
            )
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: accounts[0] }
            )

            whitelistingCondition = await WhitelistingCondition.new()
            await whitelistingCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: accounts[0] }
            )
        }

        return { whitelistingCondition, conditionStoreManager, hashList, conditionId, conditionType, createRole, owner }
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, governor)

            const hashList = await HashLists.new()
            await hashList.initialize(
                owner,
                {
                    from: owner
                }
            )

            const conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            const whitelistingCondition = await WhitelistingCondition.new()
            await whitelistingCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist', async () => {
            //            const { whitelistingCondition, hashList } = await setupTest()
            const someone = accounts[9]
            const agreementId = constants.bytes32.one

            const value = await hashList.hash(someone)

            await assert.isRejected(
                whitelistingCondition.fulfill(agreementId, hashList.address, value, { from: accounts[2] }),
                constants.condition.state.error.conditionNeedsToBeUnfulfilled
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist', async () => {
            //            const {
            //                whitelistingCondition,
            //                conditionStoreManager,
            //                hashList,
            //                createRole
            //            } = await setupTest()

            const agreementId = constants.bytes32.one
            const someone = accounts[9]
            const listOwner = createRole
            const value = await hashList.hash(someone)
            await hashList.methods['add(bytes32)'](
                value,
                {
                    from: listOwner
                }
            )
            const hashValues = await whitelistingCondition.hashValues(hashList.address, value)

            const conditionId = await whitelistingCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                whitelistingCondition.address
            )

            await whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                agreementId,
                hashList.address,
                value,
                {
                    from: createRole
                }
            )

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(constants.condition.state.fulfilled, state.toNumber())
        })
    })

    describe('fail to fulfill existing condition', () => {
        it('wrong value should fail to fulfill if conditions exist', async () => {
            const agreementId = testUtils.generateId()
            const someone = accounts[9]

            const value = await hashList.hash(someone)
            await hashList.methods['add(bytes32)'](
                value,
                {
                    from: owner
                }
            )
            const hashValues = await whitelistingCondition.hashValues(hashList.address, value)

            const conditionId = await whitelistingCondition.generateId(
                agreementId,
                hashValues
            )

            const someoneElse = accounts[8]
            const wrongValue = await hashList.hash(someoneElse)

            await conditionStoreManager.createCondition(
                conditionId,
                whitelistingCondition.address
            )

            await assert.isRejected(
                whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                    agreementId,
                    hashList.address,
                    wrongValue,
                    {
                        from: createRole
                    }
                ),
                'Item does not exist'
            )
        })

        it('wrong value should fail to fulfill if conditions exist', async () => {
            const agreementId = testUtils.generateId()
            const someone = testUtils.generateAccount().address

            const value = await hashList.hash(someone)
            await hashList.methods['add(bytes32)'](
                value,
                {
                    from: owner
                }
            )

            const hashValues = await whitelistingCondition.hashValues(hashList.address, value)

            const conditionId = await whitelistingCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                whitelistingCondition.address
            )
            const wrongListAddress = whitelistingCondition.address
            await assert.isRejected(
                whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                    agreementId,
                    wrongListAddress,
                    value,
                    {
                        from: createRole
                    }
                )
            )
        })

        it('right value should fail to fulfill if conditions already fulfilled ', async () => {
            const agreementId = testUtils.generateId()
            const someone = testUtils.generateAccount().address

            const value = await hashList.hash(someone)
            const listOwner = createRole
            await hashList.methods['add(bytes32)'](
                value,
                {
                    from: listOwner
                }
            )
            const hashValues = await whitelistingCondition.hashValues(hashList.address, value)

            const conditionId = await whitelistingCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                whitelistingCondition.address
            )

            await whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                agreementId,
                hashList.address,
                value,
                {
                    from: createRole
                }
            )

            await assert.isRejected(
                whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                    agreementId,
                    hashList.address,
                    value,
                    {
                        from: createRole
                    }
                ),
                constants.condition.state.error.invalidStateTransition
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            const agreementId = testUtils.generateId()
            const someone = testUtils.generateAccount().address

            const value = await hashList.hash(someone)
            await hashList.methods['add(bytes32)'](
                value,
                {
                    from: owner
                }
            )
            const hashValues = await whitelistingCondition.hashValues(hashList.address, value)

            const conditionId = await whitelistingCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                whitelistingCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            await assert.isRejected(
                whitelistingCondition.methods['fulfill(bytes32,address,bytes32)'](
                    agreementId,
                    hashList.address,
                    value,
                    {
                        from: createRole
                    }
                ),
                'Item does not exist'
            )
        })
    })
})
