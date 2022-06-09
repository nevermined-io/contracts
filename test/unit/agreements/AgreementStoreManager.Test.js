/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const { expect } = require('chai')
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
const { web3 } = require('hardhat')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')
const Common = artifacts.require('Common')
const EpochLibrary = artifacts.require('EpochLibrary')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const AgreementStoreManager = artifacts.require('AgreementStoreManager')
const TemplateStoreManager = artifacts.require('TemplateStoreManager')
const NeverminedToken = artifacts.require('NeverminedToken')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')

const constants = require('../../helpers/constants.js')
const testUtils = require('../../helpers/utils.js')

contract('AgreementStoreManager', (accounts) => {
    const did = constants.did[0]
    const checksum = testUtils.generateId()
    const value = constants.registry.url
    const deployer = accounts[8]
    const owner = accounts[9]
    const providers = [accounts[8], accounts[9]]
    const templateId = accounts[2]
    let common,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        token

    before(async () => {
        const epochLibrary = await EpochLibrary.new({ from: deployer })
        await ConditionStoreManager.link(epochLibrary)
    })

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!agreementStoreManager) {
            token = await NeverminedToken.new({ from: deployer })
            await token.initialize(owner, owner)

            const nvmConfig = await NeverminedConfig.new()
            await nvmConfig.initialize(owner, owner)

            const didRegistryLibrary = await DIDRegistryLibrary.new()
            await DIDRegistry.link(didRegistryLibrary)
            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero)

            conditionStoreManager = await ConditionStoreManager.new({ from: deployer })

            templateStoreManager = await TemplateStoreManager.new({ from: deployer })
            await templateStoreManager.initialize(
                owner,
                { from: deployer }
            )

            // const agreementStoreLibrary = await AgreementStoreLibrary.new({ from: deployer })
            // await AgreementStoreManager.link(agreementStoreLibrary)
            agreementStoreManager = await AgreementStoreManager.new({ from: deployer })
            await agreementStoreManager.methods['initialize(address,address,address,address)'](
                owner,
                conditionStoreManager.address,
                templateStoreManager.address,
                didRegistry.address,
                { from: deployer }
            )

            await conditionStoreManager.initialize(
                agreementStoreManager.address,
                owner,
                nvmConfig.address,
                { from: deployer }
            )
            common = await Common.new()

            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })
        }
    }

    async function registerNewDID() {
        const didSeed = testUtils.generateId()
        const did = await didRegistry.hashDID(didSeed, accounts[0])
        await didRegistry.registerAttribute(didSeed, checksum, providers, value)
        return did
    }

    describe('deploy and setup', () => {
        it('contract should deploy', async () => {
            // const agreementStoreLibrary = await AgreementStoreLibrary.new()
            // await AgreementStoreManager.link(agreementStoreLibrary)
            await AgreementStoreManager.new()
        })

        it('contract should not initialize with zero address', async () => {
            const createRole = accounts[0]

            // const agreementStoreLibrary = await AgreementStoreLibrary.new()
            // await AgreementStoreManager.link(agreementStoreLibrary)
            const agreementStoreManager = await AgreementStoreManager.new()

            // setup with zero fails
            await assert.isRejected(
                agreementStoreManager.methods['initialize(address,address,address,address)'](
                    constants.address.zero,
                    createRole,
                    createRole,
                    createRole,
                    { from: createRole }
                ),
                constants.address.error.invalidAddress0x0
            )

            // setup with zero fails
            await assert.isRejected(
                agreementStoreManager.methods['initialize(address,address,address,address)'](
                    createRole,
                    constants.address.zero,
                    createRole,
                    createRole,
                    { from: createRole }
                ),
                constants.address.error.invalidAddress0x0
            )

            // setup with zero fails
            await assert.isRejected(
                agreementStoreManager.methods['initialize(address,address,address,address)'](
                    createRole,
                    createRole,
                    constants.address.zero,
                    createRole,
                    { from: createRole }
                ),
                constants.address.error.invalidAddress0x0
            )

            // setup with zero fails
            await assert.isRejected(
                agreementStoreManager.methods['initialize(address,address,address,address)'](
                    createRole,
                    createRole,
                    createRole,
                    constants.address.zero,
                    { from: createRole }
                ),
                constants.address.error.invalidAddress0x0
            )
        })

        it('contract should not initialize without arguments', async () => {
            // const agreementStoreLibrary = await AgreementStoreLibrary.new()
            // await AgreementStoreManager.link(agreementStoreLibrary)
            const agreementStoreManager = await AgreementStoreManager.new()

            // setup with zero fails
            await assert.isRejected(
                agreementStoreManager.methods['initialize(address,address,address,address)'](),
                constants.initialize.error.invalidNumberParamsGot0Expected4
            )
        })

        it('contract should have initialized', async () => {
            expect(await agreementStoreManager.getDIDRegistryAddress()).to.equal(didRegistry.address)
        })
    })

    describe('proxy', () => {
        const proxyRole = web3.utils.soliditySha3('PROXY_ROLE')
        it('setting proxy', async () => {
            await agreementStoreManager.grantProxyRole(accounts[2], { from: owner })
            expect(await agreementStoreManager.hasRole(proxyRole, accounts[2])).to.equal(true)
        })
        it('revoking proxy', async () => {
            await agreementStoreManager.grantProxyRole(accounts[2], { from: owner })
            expect(await agreementStoreManager.hasRole(proxyRole, accounts[2])).to.equal(true)
            await agreementStoreManager.revokeProxyRole(accounts[2], { from: owner })
            expect(await agreementStoreManager.hasRole(proxyRole, accounts[2])).to.equal(false)
        })
    })

    describe('create agreement', () => {
        it('create agreement should create agreement and conditions', async () => {
            const did = await registerNewDID()

            const agreement = {
                did: did,
                conditionTypes: [common.address, common.address],
                conditionIds: [constants.bytes32.zero, constants.bytes32.one],
                timeLocks: [0, 1],
                timeOuts: [2, 3]
            }
            const agreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            await Promise.all(agreement.conditionIds.map(async (conditionId, i) => {
                const fullId = await agreementStoreManager.fullConditionId(agreementId, agreement.conditionTypes[i], conditionId)
                const storedCondition = await conditionStoreManager.getCondition(fullId)
                expect(storedCondition.typeRef).to.equal(agreement.conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
                expect(storedCondition.timeLock.toNumber()).to.equal(agreement.timeLocks[i])
                expect(storedCondition.timeOut.toNumber()).to.equal(agreement.timeOuts[i])
            }))

            // expect((await agreementStoreManager.getAgreementListSize()).toNumber()).to.equal(1)
        })

        it('should not create agreement with bad arguments', async () => {
            const did = await registerNewDID()

            const agreement = {
                did: did,
                conditionTypes: [common.address, common.address],
                conditionIds: [constants.bytes32.zero, constants.bytes32.one],
                timeLocks: [0],
                timeOuts: [2, 3]

            }
            const agreementId = testUtils.generateId()

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(agreement),
                    { from: templateId }
                ),
                'Arguments have wrong length'
            )
        })

        it('should not create agreement with uninitialized template', async () => {
            const did = await registerNewDID()
            const templateId = accounts[5]

            const agreement = {
                did: did,
                conditionTypes: [accounts[3]],
                conditionIds: [testUtils.generateId()],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(agreement),
                    { from: templateId }
                ),
                constants.template.error.templateNotApproved
            )
        })

        it('should not create agreement with proposed template', async () => {
            const templateId = accounts[3]
            await templateStoreManager.proposeTemplate(templateId)

            const agreement = {
                did: constants.did[0],
                conditionTypes: [accounts[3]],
                conditionIds: [constants.bytes32.zero],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(agreement),
                    { from: templateId }
                ),
                constants.template.error.templateNotApproved
            )
        })

        it('should not create agreement with revoked template', async () => {
            const templateId = accounts[4]
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })
            await templateStoreManager.revokeTemplate(templateId, { from: owner })

            const agreement = {
                did: constants.did[0],
                conditionTypes: [accounts[3]],
                conditionIds: [constants.bytes32.zero],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(agreement),
                    { from: templateId }
                ),
                constants.template.error.templateNotApproved
            )
        })

        it('should not create agreement with existing ID', async () => {
            const did = await registerNewDID()

            const agreement = {
                did: did,
                conditionTypes: [common.address],
                conditionIds: [testUtils.generateId()],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            /*
            assert.strictEqual(
                await agreementStoreManager.isAgreementDIDOwner(agreementId, createRole),
                true
            ) */
            const otherAgreement = {
                did: did,
                conditionTypes: [common.address],
                conditionIds: [testUtils.generateId()],
                timeLocks: [2],
                timeOuts: [3]

            }

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(otherAgreement),
                    { from: templateId }
                ),
                constants.error.idAlreadyExists
            )
        })

        it('should return false if weather it invalid DID or owner', async () => {
            const did = await registerNewDID()

            const agreement = {
                did: did,
                conditionTypes: [common.address],
                conditionIds: [testUtils.generateId()],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )
        })
        it('should not create agreement if DID not registered', async () => {
            const agreement = {
                did: did,
                conditionTypes: [accounts[3]],
                conditionIds: [testUtils.generateId()],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await assert.isRejected(
                agreementStoreManager.createAgreement(
                    agreementId,
                    ...Object.values(agreement),
                    { from: templateId }
                ),
                constants.registry.error.didNotRegistered
            )
        })
    })

    describe('get agreement', () => {
        it('successful create should get agreement', async () => {
            const did = await registerNewDID()
            const agreement = {
                did: did,
                conditionTypes: [common.address, common.address],
                conditionIds: [testUtils.generateId(), testUtils.generateId()],
                timeLocks: [0, 1],
                timeOuts: [2, 3]

            }

            // const blockNumber = await common.getCurrentBlockNumber()
            const agreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            // TODO - containSubset
            const storedAgreementTemplateId = await agreementStoreManager.getAgreementTemplate(agreementId)
            expect(storedAgreementTemplateId).to.equal(templateId)
        })

        it('should get multiple agreements for same did & template', async () => {
            const did = await registerNewDID()

            const agreement = {
                did: did,
                conditionTypes: [common.address],
                conditionIds: [testUtils.generateId()],
                timeLocks: [0],
                timeOuts: [2]

            }
            const agreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                agreementId,
                ...Object.values(agreement),
                { from: templateId }
            )

            const otherAgreement = {
                did: did,
                conditionTypes: [common.address],
                conditionIds: [testUtils.generateId()],
                timeLocks: [2],
                timeOuts: [3]

            }
            const otherAgreementId = testUtils.generateId()

            await agreementStoreManager.createAgreement(
                otherAgreementId,
                ...Object.values(otherAgreement),
                { from: templateId }
            )
        })
    })
})
