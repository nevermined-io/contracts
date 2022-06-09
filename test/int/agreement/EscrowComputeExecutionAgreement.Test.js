/* eslint-env mocha */
/* eslint-disable no-console */
/* global contract, describe, it, expect */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const constants = require('../../helpers/constants.js')
const deployConditions = require('../../helpers/deployConditions.js')
const deployManagers = require('../../helpers/deployManagers.js')
const { getTokenBalance, getCheckpoint } = require('../../helpers/getBalance.js')
const increaseTime = require('../../helpers/increaseTime.js')
const testUtils = require('../../helpers/utils')

contract('Escrow Compute Execution Template integration test', (accounts) => {
    const web3 = global.web3
    let token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        escrowComputeExecutionTemplate,
        computeExecutionCondition,
        lockPaymentCondition,
        escrowPaymentCondition

    async function setupTest({
        deployer = accounts[8],
        owner = accounts[8]
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
            computeExecutionCondition,
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

        escrowComputeExecutionTemplate = await testUtils.deploy('EscrowComputeExecutionTemplate', [
            owner,
            agreementStoreManager.address,
            didRegistry.address,
            computeExecutionCondition.address,
            lockPaymentCondition.address,
            escrowPaymentCondition.address
        ], deployer)

        // propose and approve template
        const templateId = escrowComputeExecutionTemplate.address

        if (testUtils.deploying) {
            await templateStoreManager.proposeTemplate(templateId)
            await templateStoreManager.approveTemplate(templateId, { from: owner })
        }

        return {
            templateId,
            owner
        }
    }

    async function prepareEscrowAgreement({
        initAgreementId = testUtils.generateId(),
        sender = accounts[0],
        receivers = [accounts[2], accounts[3]],
        escrowAmounts = [11, 4],
        timeLockAccess = 0,
        timeOutAccess = 0,
        didSeed = testUtils.generateId(),
        url = constants.registry.url,
        checksum = constants.bytes32.one
    } = {}) {
        const agreementId = await agreementStoreManager.agreementId(initAgreementId, sender)
        const did = await didRegistry.hashDID(didSeed, receivers[0])
        // generate IDs from attributes
        const conditionIdLock =
            await lockPaymentCondition.hashValues(did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers)
        const conditionIdCompute = await computeExecutionCondition.hashValues(did, receivers[0])
        const fullConditionIdLock = await lockPaymentCondition.generateId(agreementId, conditionIdLock)
        const fullConditionIdCompute = await computeExecutionCondition.generateId(agreementId, conditionIdCompute)
        const conditionIdEscrow =
            await escrowPaymentCondition.hashValues(did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, fullConditionIdLock, fullConditionIdCompute)
        const fullConditionIdEscrow = await escrowPaymentCondition.generateId(agreementId, conditionIdEscrow)

        // construct agreement
        const agreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdCompute,
                conditionIdLock,
                conditionIdEscrow
            ],
            timeLocks: [timeLockAccess, 0, 0],
            timeOuts: [timeOutAccess, 0, 0],
            consumer: sender
        }
        return {
            conditionIds: [
                fullConditionIdCompute,
                fullConditionIdLock,
                fullConditionIdEscrow
            ],
            agreementId,
            did,
            didSeed,
            agreement,
            sender,
            receivers,
            escrowAmounts,
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
            const { agreementId, did, didSeed, agreement, sender, receivers, escrowAmounts, checksum, url, conditionIds } = await prepareEscrowAgreement()
            const totalAmount = escrowAmounts[0] + escrowAmounts[1]
            const receiver = receivers[0]

            const checkpoint = await getCheckpoint(token, [sender, receiver, receivers[1], lockPaymentCondition.address, escrowPaymentCondition.address])
            const getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

            // register DID
            await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: receiver })

            // create agreement
            await escrowComputeExecutionTemplate.createAgreement(...Object.values(agreement))

            // check state of agreement and conditions
            // expect((await agreementStoreManager.getAgreement(agreementId)).did).to.equal(did)

            const conditionTypes = await escrowComputeExecutionTemplate.getConditionTypes()
            await Promise.all(conditionIds.map(async (conditionId, i) => {
                const storedCondition = await conditionStoreManager.getCondition(conditionId)
                expect(storedCondition.typeRef).to.equal(conditionTypes[i])
                expect(storedCondition.state.toNumber()).to.equal(constants.condition.state.unfulfilled)
            }))

            // fill up wallet
            await token.mint(sender, totalAmount, { from: owner })

            assert.strictEqual(await getBalance(token, sender), totalAmount)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, receiver), 0)

            // fulfill lock reward
            await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
            await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })

            assert.strictEqual(await getBalance(token, sender), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), totalAmount)
            assert.strictEqual(await getBalance(token, receiver), 0)

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            // fulfill access
            await computeExecutionCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.fulfilled)

            // get reward
            await escrowPaymentCondition.fulfill(agreementId, did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, conditionIds[1], conditionIds[0], { from: receiver })

            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                constants.condition.state.fulfilled
            )

            assert.strictEqual(await getBalance(token, sender), 0)
            assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, receivers[0]), escrowAmounts[0])
        })

        it('should create escrow agreement and abort after timeout', async () => {
            const { owner } = await setupTest()

            // prepare: escrow agreement
            const { agreementId, did, didSeed, agreement, sender, receivers, escrowAmounts, checksum, url, timeOutAccess, conditionIds } = await prepareEscrowAgreement({ timeOutAccess: 10 })
            const totalAmount = escrowAmounts[0] + escrowAmounts[1]
            const receiver = receivers[0]

            const checkpoint = await getCheckpoint(token, [sender, receiver, receivers[1], lockPaymentCondition.address, escrowPaymentCondition.address])
            const getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

            // register DID
            await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: receiver })

            // create agreement
            await escrowComputeExecutionTemplate.createAgreement(...Object.values(agreement))

            // fill up wallet
            await token.mint(sender, totalAmount, { from: owner })

            // fulfill lock reward
            await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
            await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            // No update since access is not fulfilled yet
            // refund
            await assert.isRejected(escrowPaymentCondition.fulfill(agreementId, did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, conditionIds[1], conditionIds[0], { from: receiver }))

            // wait: for time out
            await increaseTime.mineBlocks(web3, timeOutAccess)

            // abort: fulfill access after timeout
            await computeExecutionCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.aborted)

            // refund
            await escrowPaymentCondition.fulfill(agreementId, did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, conditionIds[1], conditionIds[0], { from: sender })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                constants.condition.state.fulfilled
            )
            assert.strictEqual(await getBalance(token, receivers[0]), 0)
            assert.strictEqual(await getBalance(token, receivers[1]), 0)
            assert.strictEqual(await getBalance(token, escrowPaymentCondition.address), 0)
            assert.strictEqual(await getBalance(token, sender), totalAmount)
        })
    })

    describe('create and fulfill escrow agreement with access secret store and timeLock', () => {
        it('should create escrow agreement and fulfill', async () => {
            const { owner } = await setupTest()

            // prepare: escrow agreement
            const { agreementId, did, didSeed, agreement, sender, receivers, escrowAmounts, checksum, url, timeLockAccess, conditionIds } = await prepareEscrowAgreement({ timeLockAccess: 10 })
            const totalAmount = escrowAmounts[0] + escrowAmounts[1]
            const receiver = receivers[0]

            const checkpoint = await getCheckpoint(token, [sender, receiver, receivers[1], lockPaymentCondition.address, escrowPaymentCondition.address])
            const getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

            // register DID
            await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: receiver })
            // fill up wallet
            await token.mint(sender, totalAmount, { from: owner })

            // create agreement
            await escrowComputeExecutionTemplate.createAgreement(...Object.values(agreement))

            // fulfill lock reward
            await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
            await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[1])).toNumber(),
                constants.condition.state.fulfilled)

            // fail: fulfill access before time lock
            await assert.isRejected(
                computeExecutionCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver }),
                constants.condition.epoch.error.isTimeLocked
            )

            // wait: for time lock
            await increaseTime.mineBlocks(web3, timeLockAccess)

            // execute: fulfill access after time lock
            await computeExecutionCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver })
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[0])).toNumber(),
                constants.condition.state.fulfilled)
            expect(await computeExecutionCondition.wasComputeTriggered(agreement.did, receiver)).to.equal(true)

            // execute payment
            await escrowPaymentCondition.fulfill(
                agreementId,
                agreement.did,
                escrowAmounts,
                receivers,
                sender,
                escrowPaymentCondition.address,
                token.address,
                conditionIds[1],
                conditionIds[0],
                { from: receiver }
            )
            assert.strictEqual(
                (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                constants.condition.state.fulfilled
            )
            assert.strictEqual(await getBalance(token, sender), 0)
            assert.strictEqual(await getBalance(token, receivers[0]), escrowAmounts[0])
        })

        describe('drain escrow reward', () => {
            it('should create escrow agreement and fulfill', async () => {
                const { owner } = await setupTest()

                // prepare: escrow agreement
                const { agreementId, did, didSeed, agreement, sender, receivers, escrowAmounts, checksum, url, conditionIds } = await prepareEscrowAgreement()
                const totalAmount = escrowAmounts[0] + escrowAmounts[1]
                const receiver = receivers[0]

                const checkpoint = await getCheckpoint(token, [sender, receiver, receivers[1], lockPaymentCondition.address, escrowPaymentCondition.address])
                const getBalance = async (a, b) => getTokenBalance(a, b, checkpoint)

                // register DID
                await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: receiver })

                // create agreement
                await escrowComputeExecutionTemplate.createAgreement(...Object.values(agreement))

                const { agreementId: agreementId2, agreement: agreement2, conditionIds: conditionIds2 } = await prepareEscrowAgreement(
                    { agreementId: constants.bytes32.two, didSeed: didSeed }
                )
                const agreement2Amounts = [escrowAmounts[0] * 2, escrowAmounts[1]]
                const newEscrowId = await escrowPaymentCondition.hashValues(
                    agreement2.did,
                    agreement2Amounts,
                    receivers,
                    sender,
                    escrowPaymentCondition.address,
                    token.address,
                    conditionIds2[1],
                    conditionIds2[0])
                agreement2.conditionIds[2] = newEscrowId
                conditionIds2[2] = await escrowPaymentCondition.generateId(agreementId2, newEscrowId)

                // create agreement2
                await escrowComputeExecutionTemplate.createAgreement(...Object.values(agreement2))

                // fill up wallet
                await token.mint(sender, totalAmount * 2, { from: owner })

                // fulfill lock reward
                await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
                await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })

                await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
                await lockPaymentCondition.fulfill(agreementId2, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })
                // fulfill access
                await computeExecutionCondition.fulfill(agreementId, agreement.did, receiver, { from: receiver })
                await computeExecutionCondition.fulfill(agreementId2, agreement2.did, receiver, { from: receiver })

                // get reward
                await assert.isRejected(
                    escrowPaymentCondition.fulfill(agreementId2, [totalAmount * 2], [receiver], sender, token.address, conditionIds2[1], conditionIds2[0], { from: receiver })
                )

                await assert.isRejected(
                    escrowPaymentCondition.fulfill(agreementId2, agreement2.did, agreement2Amounts, receivers, sender, token.address, conditionIds2[1], conditionIds2[0], { from: receiver })
                )

                await escrowPaymentCondition.fulfill(agreementId, agreement.did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, conditionIds[1], conditionIds[0], { from: receiver })
                assert.strictEqual(
                    (await conditionStoreManager.getConditionState(conditionIds[2])).toNumber(),
                    constants.condition.state.fulfilled
                )

                assert.strictEqual(await getBalance(token, sender), 0)
                assert.strictEqual(await getBalance(token, lockPaymentCondition.address), 0)
                assert.strictEqual(await getBalance(token, receivers[0]), escrowAmounts[0])
            })
        })
    })
})
