/* eslint-env mocha */
/* global artifacts, web3, contract, describe, it, beforeEach */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../helpers/constants.js')

function confirmUpgrade() {}

const {
    deploy,
    upgrade
} = require('./Upgrader')

const ConditionStoreManager = artifacts.require('ConditionStoreManager')

const ConditionStoreChangeFunctionSignature = artifacts.require('ConditionStoreChangeFunctionSignature')
const ConditionStoreChangeInStorage = artifacts.require('ConditionStoreChangeInStorage')
const ConditionStoreChangeInStorageAndLogic = artifacts.require('ConditionStoreChangeInStorageAndLogic')
const ConditionStoreExtraFunctionality = artifacts.require('ConditionStoreExtraFunctionality')
const ConditionStoreWithBug = artifacts.require('ConditionStoreWithBug')

contract('ConditionStoreManager', (accounts) => {
    let conditionStoreManagerAddress

    const verbose = false

    const approver = accounts[2]
    const conditionCreater = accounts[5]
    const owner = accounts[8]

    beforeEach('Load wallet each time', async function() {
        const addressBook = await deploy({
            web3,
            artifacts,
            contracts: ['ConditionStoreManager', 'NeverminedConfig'],
            verbose
        })

        conditionStoreManagerAddress = addressBook.ConditionStoreManager
        assert(conditionStoreManagerAddress)
    })

    async function setupTest({
        conditionId = constants.bytes32.one,
        conditionType = constants.address.dummy
    } = {}) {
        const conditionStoreManager = await ConditionStoreManager.at(conditionStoreManagerAddress)
        conditionType = conditionStoreManagerAddress
        return { conditionStoreManager, conditionId, conditionType }
    }

    describe('Test upgradability for ConditionStoreManager [ @skip-on-coverage ]', () => {
        it('Should be possible to fix/add a bug', async () => {
            const { conditionId } = await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['ConditionStoreWithBug:ConditionStoreManager'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.ConditionStoreManager,
                approver,
                verbose
            )

            const ConditionStoreWithBugInstance =
                await ConditionStoreWithBug.at(conditionStoreManagerAddress)

            // assert
            assert.strictEqual(
                (await ConditionStoreWithBugInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.fulfilled,
                'condition should be fulfilled (according to bug)'
            )
        })

        it('Should be possible to change function signature', async () => {
            const { conditionId, conditionType } = await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['ConditionStoreChangeFunctionSignature:ConditionStoreManager'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.ConditionStoreManager,
                approver,
                verbose
            )

            const ConditionStoreChangeFunctionSignatureInstance =
                await ConditionStoreChangeFunctionSignature.at(conditionStoreManagerAddress)

            await ConditionStoreChangeFunctionSignatureInstance.delegateCreateRole(conditionCreater, { from: owner })

            // assert
            assert.strictEqual(
                await ConditionStoreChangeFunctionSignatureInstance.getCreateRole(),
                conditionCreater,
                'Invalid create role!'
            )

            await ConditionStoreChangeFunctionSignatureInstance.createCondition(
                conditionId,
                conditionType,
                conditionCreater,
                { from: conditionCreater }
            )

            // assert
            assert.strictEqual(
                (await ConditionStoreChangeFunctionSignatureInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.unfulfilled,
                'condition should be unfulfilled'
            )
        })

        it('Should be possible to append storage variable(s) ', async () => {
            await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['ConditionStoreChangeInStorage:ConditionStoreManager'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.ConditionStoreManager,
                approver,
                verbose
            )

            const ConditionStoreChangeInStorageInstance =
                await ConditionStoreChangeInStorage.at(conditionStoreManagerAddress)

            assert.strictEqual(
                (await ConditionStoreChangeInStorageInstance.conditionCount()).toNumber(),
                0
            )
        })

        it('Should be possible to append storage variables and change logic', async () => {
            const { conditionId, conditionType } = await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['ConditionStoreChangeInStorageAndLogic:ConditionStoreManager'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.ConditionStoreManager,
                approver,
                verbose
            )

            const ConditionStoreChangeInStorageAndLogicInstance =
                await ConditionStoreChangeInStorageAndLogic.at(conditionStoreManagerAddress)

            await ConditionStoreChangeInStorageAndLogicInstance.delegateCreateRole(conditionCreater, { from: owner })

            assert.strictEqual(
                (await ConditionStoreChangeInStorageAndLogicInstance.conditionCount()).toNumber(),
                0
            )

            await ConditionStoreChangeInStorageAndLogicInstance.createCondition(
                conditionId,
                conditionType,
                conditionCreater,
                { from: conditionCreater }
            )

            assert.strictEqual(
                (await ConditionStoreChangeInStorageAndLogicInstance.getConditionState(conditionId)).toNumber(),
                constants.condition.state.unfulfilled,
                'condition should be unfulfilled'
            )
        })

        it('Should be able to call new method added after upgrade is approved', async () => {
            await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['ConditionStoreExtraFunctionality:ConditionStoreManager'],
                verbose
            })

            // init
            await confirmUpgrade(
                web3,
                taskBook.ConditionStoreManager,
                approver,
                verbose
            )

            const ConditionStoreExtraFunctionalityInstance =
                await ConditionStoreExtraFunctionality.at(conditionStoreManagerAddress)

            // asset
            assert.strictEqual(
                await ConditionStoreExtraFunctionalityInstance.dummyFunction(),
                true
            )
        })
    })
})
