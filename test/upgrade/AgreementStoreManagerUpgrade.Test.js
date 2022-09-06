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

const AgreementStoreManager = artifacts.require('AgreementStoreManager')

const AgreementStoreManagerChangeFunctionSignature =
    artifacts.require('AgreementStoreManagerChangeFunctionSignature')
const AgreementStoreManagerChangeInStorage =
    artifacts.require('AgreementStoreManagerChangeInStorage')
const AgreementStoreManagerChangeInStorageAndLogic =
    artifacts.require('AgreementStoreManagerChangeInStorageAndLogic')
const AgreementStoreManagerExtraFunctionality =
    artifacts.require('AgreementStoreManagerExtraFunctionality')
const AgreementStoreManagerWithBug = artifacts.require('AgreementStoreManagerWithBug')

contract('AgreementStoreManager', (accounts) => {
    let agreementStoreManagerAddress

    const verbose = false
    const approver = accounts[2]

    async function setupTest({
        agreementId = constants.bytes32.one,
        conditionIds = [constants.address.dummy],
        did = constants.did[0],
        conditionTypes = [constants.address.dummy],
        timeLocks = [0],
        timeOuts = [2]
    } = {}) {
        await AgreementStoreManager.at(agreementStoreManagerAddress)
        return {
            did,
            agreementId,
            conditionIds,
            conditionTypes,
            timeLocks,
            timeOuts
        }
    }

    describe('Test upgradability for AgreementStoreManager [ @skip-on-coverage ]', () => {
        beforeEach('Load wallet each time', async () => {
            const addressBook = await deploy({
                web3,
                artifacts,
                contracts: [
                    'NeverminedConfig',
                    'DIDRegistry',
                    'ConditionStoreManager',
                    'TemplateStoreManager',
                    'AgreementStoreManager'
                ],
                verbose
            })

            agreementStoreManagerAddress = addressBook.AgreementStoreManager
            assert(agreementStoreManagerAddress)
        })

        it('Should be possible to fix/add a bug', async () => {
            await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['AgreementStoreManagerWithBug:AgreementStoreManager'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.AgreementStoreManager,
                approver,
                verbose
            )
            const AgreementStoreManagerWithBugInstance =
                await AgreementStoreManagerWithBug.at(agreementStoreManagerAddress)

            assert.strictEqual(
                await AgreementStoreManagerWithBugInstance.getDIDRegistryAddress(),
                constants.address.zero,
                'did registry should return zero (according to bug)'
            )
        })

        it('Should be possible to change function signature', async () => {
            const {
                did,
                agreementId,
                conditionIds,
                conditionTypes,
                timeLocks,
                timeOuts
            } = await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['AgreementStoreManagerChangeFunctionSignature:AgreementStoreManager'],
                verbose
            })

            // act & assert
            await confirmUpgrade(
                web3,
                taskBook.AgreementStoreManager,
                approver,
                verbose
            )

            const AgreementStoreManagerChangeFunctionSignatureInstance =
                await AgreementStoreManagerChangeFunctionSignature.at(agreementStoreManagerAddress)

            await assert.isRejected(
                AgreementStoreManagerChangeFunctionSignatureInstance.methods['createAgreement(bytes32,bytes32,address[],bytes32[],uint256[],uint256[],address,address)'](
                    agreementId,
                    did,
                    conditionTypes,
                    conditionIds,
                    timeLocks,
                    timeOuts,
                    accounts[7],
                    accounts[7],
                    { from: accounts[8] }
                ),
                'Invalid sender address, should fail in function signature check'
            )
        })

        it('Should be possible to append storage variable(s) ', async () => {
            await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['AgreementStoreManagerChangeInStorage:AgreementStoreManager'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.AgreementStoreManager,
                approver,
                verbose
            )

            const AgreementStoreManagerChangeInStorageInstance =
                await AgreementStoreManagerChangeInStorage.at(agreementStoreManagerAddress)

            // act & assert
            assert.strictEqual(
                (await AgreementStoreManagerChangeInStorageInstance.agreementCount()).toNumber(),
                0,
                'Invalid change in storage'
            )
        })

        it('Should be possible to append storage variables and change logic', async () => {
            const {
                did,
                agreementId,
                conditionIds,
                conditionTypes,
                timeLocks,
                timeOuts
            } = await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['AgreementStoreManagerChangeInStorageAndLogic:AgreementStoreManager'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.AgreementStoreManager,
                approver,
                verbose
            )

            const AgreementStoreManagerChangeInStorageAndLogicInstance =
                await AgreementStoreManagerChangeInStorageAndLogic.at(agreementStoreManagerAddress)

            // act & assert
            await assert.isRejected(
                AgreementStoreManagerChangeInStorageAndLogicInstance.methods['createAgreement(bytes32,bytes32,address[],bytes32[],uint256[],uint256[],address,address)'](
                    agreementId,
                    did,
                    conditionTypes,
                    conditionIds,
                    timeLocks,
                    timeOuts,
                    accounts[7],
                    accounts[7],
                    { from: accounts[8] }
                ),
                'Invalid sender address, should fail in function signature check'
            )

            assert.strictEqual(
                (await AgreementStoreManagerChangeInStorageAndLogicInstance.agreementCount()).toNumber(),
                0,
                'Invalid change in storage'
            )
        })

        it('Should be able to call new method added after upgrade is approved', async () => {
            await setupTest()

            const taskBook = await upgrade({
                web3,
                contracts: ['AgreementStoreManagerExtraFunctionality:AgreementStoreManager'],
                verbose
            })

            await confirmUpgrade(
                web3,
                taskBook.AgreementStoreManager,
                approver,
                verbose
            )

            const AgreementStoreExtraFunctionalityInstance =
                await AgreementStoreManagerExtraFunctionality.at(agreementStoreManagerAddress)

            // act & assert
            assert.strictEqual(
                await AgreementStoreExtraFunctionalityInstance.dummyFunction(),
                true,
                'Invalid extra functionality upgrade'
            )
        })
    })
})
