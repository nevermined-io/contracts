/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const EpochLibrary = artifacts.require('EpochLibrary')
const NeverminedConfig = artifacts.require('NeverminedConfig')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const ThresholdCondition = artifacts.require('ThresholdCondition')
const HashLockCondition = artifacts.require('HashLockCondition')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('Threshold Condition', (accounts) => {
    const owner = accounts[1]
    const createRole = accounts[0]
    let hashLockCondition
    let randomConditionID
    let conditionStoreManager
    let thresholdCondition
    let nvmConfig
    const randomConditions = []

    before(async () => {
        nvmConfig = await NeverminedConfig.new()
        await nvmConfig.initialize(owner, owner)
        const epochLibrary = await EpochLibrary.new()
        await ConditionStoreManager.link(epochLibrary)
    })

    async function setupTest({
        conditionId = testUtils.generateId(),
        conditionType = constants.address.dummy,
        createRole = accounts[0],
        owner = accounts[1],
        fulfillInputConditions = true,
        includeRandomInputConditions = false,
        MaxNConditions = 50
    } = {}) {
        if (!thresholdCondition) {
            conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: accounts[0] }
            )

            thresholdCondition = await ThresholdCondition.new()
            await thresholdCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: accounts[0] }
            )

            // create dummy and real input conditions
            hashLockCondition = await HashLockCondition.new()
            await hashLockCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        }

        const condition1 = testUtils.generateId()
        const condition2 = testUtils.generateId()

        const firstConditionId = await hashLockCondition.generateId(
            condition1,
            constants.condition.hashlock.uint.keccak
        )

        const secondConditionId = await hashLockCondition.generateId(
            condition2,
            constants.condition.hashlock.uint.keccak
        )

        await conditionStoreManager.createCondition(
            firstConditionId,
            hashLockCondition.address
        )

        await conditionStoreManager.createCondition(
            secondConditionId,
            hashLockCondition.address
        )

        if (fulfillInputConditions) {
            await hashLockCondition.fulfill(
                condition1,
                constants.condition.hashlock.uint.preimage
            )

            await hashLockCondition.fulfill(
                condition2,
                constants.condition.hashlock.uint.preimage
            )

            const firstConditionState = await conditionStoreManager.getCondition(firstConditionId)
            const secondConditionState = await conditionStoreManager.getCondition(secondConditionId)
            assert.strictEqual(firstConditionState.state.toNumber(), constants.condition.state.fulfilled)
            assert.strictEqual(secondConditionState.state.toNumber(), constants.condition.state.fulfilled)
        }

        const inputConditions = [
            firstConditionId,
            secondConditionId
        ]

        if (includeRandomInputConditions) {
            for (let i = 0; i < MaxNConditions - 2; i++) {
                randomConditionID = testUtils.generateId()
                await conditionStoreManager.createCondition(
                    randomConditionID,
                    hashLockCondition.address
                )
                randomConditions.push(randomConditionID)
            }
            randomConditions.push(inputConditions[0])
            randomConditions.push(inputConditions[1])
        }

        return {
            thresholdCondition,
            conditionStoreManager,
            conditionId,
            conditionType,
            createRole,
            owner,
            inputConditions,
            randomConditions,
            condition1,
            condition2
        }
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, owner)

            const conditionStoreManager = await ConditionStoreManager.new()
            await conditionStoreManager.initialize(
                createRole,
                owner,
                nvmConfig.address,
                { from: owner }
            )

            const thresholdCondition = await ThresholdCondition.new()
            await thresholdCondition.initialize(
                owner,
                conditionStoreManager.address,
                { from: owner }
            )
        })
    })

    describe('fulfill non existing condition', () => {
        it('should not fulfill if conditions do not exist', async () => {
            const { thresholdCondition, inputConditions } = await setupTest()
            const agreementId = constants.bytes32.three

            await assert.isRejected(
                thresholdCondition.fulfill(agreementId, inputConditions, 2, { from: accounts[2] }),
                constants.condition.state.error.conditionNeedsToBeUnfulfilled
            )
        })
    })

    describe('fulfill existing condition', () => {
        it('should fulfill if conditions exist', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole
            } = await setupTest()

            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                agreementId,
                inputConditions,
                inputConditions.length,
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
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole,
                condition1,
                condition2
            } = await setupTest()
            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                agreementId,
                inputConditions,
                inputConditions.length,
                {
                    from: createRole
                }
            )
            const invalidInputConditions = [
                condition1,
                condition2
            ]
            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    invalidInputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                'Invalid threshold fulfilment'
            )
        })

        it('wrong value should fail to fulfill if conditions exist', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole
            } = await setupTest()
            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )
            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length - 1,
                    {
                        from: createRole
                    }
                ),
                'Invalid UpdateRole'
            )
        })

        it('right value should fail to fulfill if conditions already fulfilled ', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole
            } = await setupTest()

            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                agreementId,
                inputConditions,
                inputConditions.length,
                {
                    from: createRole
                }
            )

            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                constants.condition.state.error.invalidStateTransition
            )
        })

        it('should fail to fulfill if conditions has different type ref', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                owner,
                createRole
            } = await setupTest()

            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await conditionStoreManager.delegateUpdateRole(
                conditionId,
                createRole,
                { from: owner }
            )

            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                constants.acl.error.invalidUpdateRole
            )
        })
    })

    describe('UNINITIALIZED OR ABORTED input conditions', () => {
        it('should fail if input conditions are Unfulfilled', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole
            } = await setupTest({ fulfillInputConditions: false })

            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                'Invalid threshold fulfilment'
            )
        })

        it('should fail if input conditions are Uninitialized', async () => {
            const {
                thresholdCondition,
                inputConditions,
                createRole
            } = await setupTest({ fulfillInputConditions: false })

            const agreementId = constants.bytes32.three

            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                'Invalid threshold fulfilment'
            )
        })

        it('should fail if input conditions are ABORTED', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                inputConditions,
                createRole,
                owner
            } = await setupTest({ fulfillInputConditions: false })

            const agreementId = constants.bytes32.three

            const hashValues = await thresholdCondition.hashValues(inputConditions, inputConditions.length)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            // Abort input conditions
            await conditionStoreManager.delegateUpdateRole(
                inputConditions[0],
                createRole,
                {
                    from: owner
                }
            )

            await conditionStoreManager.delegateUpdateRole(
                inputConditions[1],
                createRole,
                {
                    from: owner
                }
            )

            await conditionStoreManager.updateConditionState(
                inputConditions[0],
                3,
                {
                    from: createRole
                }
            )

            await conditionStoreManager.updateConditionState(
                inputConditions[1],
                3,
                {
                    from: createRole
                }
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await assert.isRejected(
                thresholdCondition.methods['fulfill(bytes32,bytes32[],uint256)'](
                    agreementId,
                    inputConditions,
                    inputConditions.length,
                    {
                        from: createRole
                    }
                ),
                'Invalid threshold fulfilment'
            )
        })
    })

    describe('load testing', () => {
        it('should pass if the last input conditions pass the threshold', async () => {
            const {
                thresholdCondition,
                conditionStoreManager,
                randomConditions,
                inputConditions,
                createRole
            } = await setupTest({
                includeRandomInputConditions: true,
                fulfillInputConditions: true
            })
            const agreementId = constants.bytes32.three

            const threshold = inputConditions.length
            const hashValues = await thresholdCondition.hashValues(randomConditions, threshold)

            const conditionId = await thresholdCondition.generateId(
                agreementId,
                hashValues
            )

            await conditionStoreManager.createCondition(
                conditionId,
                thresholdCondition.address
            )

            await thresholdCondition.fulfill(
                agreementId,
                randomConditions,
                threshold,
                {
                    from: createRole
                }
            )

            const { state } = await conditionStoreManager.getCondition(conditionId)
            assert.strictEqual(constants.condition.state.fulfilled, state.toNumber())
        })
    })
})
