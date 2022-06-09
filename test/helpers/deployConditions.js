/* global artifacts */
const DisputeManager = artifacts.require('PlonkVerifier')

const testUtils = require('./utils')

const deployConditions = async function(
    deployer,
    owner,
    agreementStoreManager,
    conditionStoreManager,
    didRegistry,
    token
) {
    const lockPaymentCondition = await testUtils.deploy('LockPaymentCondition', [owner,
        conditionStoreManager.address,
        didRegistry.address
    ], deployer)

    const accessCondition = await testUtils.deploy('AccessCondition', [owner,
        conditionStoreManager.address,
        agreementStoreManager.address], deployer)

    const disputeManager = await DisputeManager.new({ from: deployer })

    const accessProofCondition = await testUtils.deploy('AccessProofCondition', [owner,
        conditionStoreManager.address,
        agreementStoreManager.address,
        disputeManager.address
    ], deployer)

    const escrowPaymentCondition = await testUtils.deploy(
        'EscrowPaymentCondition',
        [owner, conditionStoreManager.address],
        deployer
    )

    const computeExecutionCondition = await testUtils.deploy('ComputeExecutionCondition', [owner,
        conditionStoreManager.address,
        agreementStoreManager.address],
    deployer
    )

    if (testUtils.deploying) {
        await conditionStoreManager.grantProxyRole(
            escrowPaymentCondition.address,
            { from: owner }
        )
    }

    return {
        accessCondition,
        accessProofCondition,
        escrowPaymentCondition,
        escrowCondition: escrowPaymentCondition,
        lockPaymentCondition,
        computeExecutionCondition
    }
}

module.exports = deployConditions
