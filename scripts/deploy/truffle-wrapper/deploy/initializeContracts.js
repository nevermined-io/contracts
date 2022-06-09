/* eslint-disable no-console */
const ZeroAddress = '0x0000000000000000000000000000000000000000'
const { ethers, upgrades, web3 } = require('hardhat')

async function doDeploy(signer, args) {
    if (process.env.NO_PROXY === 'true') {
        const c = await signer.deploy()
        await c.deployed()
        const tx = await c.initialize(...args)
        await tx.wait()
        return c
    } else {
        const c = await upgrades.deployProxy(signer, args, { unsafeAllowLinkedLibraries: true })
        await c.deployed()
        return c
    }
}

async function zosCreate({ contract, args, libraries, verbose, ctx }) {
    const { cache, addresses, roles } = ctx
    if (addresses[contract]) {
        console.log(`Contract ${contract} found from cache`)
        const C = await ethers.getContractFactory(contract, { libraries })
        cache[contract] = C.attach(addresses[contract])
        return addresses[contract]
    } else {
        const C = await ethers.getContractFactory(contract, { libraries })
        const c = await doDeploy(C.connect(ethers.provider.getSigner(roles.deployer)), args)
        cache[contract] = c
        if (verbose) {
            console.log(`${contract}: ${c.address}`)
        }
        addresses[contract] = c.address
        return c.address
    }
}

