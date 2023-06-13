

// setup contracts

const constants = require('../test/helpers/constants.js')
const deployConditions = require('../test/helpers/deployConditions.js')
const deployManagers = require('../test/helpers/deployManagers.js')
const testUtils = require('../test/helpers/utils')
const ethers = require('ethers')
const fs = require('fs')
const { makeProof, setupEG } = require('../test/helpers/dleq')

async function setup() {
    const web3 = global.web3
    let accounts = await web3.eth.getAccounts()
    let token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        accessTemplate,
        accessProofCondition,
        lockPaymentCondition,
        escrowPaymentCondition


    let deployer = accounts[8]
    let owner = accounts[8];
    console.log(accounts);

    ({
        token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager
    } = await deployManagers(
        deployer,
        owner
    ))

    let accessDLEQCondition
    ({
        accessDLEQCondition,
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
    accessProofCondition = accessDLEQCondition

    accessTemplate = await testUtils.deploy('AccessDLEQTemplate',
        [owner,
            agreementStoreManager.address,
            didRegistry.address,
            accessProofCondition.address,
            lockPaymentCondition.address,
            escrowPaymentCondition.address],
        deployer
    )

    // propose and approve template
    const templateId = accessTemplate.address

    await templateStoreManager.proposeTemplate(templateId)
    await templateStoreManager.approveTemplate(templateId, { from: owner })

    console.log("deploy finished")

    // setup the network public key
    let config = JSON.parse(fs.readFileSync('server.json'))
    console.log("setting key", config.netkey)

    await accessProofCondition.setNetworkPublicKey(config.netkey, { from: owner })

    fs.writeFileSync('frost-contracts.json', JSON.stringify({
        address: accessProofCondition.address,
        abi: accessProofCondition.abi,
    }))

    ///////////////////////////////////////////////////////////////////////////////////////////////////////

    /// make a test request
    async function prepareEscrowAgreementMultipleEscrow({
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
        console.log("???")
        let provider = config.netkey
        const info1 = await setupEG()
        const { secretId, buyer, reencrypt } = info1
        const cipher = 1234n

        console.log("???")

        const did = await didRegistry.hashDID(didSeed, receivers[0])

        const agreementId = await agreementStoreManager.agreementId(initAgreementId, accounts[0])

        // generate IDs from attributes
        const conditionIdLock =
            await lockPaymentCondition.hashValues(did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers)
        const conditionIdAccess =
            await accessProofCondition.hashValues(cipher, secretId, provider, buyer)
        const fullConditionIdLock = await lockPaymentCondition.generateId(agreementId, conditionIdLock)
        const fullConditionIdAccess = await accessProofCondition.generateId(agreementId, conditionIdAccess)
        const conditionIdEscrow =
            await escrowPaymentCondition.hashValues(did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, fullConditionIdLock, fullConditionIdAccess)
        const fullConditionIdEscrow = await escrowPaymentCondition.generateId(agreementId, conditionIdEscrow)

        const { proof } = await makeProof(info1, fullConditionIdAccess)

        // params for condition
        const data = [
            cipher, secretId, provider, buyer, reencrypt, proof
        ]
        const netdata = [
            reencrypt, proof
        ]

        const coder = new ethers.utils.AbiCoder()
        const uint = 'uint'

        const params = [
            coder.encode(
                [uint, uint, uint, uint, uint, uint, uint],
                [cipher, secretId[0], secretId[1], provider[0], provider[1], buyer[0], buyer[1]]
            ),
            coder.encode(
                ['bytes32', 'address', 'address', 'uint256[]', 'address[]'],
                [did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers]
            ),
            coder.encode(
                ['bytes32', 'uint256[]', 'address[]', 'address', 'address', 'address', 'bytes32', 'bytes32[]'],
                [did, escrowAmounts, receivers, sender, escrowPaymentCondition.address, token.address, fullConditionIdLock, [fullConditionIdAccess]]
            )
        ]

        // construct agreement
        const agreement = {
            initAgreementId,
            did,
            conditionIds: [
                conditionIdAccess,
                conditionIdLock,
                conditionIdEscrow
            ],
            timeLocks: [timeLockAccess, 0, 0],
            timeOuts: [timeOutAccess, 0, 0],
            consumer: sender
        }
        return {
            conditionIds: [
                fullConditionIdAccess,
                fullConditionIdLock,
                fullConditionIdEscrow
            ],
            params,
            agreementId,
            did,
            data,
            didSeed,
            agreement,
            sender,
            receivers,
            escrowAmounts,
            timeLockAccess,
            timeOutAccess,
            checksum,
            url,
            secretId,
            provider,
            buyer,
            netdata,
            reencrypt,
            proof,
            cipher
        }
    }

    const { agreementId, data, did, didSeed, secretId, params, agreement, sender, receivers, escrowAmounts, checksum, url, conditionIds } = await prepareEscrowAgreementMultipleEscrow()
    const receiver = receivers[0]
    const totalAmount = escrowAmounts[0] + escrowAmounts[1]
    // register DID
    await didRegistry.registerAttribute(didSeed, checksum, [], url, { from: receiver })

    // create agreement, fulfill enough to create a request for network
    await accessTemplate.createAgreement(...Object.values(agreement))

    await token.mint(sender, totalAmount, { from: owner })
    await token.approve(lockPaymentCondition.address, totalAmount, { from: sender })
    await lockPaymentCondition.fulfill(agreementId, did, escrowPaymentCondition.address, token.address, escrowAmounts, receivers, { from: sender })
    await accessProofCondition.addSecret(secretId, { from: receiver })
    const pid = await accessProofCondition.pointId(secretId)
    await accessProofCondition.addPrice(pid, 1, token.address, 20, { from: receiver })
    await accessProofCondition.authorizeAccessTemplate(agreementId, params, 0)

    console.log("request created successfully")

    process.exit(0)

}

setup()
