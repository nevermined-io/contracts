/* eslint-disable no-console */
const ZeroAddress = '0x0000000000000000000000000000000000000000'
const { ethers, upgrades, web3 } = require('hardhat')
const { writeArtifact, exportLibraryArtifact } = require('./artifacts')

function getSignatureOfMethod(
    contractInstace,
    methodName,
    args
) {
    const methods = contractInstace.interface.fragments.filter(
        f => f.name === methodName
    )
    const foundMethod =
        methods.find(f => f.inputs.length === args.length) || methods[0]
    if (!foundMethod) {
        throw new Error(`Method "${methodName}" not found in contract`)
    }
    return foundMethod.format()
}

async function doDeploy(contractName, signer, args, isCore) {
    const methodSignature = getSignatureOfMethod(signer, 'initialize', args)

    if (!isCore || process.env.NO_PROXY === 'true') {
        const c = await signer.deploy()
        await c.deployed()
        const tx = await c[methodSignature](...args)
        await tx.wait()
        await exportLibraryArtifact(contractName, c)
        return c
    } else {
        const c = await upgrades.deployProxy(signer, args, { unsafeAllowLinkedLibraries: true, initializer: methodSignature })
        await c.deployed()
        await writeArtifact(contractName, c)
        return c
    }
}

async function zosCreate({ contract, args, libraries, verbose, ctx, isCore }) {
    const { cache, addresses, roles, deployCore } = ctx
    if (isCore && !deployCore) {
        if (!addresses[contract]) {
            console.error(`Error: core contract ${contract} is not in cache`)
            process.exit(1)
        }
        console.log(`Contract ${contract} found from cache`)
        return addresses[contract]
    } else if (addresses[contract]) {
        console.log(`Contract ${contract} found from cache`)
        const C = await ethers.getContractFactory(contract, { libraries })
        cache[contract] = C.attach(addresses[contract]).connect(roles.deployerSigner)
        return addresses[contract]
    } else {
        const C = await ethers.getContractFactory(contract, { libraries })
        const c = await doDeploy(contract, C.connect(roles.deployerSigner), args, isCore)
        cache[contract] = c
        if (verbose) {
            console.log(`${contract}: ${c.address}`)
        }
        addresses[contract] = c.address
        return c.address
    }
}

async function deployLibrary(name, addresses, cache, signer) {
    if (addresses[name]) {
        console.log(`Contract ${name} found from cache`)
        const C = await ethers.getContractFactory(name, signer)
        cache[name] = C.attach(addresses[name])
        return addresses[name]
    } else {
        const factory = await ethers.getContractFactory(name, signer)
        const library = await factory.deploy()
        const h1 = library.deployTransaction.hash
        await library.deployed()
        const address = (await web3.eth.getTransactionReceipt(h1)).contractAddress
        addresses[name] = address
        cache[name] = library
        return address
    }
}

