/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const deployConditions = require('../../helpers/deployConditions.js')
const deployManagers = require('../../helpers/deployManagers.js')
const { getBalance } = require('../../helpers/getBalance.js')
const increaseTime = require('../../helpers/increaseTime.js')
const testUtils = require('../../helpers/utils')
const SignCondition = artifacts.require('SignCondition')

// this template doesn't exist
contract.skip('Stake Agreement integration test', (accounts) => {
    const web3 = global.web3
    let token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        signCondition,
        lockPaymentCondition,
        escrowPaymentCondition

    async function setupTest({
        deployer = accounts[8],
        owner = accounts[9]
    } = {}) {
        ({
            token,
            didRegistry,
            agreementStoreManager,
            conditionStoreManager
        } = await deployManagers(
            deployer,
            owner
        ));

        ({
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

        signCondition = await SignCondition.new({ from: deployer })
        await signCondition.initialize(
            owner,
            conditionStoreManager.address,
            { from: deployer }
        )

        return {
            deployer,
            owner
        }
    }

    async function prepareStakeAgreement({
        initAgreementId = constants.bytes32.one,
        staker = accounts[0],
        stakeAmount = 1000,
        stakePeriod = 5,
        // uses signature as release, could also be hash of secret
        sign = constants.condition.sign.bytes32,
        didSeed = testUtils.generateId(),
        url = constants.registry.url,
        checksum = constants.bytes32.one
    } = {}) {
        // generate IDs from attributes
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])
        const did = await didRegistry.hashDID(didSeed, accounts[0])
        const conditionIdSign = await signCondition.hashValues(sign.message, sign.publicKey)
        const conditionIdLock =
            await lockPaymentCondition.hashValues(did, escrowPaymentCondition.address, token.address, [stakeAmount], [staker])
        const fullConditionIdLock = await lockPaymentCondition.generateId(agreementId, conditionIdLock)
        const fullConditionIdSign = await signCondition.generateId(agreementId, conditionIdSign)
        const conditionIdEscrow =
        await escrowPaymentCondition.hashValues(did, [stakeAmount], [staker], accounts[0], escrowPaymentCondition.address, token.address, fullConditionIdLock, fullConditionIdSign)
        const fullConditionIdEscrow = await escrowPaymentCondition.generateId(agreementId, conditionIdEscrow)

        // construct agreement
        const agreement = {
            initAgreementId,
            did,
            conditionTypes: [
                signCondition.address,
                lockPaymentCondition.address,
                escrowPaymentCondition.address
            ],
            conditionIds: [
                conditionIdSign,
                conditionIdLock,
                conditionIdEscrow
            ],
            timeLocks: [stakePeriod, 0, 0],
            timeOuts: [0, 0, 0]
        }
        return {
            conditionIds: [
                fullConditionIdSign,
                fullConditionIdLock,
                fullConditionIdEscrow
            ],
            agreementId,
            did,
            didSeed,
            agreement,
            stakeAmount,
            staker,
            stakePeriod,
            sign,
            checksum,
            url
        }
    }

    describe('create and fulfill stake agreement', () => {
        it('stake agreement as an escrow with self-sign release', async () => {
            const { owner } = await setupTest()

            const alice = accounts[0]
            // propose and approve account as agreement factory - not for production :)
            // await approveTemplateAccount(owner, alice)

            // prepare: stake agreement
            const { agreementId, did, didSeed, stakeAmount, staker, stakePeriod, sign, checksum, url, agreement, conditionIds } = await prepareStakeAgreement()

            // fill up wallet
            await token.mint(alice, stakeAmount, { from: owner })

            // register DID
            await didRegistry.registerAttribute(didSeed, checksum, [], url)

            // create agreement: as approved account - not for production ;)
            await agreementStoreManager.createAgreement(...Object.values(agreement), { from: accounts[0] })

            // stake: fulfill lock reward
            await token.approve(lockPaymentCondition.address, stakeAmount, { from: alice })

            await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, [stakeAmount], [staker])
            assert.strictEqual(await getBalance(token, alice), 0)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), stakeAmount)

            // unstake: fail to fulfill before stake period
            await assert.isRejected(
                signCondition.fulfill(agreementId, sign.message, sign.publicKey, sign.signature),
                constants.condition.epoch.error.isTimeLocked
            )

            // wait: for stake period
            await increaseTime.mineBlocks(web3, stakePeriod)

            // unstake: waited and fulfill after stake period
            await signCondition.fulfill(agreementId, sign.message, sign.publicKey, sign.signature)
            await escrowPaymentCondition.fulfill(agreementId, did, [stakeAmount], [alice], accounts[0], escrowPaymentCondition.address, token.address, conditionIds[1], conditionIds[0])
            assert.strictEqual(await getBalance(token, alice), stakeAmount)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), 0)
        })
    })
})