async function deployLibrary(name, addresses, cache) {
    if (addresses[name]) {
        console.log(`Contract ${name} found from cache`)
        const C = await ethers.getContractFactory(name)
        cache[name] = C.attach(addresses[name])
        return addresses[name]
    } else {
        const factory = await ethers.getContractFactory(name)
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
    roles,
    didRegistryLibrary,
    epochLibrary,
    addresses,
    verbose = true
} = {}) {
    // Deploy all implementations in the specified network.
    // NOTE: Creates another zos.<network_name>.json file, specific to the network used,
    // which keeps track of deployed addresses, etc.

    // Here we run initialize which replace contract constructors
    // Since each contract initialize function could be different we can not use a loop
    // NOTE: A dapp could now use the address of the proxy specified in zos.<network_name>.json
    // instance=MyContract.at(proxyAddress)
    const addressBook = {}
    const cache = {}
    const ctx = { cache, addresses, roles }

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

    if (configMarketplaceFee < 0 || configMarketplaceFee > 10000) {
        console.error('NVM_MARKETPLACE_FEE can not be lower than 0 or higher than 10000 (100%)\nPlease refer to the ReleaseProcess.md documentation')
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

    if (contracts.indexOf('NeverminedConfig') > -1) {
        addressBook.NeverminedConfig = await zosCreate({
            contract: 'NeverminedConfig',
            ctx,
            args: [roles.deployer, roles.deployer],
            verbose
        })
    }

    if (contracts.indexOf('NFTUpgradeable') > -1) {
        addressBook.NFTUpgradeable = await zosCreate({
            contract: 'NFTUpgradeable',
            ctx,
            args: [''],
            verbose
        })
    }

    if (contracts.indexOf('NFT721Upgradeable') > -1) {
        addressBook.NFT721Upgradeable = await zosCreate({
            contract: 'NFT721Upgradeable',
            ctx,
            args: [],
            verbose
        })
    }

    if (contracts.indexOf('DIDRegistry') > -1) {
        addressBook.DIDRegistry = await zosCreate({
            contract: 'DIDRegistry',
            ctx,
            args: [roles.deployer, addressBook.NFTUpgradeable || ZeroAddress, addressBook.NFT721Upgradeable || ZeroAddress],
            libraries: { DIDRegistryLibrary: didRegistryLibrary },
            verbose
        })
    }

    if (contracts.indexOf('StandardRoyalties') > -1 && contracts.indexOf('DIDRegistry') > -1) {
        addressBook.StandardRoyalties = await zosCreate({
            contract: 'StandardRoyalties',
            ctx,
            args: [addressBook.DIDRegistry],
            verbose
        })
    }

    // testnet only!
    if (contracts.indexOf('NeverminedToken') > -1) {
        addressBook.NeverminedToken = await zosCreate({
            contract: 'NeverminedToken',
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

    if (contracts.indexOf('ConditionStoreManager') > -1 && contracts.indexOf('NeverminedConfig') > -1) {
        addressBook.ConditionStoreManager = await zosCreate({
            contract: 'ConditionStoreManager',
            ctx,
            libraries: { EpochLibrary: epochLibrary },
            args: [roles.deployer, roles.deployer, getAddress('NeverminedConfig')],
            verbose
        })
    }

    if (contracts.indexOf('PlonkVerifier') > -1) {
        proxies.PlonkVerifier = await deployLibrary('PlonkVerifier', addresses, cache)
    }

    if (contracts.indexOf('AaveCreditVault') > -1) {
        proxies.AaveCreditVault = await deployLibrary('AaveCreditVault', addresses, cache)
    }

    if (contracts.indexOf('TemplateStoreManager') > -1) {
        addressBook.TemplateStoreManager = await zosCreate({
            contract: 'TemplateStoreManager',
            ctx,
            args: [roles.deployer],
            verbose
        })
    }

    if (getAddress('ConditionStoreManager')) {
        if (contracts.indexOf('EscrowPaymentCondition') > -1) {
            addressBook.EscrowPaymentCondition = await zosCreate({
                contract: 'EscrowPaymentCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }

        if (contracts.indexOf('SignCondition') > -1) {
            addressBook.SignCondition = await zosCreate({
                contract: 'SignCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }

        if (contracts.indexOf('HashLockCondition') > -1) {
            addressBook.HashLockCondition = await zosCreate({
                contract: 'HashLockCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }

        if (contracts.indexOf('ThresholdCondition') > -1) {
            addressBook.ThresholdCondition = await zosCreate({
                contract: 'ThresholdCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }

        if (contracts.indexOf('WhitelistingCondition') > -1) {
            addressBook.WhitelistingCondition = await zosCreate({
                contract: 'WhitelistingCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('NFT721HolderCondition') > -1) {
            addressBook.NFT721HolderCondition = await zosCreate({
                contract: 'NFT721HolderCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('NFT721LockCondition') > -1) {
            addressBook.NFT721LockCondition = await zosCreate({
                contract: 'NFT721LockCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('NFT721EscrowPaymentCondition') > -1) {
            addressBook.NFT721EscrowPaymentCondition = await zosCreate({
                contract: 'NFT721EscrowPaymentCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('NFTEscrowPaymentCondition') > -1) {
            addressBook.NFTEscrowPaymentCondition = await zosCreate({
                contract: 'NFTEscrowPaymentCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('AaveBorrowCondition') > -1) {
            addressBook.AaveBorrowCondition = await zosCreate({
                contract: 'AaveBorrowCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('AaveCollateralDepositCondition') > -1) {
            addressBook.AaveCollateralDepositCondition = await zosCreate({
                contract: 'AaveCollateralDepositCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('AaveCollateralWithdrawCondition') > -1) {
            addressBook.AaveCollateralWithdrawCondition = await zosCreate({
                contract: 'AaveCollateralWithdrawCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
        if (contracts.indexOf('AaveRepayCondition') > -1) {
            addressBook.AaveRepayCondition = await zosCreate({
                contract: 'AaveRepayCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager')
                ],
                verbose
            })
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('TemplateStoreManager') &&
        getAddress('DIDRegistry')) {
        if (contracts.indexOf('AgreementStoreManager') > -1) {
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
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('EscrowPaymentCondition') &&
        getAddress('DIDRegistry')) {
        if (contracts.indexOf('RewardsDistributor') > -1) {
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
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('DIDRegistry')) {
        if (contracts.indexOf('LockPaymentCondition') > -1) {
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
        }
        if (contracts.indexOf('TransferDIDOwnershipCondition') > -1) {
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
        }
        if (contracts.indexOf('NFTAccessCondition') > -1) {
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
        }
        if (getAddress('PlonkVerifier') && contracts.indexOf('AccessProofCondition') > -1) {
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
        }
    }
    if (getAddress('ConditionStoreManager') &&
        getAddress('NFTUpgradeable')) {
        if (contracts.indexOf('NFTHolderCondition') > -1) {
            addressBook.NFTHolderCondition = await zosCreate({
                contract: 'NFTHolderCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager'),
                    getAddress('NFTUpgradeable')
                ],
                verbose
            })
        }

        if (contracts.indexOf('NFTLockCondition') > -1) {
            addressBook.NFTLockCondition = await zosCreate({
                contract: 'NFTLockCondition',
                ctx,
                args: [
                    roles.ownerWallet,
                    getAddress('ConditionStoreManager'),
                    getAddress('NFTUpgradeable')
                ],
                verbose
            })
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('DIDRegistry') &&
        getAddress('NFTUpgradeable')) {
        if (contracts.indexOf('TransferNFTCondition') > -1) {
            addressBook.TransferNFTCondition = await zosCreate({
                contract: 'TransferNFTCondition',
                ctx,
                args: [
                    roles.deployer,
                    getAddress('ConditionStoreManager'),
                    getAddress('DIDRegistry'),
                    getAddress('NFTUpgradeable'),
                    ZeroAddress
                ],
                verbose
            })
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('AgreementStoreManager')) {
        if (contracts.indexOf('AccessCondition') > -1) {
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
        }
        if (contracts.indexOf('ComputeExecutionCondition') > -1) {
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
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('DIDRegistry') &&
        getAddress('NFT721Upgradeable') &&
        getAddress('LockPaymentCondition')) {
        if (contracts.indexOf('TransferNFT721Condition') > -1) {
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
        }
    }

    if (getAddress('ConditionStoreManager') &&
        getAddress('NFT721LockCondition')) {
        if (contracts.indexOf('DistributeNFTCollateralCondition') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('DIDRegistry') &&
        getAddress('AccessCondition') &&
        getAddress('LockPaymentCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('AccessTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('DIDRegistry') &&
        getAddress('AccessProofCondition') &&
        getAddress('LockPaymentCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('AccessProofTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('NFTHolderCondition')) {
        if (contracts.indexOf('NFTAccessProofTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('NFTLockCondition') &&
        getAddress('NFTEscrowPaymentCondition')) {
        if (contracts.indexOf('NFTAccessSwapTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('LockPaymentCondition') &&
        getAddress('TransferNFTCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('NFTSalesWithAccessTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('NFT721HolderCondition')) {
        if (contracts.indexOf('NFT721AccessProofTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('NFT721LockCondition') &&
        getAddress('NFT721EscrowPaymentCondition')) {
        if (contracts.indexOf('NFT721AccessSwapTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('AccessProofCondition') &&
        getAddress('LockPaymentCondition') &&
        getAddress('TransferNFT721Condition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('NFT721SalesWithAccessTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('DIDRegistry') &&
        getAddress('ComputeExecutionCondition') &&
        getAddress('LockPaymentCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('EscrowComputeExecutionTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('NFTAccessCondition') &&
        getAddress('NFTHolderCondition')) {
        if (contracts.indexOf('NFTAccessTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('NFTAccessCondition') &&
        getAddress('NFT721HolderCondition')) {
        if (contracts.indexOf('NFT721AccessTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('LockPaymentCondition') &&
        getAddress('TransferNFTCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('NFTSalesTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('LockPaymentCondition') &&
        getAddress('TransferNFT721Condition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('NFT721SalesTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('LockPaymentCondition') &&
        getAddress('TransferDIDOwnershipCondition') &&
        getAddress('EscrowPaymentCondition')) {
        if (contracts.indexOf('DIDSalesTemplate') > -1) {
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
        }
    }

    if (getAddress('AgreementStoreManager') &&
        getAddress('NFT721LockCondition') &&
        getAddress('AaveCollateralDepositCondition') &&
        getAddress('AaveBorrowCondition') &&
        getAddress('AaveRepayCondition') &&
        getAddress('AaveCollateralWithdrawCondition') &&
        getAddress('DistributeNFTCollateralCondition')) {
        if (contracts.indexOf('AaveCreditTemplate') > -1) {
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
        }
    }

    return { cache, addressBook, proxies }
}

module.exports = initializeContracts