async function initializeContracts({
    contracts,
    core,
    roles,
    addresses,
    deployCore,
    verbose = true
} = {}) {
    contracts = contracts.concat(core)
    // Deploy all implementations in the specified network.
    // NOTE: Creates another zos.<network_name>.json file, specific to the network used,
    // which keeps track of deployed addresses, etc.

    // Here we run initialize which replace contract constructors
    // Since each contract initialize function could be different we can not use a loop
    // NOTE: A dapp could now use the address of the proxy specified in zos.<network_name>.json
    // instance=MyContract.at(proxyAddress)
    const addressBook = {}
    const cache = {}
    const ctx = { cache, addresses, roles, deployCore }

    // WARNING!
    // use this only when deploying a selective portion of the contracts
    // Only use this if you know what you do, otherwise it can break the contracts deployed
    const proxies = {
        // if the application should be deployed with another token set the address here!
        // Token: '0xc778417e063141139fce010982780140aa0cd5ab'
    }

    // We load some environment variables that affect the configuration of a Nevermined deployment
    // This configuration can be modified later via interaction with the NeverminedConfig contract
    const configMarketplaceFee = Number(process.env.NVM_MARKETPLACE_FEE || '0')
    const configFeeReceiver = process.env.NVM_RECEIVER_FEE || ZeroAddress

    console.log(`Fee env: ${configMarketplaceFee}`)

    if (configMarketplaceFee < 0 || configMarketplaceFee > 1000000) {
        console.error('NVM_MARKETPLACE_FEE can not be lower than 0 or higher than 1000000 (100%)\nPlease refer to the ReleaseProcess.md documentation')
        process.exit(1)
    }

    if (configMarketplaceFee > 0 && configFeeReceiver === ZeroAddress) {
        console.error('If NVM_MARKETPLACE_FEE is higher than 0 you need to specify a valid address to receive the marketplace fees')
        process.exit(1)
    }

    console.log('NVM Config: [governorAddress] = ' + roles.governorWallet)
    console.log('NVM Config: [marketplaceFee] = ' + configMarketplaceFee)
    console.log('NVM Config: [feeReceiver] = ' + configFeeReceiver)

    // returns either the address from the address book or the address of the manual set proxies
    const getAddress = (contract) => {
        return addressBook[contract] || proxies[contract]
    }

    addressBook.NeverminedConfig = await zosCreate({
        contract: 'NeverminedConfig',
        ctx,
        args: [roles.deployer, roles.deployer, false],
        isCore: true,
        verbose
    })

    addressBook.DIDRegistry = await zosCreate({
        contract: 'DIDRegistry',
        ctx,
        args: [roles.deployer, addressBook.NFT1155Upgradeable || ZeroAddress, addressBook.NFT721Upgradeable || ZeroAddress, addressBook.NeverminedConfig || ZeroAddress, ZeroAddress],
        isCore: true,
        verbose
    })

    addressBook.StandardRoyalties = await zosCreate({
        contract: 'StandardRoyalties',
        ctx,
        args: [addressBook.DIDRegistry],
        isCore: true,
        verbose
    })

    addressBook.NFT1155Upgradeable = await zosCreate({
        contract: 'NFT1155Upgradeable',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('DIDRegistry'),
            'Nevermined NFT-1155',
            'NVM',
            '',
            getAddress('NeverminedConfig'),
        ],
        isCore: true,
        verbose
    })
    addressBook.NFT721Upgradeable = await zosCreate({
        contract: 'NFT721Upgradeable',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('DIDRegistry'),
            'Nevermined NFT-721',
            'NVM',
            '',
            0,
            getAddress('NeverminedConfig'),
        ],
        isCore: true,
        verbose
    })
    addressBook.NFT721SubscriptionUpgradeable = await zosCreate({
        contract: 'NFT721SubscriptionUpgradeable',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('DIDRegistry'),
            'Nevermined NFT-721',
            'NVM',
            '',
            0,
            getAddress('NeverminedConfig'),
        ],
        isCore: true,
        verbose
    })

    addressBook.NFT1155SubscriptionUpgradeable = await zosCreate({
        contract: 'NFT1155SubscriptionUpgradeable',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('DIDRegistry'),
            'Nevermined Smart Subscription',
            'NVM',
            '',
            getAddress('NeverminedConfig'),
        ],
        isCore: true,
        verbose
    })

    // testnet only!
    if (contracts.indexOf('NeverminedToken') > -1) {
        addressBook.NeverminedToken = await zosCreate({
            contract: 'NeverminedToken',
            isCore: true,
            ctx,
            args: [
                roles.ownerWallet,
                roles.deployer
            ],
            verbose
        })

        // propagate the token address it is used somewhere else
        proxies.Token = addressBook.NeverminedToken
    }

    // testnet only!
    if (
        contracts.indexOf('Dispenser') > -1 &&
        getAddress('Token')
    ) {
        addressBook.Dispenser = await zosCreate({
            contract: 'Dispenser',
            ctx,
            args: [
                getAddress('Token'),
                roles.ownerWallet
            ],
            verbose
        })
    }

    addressBook.ConditionStoreManager = await zosCreate({
        contract: 'ConditionStoreManager',
        ctx,
        args: [roles.deployer, roles.deployer, getAddress('NeverminedConfig')],
        verbose
    })

    proxies.PlonkVerifier = await deployLibrary('PlonkVerifier', addresses, cache, roles.deployerSigner)

    proxies.AaveCreditVault = await deployLibrary('AaveCreditVault', addresses, cache, roles.deployerSigner)

    addressBook.TemplateStoreManager = await zosCreate({
        contract: 'TemplateStoreManager',
        ctx,
        args: [roles.deployer],
        verbose
    })

    addressBook.EscrowPaymentCondition = await zosCreate({
        contract: 'EscrowPaymentCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })

    addressBook.SignCondition = await zosCreate({
        contract: 'SignCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })

    addressBook.HashLockCondition = await zosCreate({
        contract: 'HashLockCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })

    addressBook.ThresholdCondition = await zosCreate({
        contract: 'ThresholdCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })

    addressBook.WhitelistingCondition = await zosCreate({
        contract: 'WhitelistingCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.NFT721HolderCondition = await zosCreate({
        contract: 'NFT721HolderCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.NFT721LockCondition = await zosCreate({
        contract: 'NFT721LockCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.NFT721EscrowPaymentCondition = await zosCreate({
        contract: 'NFT721EscrowPaymentCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.NFTEscrowPaymentCondition = await zosCreate({
        contract: 'NFTEscrowPaymentCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.AaveBorrowCondition = await zosCreate({
        contract: 'AaveBorrowCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.AaveCollateralDepositCondition = await zosCreate({
        contract: 'AaveCollateralDepositCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.AaveCollateralWithdrawCondition = await zosCreate({
        contract: 'AaveCollateralWithdrawCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })
    addressBook.AaveRepayCondition = await zosCreate({
        contract: 'AaveRepayCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager')
        ],
        verbose
    })

    addressBook.AgreementStoreManager = await zosCreate({
        contract: 'AgreementStoreManager',
        ctx,
        args: [
            roles.deployer,
            getAddress('ConditionStoreManager'),
            getAddress('TemplateStoreManager'),
            getAddress('DIDRegistry')
        ],
        verbose
    })
    addressBook.RewardsDistributor = await zosCreate({
        contract: 'RewardsDistributor',
        ctx,
        args: [
            getAddress('DIDRegistry'),
            getAddress('ConditionStoreManager'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.LockPaymentCondition = await zosCreate({
        contract: 'LockPaymentCondition',
        ctx,
        args: [
            roles.deployer,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry')
        ],
        verbose
    })
    addressBook.TransferDIDOwnershipCondition = await zosCreate({
        contract: 'TransferDIDOwnershipCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry')
        ],
        verbose
    })
    addressBook.NFTAccessCondition = await zosCreate({
        contract: 'NFTAccessCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry')
        ],
        verbose
    })
    addressBook.AccessProofCondition = await zosCreate({
        contract: 'AccessProofCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('PlonkVerifier')
        ],
        verbose
    })
    addressBook.AccessDLEQCondition = await zosCreate({
        contract: 'AccessDLEQCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('LockPaymentCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.NFTHolderCondition = await zosCreate({
        contract: 'NFTHolderCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('NFT1155Upgradeable')
        ],
        verbose
    })
    addressBook.NFTLockCondition = await zosCreate({
        contract: 'NFTLockCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('NFT1155Upgradeable')
        ],
        verbose
    })

    addressBook.TransferNFTCondition = await zosCreate({
        contract: 'TransferNFTCondition',
        ctx,
        args: [
            roles.deployer,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('NFT1155Upgradeable'),
            ZeroAddress
        ],
        verbose
    })
    addressBook.AccessCondition = await zosCreate({
        contract: 'AccessCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('AgreementStoreManager')
        ],
        verbose
    })
    addressBook.ComputeExecutionCondition = await zosCreate({
        contract: 'ComputeExecutionCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('AgreementStoreManager')
        ],
        verbose
    })

    addressBook.TransferNFT721Condition = await zosCreate({
        contract: 'TransferNFT721Condition',
        ctx,
        args: [
            roles.deployer,
            getAddress('ConditionStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('NFT721Upgradeable'),
            getAddress('LockPaymentCondition')
        ],
        verbose
    })
    addressBook.DistributeNFTCollateralCondition = await zosCreate({
        contract: 'DistributeNFTCollateralCondition',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('ConditionStoreManager'),
            getAddress('NFT721LockCondition')
        ],
        verbose
    })
    addressBook.AccessTemplate = await zosCreate({
        contract: 'AccessTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('AccessCondition'),
            getAddress('LockPaymentCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.AccessProofTemplate = await zosCreate({
        contract: 'AccessProofTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('AccessProofCondition'),
            getAddress('LockPaymentCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.AccessDLEQTemplate = await zosCreate({
        contract: 'AccessDLEQTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('AccessDLEQCondition'),
            getAddress('LockPaymentCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.NFTAccessProofTemplate = await zosCreate({
        contract: 'NFTAccessProofTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFTHolderCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })
    addressBook.NFTAccessDLEQTemplate = await zosCreate({
        contract: 'NFTAccessDLEQTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFTHolderCondition'),
            getAddress('AccessDLEQCondition')
        ],
        verbose
    })
    addressBook.NFTAccessSwapTemplate = await zosCreate({
        contract: 'NFTAccessSwapTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFTLockCondition'),
            getAddress('NFTEscrowPaymentCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })
    addressBook.NFTSalesWithAccessTemplate = await zosCreate({
        contract: 'NFTSalesWithAccessTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFTCondition'),
            getAddress('EscrowPaymentCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })

    addressBook.NFTSalesWithDLEQTemplate = await zosCreate({
        contract: 'NFTSalesWithDLEQTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFTCondition'),
            getAddress('EscrowPaymentCondition'),
            getAddress('AccessDLEQCondition')
        ],
        verbose
    })
    addressBook.NFT721AccessProofTemplate = await zosCreate({
        contract: 'NFT721AccessProofTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFT721HolderCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })
    addressBook.NFT721AccessDLEQTemplate = await zosCreate({
        contract: 'NFT721AccessDLEQTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFT721HolderCondition'),
            getAddress('AccessDLEQCondition')
        ],
        verbose
    })
    addressBook.NFT721AccessSwapTemplate = await zosCreate({
        contract: 'NFT721AccessSwapTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFT721LockCondition'),
            getAddress('NFT721EscrowPaymentCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })
    addressBook.NFT721SalesWithAccessTemplate = await zosCreate({
        contract: 'NFT721SalesWithAccessTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFT721Condition'),
            getAddress('EscrowPaymentCondition'),
            getAddress('AccessProofCondition')
        ],
        verbose
    })
    addressBook.NFT721SalesWithDLEQTemplate = await zosCreate({
        contract: 'NFT721SalesWithDLEQTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFT721Condition'),
            getAddress('EscrowPaymentCondition'),
            getAddress('AccessDLEQCondition')
        ],
        verbose
    })

    addressBook.EscrowComputeExecutionTemplate = await zosCreate({
        contract: 'EscrowComputeExecutionTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('DIDRegistry'),
            getAddress('ComputeExecutionCondition'),
            getAddress('LockPaymentCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.NFTAccessTemplate = await zosCreate({
        contract: 'NFTAccessTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFTHolderCondition'),
            getAddress('NFTAccessCondition')
        ],
        verbose
    })
    addressBook.NFT721AccessTemplate = await zosCreate({
        contract: 'NFT721AccessTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFT721HolderCondition'),
            getAddress('NFTAccessCondition')
        ],
        verbose
    })
    addressBook.NFTSalesTemplate = await zosCreate({
        contract: 'NFTSalesTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFTCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.NFT721SalesTemplate = await zosCreate({
        contract: 'NFT721SalesTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferNFT721Condition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.DIDSalesTemplate = await zosCreate({
        contract: 'DIDSalesTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('LockPaymentCondition'),
            getAddress('TransferDIDOwnershipCondition'),
            getAddress('EscrowPaymentCondition')
        ],
        verbose
    })
    addressBook.AaveCreditTemplate = await zosCreate({
        contract: 'AaveCreditTemplate',
        ctx,
        args: [
            roles.ownerWallet,
            getAddress('AgreementStoreManager'),
            getAddress('NFT721LockCondition'),
            getAddress('AaveCollateralDepositCondition'),
            getAddress('AaveBorrowCondition'),
            getAddress('AaveRepayCondition'),
            getAddress('AaveCollateralWithdrawCondition'),
            getAddress('DistributeNFTCollateralCondition'),
            getAddress('AaveCreditVault')
        ],
        verbose
    })

    return { cache, addressBook, proxies }
}

module.exports = initializeContracts
