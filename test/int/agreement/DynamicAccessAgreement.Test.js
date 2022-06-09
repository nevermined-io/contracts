/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, expect, BigInt */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const testUtils = require('../../helpers/utils')

const DynamicAccessTemplate = artifacts.require('DynamicAccessTemplate')
const NFTHolderCondition = artifacts.require('NFTHolderCondition')

const constants = require('../../helpers/constants.js')
const deployConditions = require('../../helpers/deployConditions.js')
const deployManagers = require('../../helpers/deployManagers.js')

contract('Dynamic Access Template integration test', (accounts) => {
    let token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        dynamicAccessTemplate,
        accessCondition,
        nft,
        nftHolderCondition

    const Activities = {
        GENERATED: '0x1',
        USED: '0x2'
    }

    async function setupTest({
        deployer = accounts[8],
        owner = accounts[9]
    } = {}) {
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager,
            templateStoreManager,
            nft
        } = await deployManagers(
            deployer,
            owner
        ));

        ({
            accessCondition
        } = await deployConditions(
            deployer,
            owner,
            agreementStoreManager,
            conditionStoreManager,
            didRegistry,
            token
        ))

        dynamicAccessTemplate = await DynamicAccessTemplate.new()
        await dynamicAccessTemplate.methods['initialize(address,address,address)'](
            owner,
            agreementStoreManager.address,
            didRegistry.address,
            { from: deployer }
        )

        nftHolderCondition = await NFTHolderCondition.new()
        await nftHolderCondition.initialize(
            owner,
            conditionStoreManager.address,
            nft.address,
            { from: owner }
        )

        // propose and approve template
        const templateId = dynamicAccessTemplate.address
        await templateStoreManager.proposeTemplate(templateId)
        await templateStoreManager.approveTemplate(templateId, { from: owner })

        return {
            templateId,
            owner
        }
    }

    async function prepareAgreement({
        initAgreementId = testUtils.generateId(),
        holder = accounts[0],
        receiver = accounts[1],
        nftAmount = 1,
        timeLockAccess = 0,
        timeOutAccess = 0,
        didSeed = constants.did[0],
        url = constants.registry.url,
        checksum = constants.bytes32.one
    } = {}) {
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, holder)
        const did = await didRegistry.hashDID(didSeed, receiver)
        // generate IDs from attributes
        const conditionIdAccess = await accessCondition.hashValues(did, receiver)
        const conditionIdNft = await nftHolderCondition.hashValues(did, holder, nftAmount)

        // construct agreement
        const agreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdAccess,
                conditionIdNft
            ],
            timeLocks: [timeLockAccess, 0],
            timeOuts: [timeOutAccess, 0],
            consumer: receiver
        }
        return {
            conditionIds: [
                await accessCondition.generateId(agreementId, conditionIdAccess),
                await nftHolderCondition.generateId(agreementId, conditionIdNft)
            ],
            agreementId,
            didSeed,
            agreement,
            holder,
            receiver,
            nftAmount,
            timeLockAccess,
            timeOutAccess,
            checksum,
            url
        }
    }

    describe('create and fulfill escrow agreement', () => {
        it('should create escrow agreement and fulfill', async () => {
            const { owner } = await setupTest()

            // prepare: escrow agreement
            const { agreementId, didSeed, agreement, holder, receiver, nftAmount, checksum, url, conditionIds } = await prepareAgreement()

            // register DID
            await didRegistry.registerMintableDID(
                didSeed, checksum, [], url, 10, 0, Activities.GENERATED, '', { from: receiver })

            // Mint and Transfer
            await didRegistry.mint(agreement.did, 10, { from: receiver })
            await nft.safeTransferFrom(
                receiver, holder, BigInt(agreement.did), 10, '0x', { from: receiver })

            // Conditions need to be added to the template
            await assert.isRejected(
                dynamicAccessTemplate.createAgreement(...Object.values(agreement)),
                'Arguments have wrong length'
            )

            await dynamicAccessTemplate.addTemplateCondition(accessCondition.address, { from: owner })
            await dynamicAccessTemplate.addTemplateCondition(nftHolderCondition.address, { from: owner })
            const templateConditionTypes = await dynamicAccessTemplate.getConditionTypes()
            assert.strictEqual(2, templateConditionTypes.length)

            // create agreement
            await dynamicAccessTemplate.createAgreement(...Object.values(agreement))

            // check state of agreement and conditions
            const conditionTypes = await dynamicAccessTemplate.getConditionTypes()
            await Promise.all(conditionIds.map(async (conditionId, i) => {
                const storedCondition = await conditionStoreManager.getCondition(conditionId)
                expect(storedCondition.typeRef).to.equal(conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
            }))

            // fulfill nft condition
            await nftHolderCondition.fulfill(agreementId, agreement.did, holder, nftAmount)

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            // fulfill access
            await accessCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.fulfilled)
        })
    })
})
