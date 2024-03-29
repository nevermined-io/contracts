const { ethers } = require('hardhat')
const { resolveAddress } = require('./artifacts')

/* eslint-disable no-console */
const ZeroAddress = '0x0000000000000000000000000000000000000000'

async function callContract(instance, f) {
    const contractOwner = await instance.owner()
    let tx
    try {
        if (contractOwner !== instance.signer.address) {
            const signer = await ethers.provider.getSigner(contractOwner)
            instance.connect(signer)
        }
        tx = await f(instance.populateTransaction)
        const res = await instance.signer.sendTransaction(tx)
        await res.wait()
    } catch (err) {
        console.log('Warning: TX fail')
        console.log(err)
        console.log(tx)
        if (process.env.DEPLOY_EXIT_ERROR === 'true') {
            throw new Error('Error in contract call, exiting')
        }
    }
}

async function approveTemplate({
    TemplateStoreManagerInstance,
    templateAddress
} = {}) {
    console.log(`  approveTemplate :: ${templateAddress}`)
    await callContract(TemplateStoreManagerInstance, a => a.approveTemplate(templateAddress))
}

async function setupTemplate({ verbose, TemplateStoreManagerInstance, templateName, addressBook, roles } = {}) {
    const templateAddress = resolveAddress(templateName, addressBook)

    console.log(`  setupTemplate :: ${templateName} :: ${templateAddress}`)
    if (templateAddress) {
        const approved = await TemplateStoreManagerInstance.isTemplateApproved(templateAddress)

        if (approved) {
            console.log(`Already approved ${templateName} at ${templateAddress}`)
            return
        }

        if (verbose) {
            console.log(
                `Proposing template ${templateName}: ${templateAddress} from ${roles.deployer}`
            )
        }

        try {
            const tx = await TemplateStoreManagerInstance.proposeTemplate(
                templateAddress
            )
            await tx.wait()
        } catch (err) {
            console.log(`Warning: template ${templateName} already proposed`)
            console.log(err)
        }

        if (verbose) {
            console.log(
                `Approving template ${templateName}: ${templateAddress} from ${roles.deployer}`
            )
        }

        await approveTemplate({
            TemplateStoreManagerInstance,
            roles,
            templateAddress
        })
    }
}

async function transferOwnership({
    ContractInstance,
    name,
    roles,
    verbose
} = {}) {
    if (verbose) {
        console.log(
            `Transferring ownership of ${name} from ${roles.deployer} to ${roles.ownerWallet}`
        )
    }

    console.log('Getting Contract Owner from contract: ', name)
    let contractOwner = ZeroAddress
    try {
        contractOwner = await ContractInstance.owner()
    } catch {
        console.log('Error getting contract owner from contract')
    }
    console.log(contractOwner, roles.deployer)
    if (contractOwner === roles.owner) {
        console.log(`The owner wallet {roles.owner} is already owner of the contract ${name}`)
    } else if (contractOwner === roles.deployer) {
        console.log(`Transferring ownership of ${name} from ${roles.deployer} to ${roles.ownerWallet}`)
        const tx = await ContractInstance.connect(roles.deployerSigner).transferOwnership(
            roles.ownerWallet,
            { from: roles.deployer }
        )
        await tx.wait()
    } else {
        console.log('=====================================================================================')
        console.log('WARNING: Ownership was not transferred!')
        console.log(`The deployer is not anymore the owner of the ${name} `)
        console.log('=====================================================================================')
    }
}

async function setupContracts({
    web3,
    artifacts,
    addressBook,
    roles,
    testnet,
    gsn,
    verbose = true,
    addresses
} = {}) {
    /*
     * -----------------------------------------------------------------------
     * setup deployed contracts
     * -----------------------------------------------------------------------
     */
    console.log('\n\n -- Setting up contracts -- \n\n')
    console.log(`Stage: ${addresses.stage}`)
    if (!addresses.stage) {
        addresses.stage = 0
    }
    if (addressBook.TemplateStoreManager) { // && addresses.stage < 1) { // Temporary change to validate templates in all the iterations
        const TemplateStoreManagerInstance = artifacts.TemplateStoreManager

        const templates = Object.keys(addressBook).filter(a => a.match(/Template$/))
        console.log(`Templates Found: ${JSON.stringify(templates)}`)
        for (const templateName of templates) {
            console.log(`Setting up template: ${templateName}`)
            await setupTemplate({
                verbose,
                TemplateStoreManagerInstance,
                templateName,
                addressBook,
                roles
            })
        }

        await transferOwnership({
            ContractInstance: TemplateStoreManagerInstance,
            name: 'TemplateStoreManager',
            roles,
            verbose
        })
        addresses.stage = 1
    }

    if (addressBook.ConditionStoreManager && addresses.stage < 2) {
        const ConditionStoreManagerInstance = artifacts.ConditionStoreManager

        if (addressBook.AgreementStoreManager) {
            const _address = resolveAddress('AgreementStoreManager', addressBook)
            if (verbose) {
                console.log(
                    `Delegating create role to ${_address}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.delegateCreateRole(
                _address
            ))
        }

        if (addressBook.NeverminedConfig) {
            const _address = resolveAddress('NeverminedConfig', addressBook)
            if (verbose) {
                console.log(
                    `Setting nevermined config ${_address}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.setNvmConfigAddress(
                _address
            ))
        }

        if (addressBook.EscrowPaymentCondition) {
            const _address = resolveAddress('EscrowPaymentCondition', addressBook)
            if (verbose) {
                console.log(
                    `Linking escrow to condition store manager ${_address}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.grantProxyRole(
                _address
            ))
        }

        await transferOwnership({
            ContractInstance: ConditionStoreManagerInstance,
            name: 'ConditionStoreManager',
            roles,
            verbose
        })
        addresses.stage = 2
    }

    if (addressBook.NFT1155Upgradeable && addressBook.DIDRegistry && addresses.stage < 3) {
        console.log('Set NFT Operators : ' + resolveAddress('NFT1155Upgradeable', addressBook))
        console.log('No operators needed, DIDRegistry is setup during the initialization')
        // Leaving this block here to setup operators when necessary
        //        await callContract(artifacts.NFT1155Upgradeable, a => a.grantOperatorRole(addressBook.DIDRegistry))
        addresses.stage = 3
    }

    if (addressBook.LockPaymentCondition && addressBook.AgreementStoreManager && addresses.stage < 4) {
        console.log('Set lock payment condition proxy : ' + resolveAddress('LockPaymentCondition', addressBook))
        await callContract(artifacts.LockPaymentCondition, a => a.grantProxyRole(resolveAddress('AgreementStoreManager', addressBook)))
        addresses.stage = 4
    }

    if (addressBook.AgreementStoreManager && addresses.stage < 5) {
        const agreements = Object.keys(addressBook).filter(a => a.match(/Template$/))
        for (const a of agreements) {
            if (addressBook[a] && addressBook.AgreementStoreManager) {
                const _address = resolveAddress(a, addressBook)
                console.log('Set agreement manager proxy : ' + _address)
                await callContract(artifacts.AgreementStoreManager, c => c.grantProxyRole(_address))
            }
        }
        addresses.stage = 5
    }

    if (addressBook.LockPaymentCondition && addresses.stage < 6) {
        await callContract(artifacts.LockPaymentCondition, a => a.reinitialize())
        await transferOwnership({
            ContractInstance: artifacts.LockPaymentCondition,
            name: 'LockPaymentCondition',
            roles,
            verbose
        })
        addresses.stage = 6
    }

    if (addressBook.AgreementStoreManager && addresses.stage < 7) {
        await transferOwnership({
            ContractInstance: artifacts.AgreementStoreManager,
            name: 'AgreementStoreManager',
            roles,
            verbose
        })
        addresses.stage = 7
    }

    if (addressBook.NFT721Upgradeable && addressBook.DIDRegistry && addresses.stage < 8) {
        console.log('Set NFT721 operators : ' + addressBook.NFT721Upgradeable)
        console.log('No operators needed, DIDRegistry is setup during the initialization')
        // Leaving this block here to setup operators when necessary
        //        await callContract(artifacts.NFT721Upgradeable, a => a.grantOperatorRole(addressBook.DIDRegistry))
        addresses.stage = 8
    }

    if (addressBook.TransferDIDOwnershipCondition && addressBook.DIDRegistry && addresses.stage < 9) {
        console.log('TransferDIDOwnershipCondition : ' + addressBook.TransferDIDOwnershipCondition)
        // await callContract(artifacts.DIDRegistry, a => a.grantRegistryOperatorRole(addressBook.TransferDIDOwnershipCondition))
        addresses.stage = 9
    }

    if (addressBook.TransferNFTCondition && addressBook.NeverminedConfig && addresses.stage < 10) {
        const _address = resolveAddress('TransferNFTCondition', addressBook)
        console.log('TransferNFTCondition : ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 10
    }

    if (addressBook.TransferNFTCondition && addressBook.DIDRegistry && addresses.stage < 11) {
        console.log('DIDRegistry : ' + addressBook.DIDRegistry)
        addresses.stage = 11
    }

    if (addressBook.TransferNFT721Condition && addressBook.NeverminedConfig && addresses.stage < 12) {
        const _address = resolveAddress('TransferNFT721Condition', addressBook)
        console.log('TransferNFT721Condition : ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 12
    }

    if (addressBook.DIDRegistry && addresses.stage < 13) {
        const DIDRegistryInstance = artifacts.DIDRegistry

        await transferOwnership({
            ContractInstance: DIDRegistryInstance,
            name: 'DIDRegistry',
            roles,
            verbose
        })
        addresses.stage = 13
    }

    if (addressBook.NeverminedToken && addresses.stage < 14) {
        const token = artifacts.NeverminedToken
        const _address = resolveAddress('Dispenser', addressBook)

        if (addressBook.Dispenser) {
            if (verbose) {
                console.log(
                    `adding dispenser as a minter ${_address} from ${roles.deployer}`
                )
            }

            const tx = await token.connect(roles.deployerSigner).grantRole(
                web3.utils.toHex('minter').padEnd(66, '0'),
                _address,
                { from: roles.deployer }
            )
            await tx.wait()
        }

        if (verbose) {
            console.log(
                `Renouncing deployer as initial minter from ${roles.deployer}`
            )
        }

        const tx = await token.connect(roles.deployerSigner).revokeRole(
            web3.utils.toHex('minter').padEnd(66, '0'),
            roles.deployer,
            { from: roles.deployer }
        )
        await tx.wait()

        const tx2 = await token.connect(roles.deployerSigner).grantRole(
            web3.utils.toHex('minter').padEnd(66, '0'),
            roles.ownerWallet,
            { from: roles.deployer }
        )
        await tx2.wait()

        addresses.stage = 14
    }

    if (addressBook.NeverminedConfig && addresses.stage < 15) {
        const nvmConfig = artifacts.NeverminedConfig
        const _address = resolveAddress('NeverminedConfig', addressBook)

        console.log('NeverminedConfig : ' + _address)

        const configMarketplaceFee = Number(process.env.NVM_MARKETPLACE_FEE || '0')
        const configFeeReceiver = process.env.NVM_RECEIVER_FEE || ZeroAddress

        await callContract(nvmConfig, a => a.setMarketplaceFees(configMarketplaceFee, configFeeReceiver))
        console.log('[NeverminedConfig] Marketplace Fees set to : ' + configMarketplaceFee)

        await callContract(nvmConfig, a => a.setGovernor(roles.governorWallet))

        const isGovernor = await nvmConfig.isGovernor(roles.governorWallet)
        console.log('Is governorWallet NeverminedConfig governor? ' + isGovernor)

        await transferOwnership({
            ContractInstance: nvmConfig,
            name: 'NeverminedConfig',
            roles,
            verbose
        })

        addresses.stage = 15
    }

    if (addressBook.TransferNFTCondition && addressBook.AgreementStoreManager && addresses.stage < 16) {
        const _address = resolveAddress('AgreementStoreManager', addressBook)

        console.log('Set TransferNFTCondition proxy : ' + addressBook.TransferNFTCondition)
        console.log('Grant proxy role to AgreementStoreManager: ' + _address)

        await callContract(artifacts.TransferNFTCondition, a => a.grantProxyRole(_address))

        await transferOwnership({
            ContractInstance: artifacts.TransferNFTCondition,
            name: 'TransferNFTCondition',
            roles,
            verbose
        })

        addresses.stage = 16
    }

    if (addressBook.TransferNFT721Condition && addressBook.AgreementStoreManager && addresses.stage < 17) {
        const _address = resolveAddress('AgreementStoreManager', addressBook)

        console.log('Set transfer nft721 condition proxy : ' + addressBook.TransferNFT721Condition)
        await callContract(artifacts.TransferNFT721Condition, a => a.grantProxyRole(_address))
        await transferOwnership({
            ContractInstance: artifacts.TransferNFT721Condition,
            name: 'TransferNFT721Condition',
            roles,
            verbose
        })
        addresses.stage = 17
    }

    if (addressBook.AccessCondition && addresses.stage < 18) {
        console.log('Reinit Access condition: ' + addressBook.AccessCondition)
        await callContract(artifacts.AccessCondition, a => a.reinitialize())
        addresses.stage = 18
    }

    if (addressBook.DIDRegistry && addressBook.StandardRoyalties && addresses.stage < 19) {
        console.log('Setup royalty manager: ' + addressBook.StandardRoyalties)
        await callContract(artifacts.DIDRegistry, a => a.registerRoyaltiesChecker(resolveAddress('StandardRoyalties', addressBook)))
        await callContract(artifacts.DIDRegistry, a => a.setDefaultRoyalties(resolveAddress('StandardRoyalties', addressBook)))
        addresses.stage = 19
    }

    if (addressBook.NFTLockCondition && addressBook.NeverminedConfig && addresses.stage < 21) {
        const _address = resolveAddress('NFTLockCondition', addressBook)
        console.log('Grant Proxy Approval (NFTLockCondition): ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 21
    }

    if (addressBook.NeverminedConfig && addressBook.NFT721LockCondition && addresses.stage < 22) {
        const _address = resolveAddress('NFT721LockCondition', addressBook)
        console.log('Grant Proxy Approval (NFT721LockCondition): ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 22
    }

    if (addresses.stage < 23) {
        const chainId = await web3.eth.getChainId()
        console.log(`Setting up OpenGSN forwarder for chain ID ${chainId}`)
        if (!gsn) {
            if (process.env.OPENGSN_FORWARDER) {
                gsn = process.env.OPENGSN_FORWARDER
            } else if (chainId === 80001) {
                gsn = '0x4d4581c01A457925410cd3877d17b2fd4553b2C5' // mumbai
            } else if (chainId === 1) {
                gsn = '0xAa3E82b4c4093b4bA13Cb5714382C99ADBf750cA' // ethereum mainnet
            } else if (chainId === 137) {
                gsn = '0xdA78a11FD57aF7be2eDD804840eA7f4c2A38801d' // polygon
            }
        }
        if (testnet && gsn) {
            await callContract(artifacts.NeverminedConfig, a => a.setTrustedForwarder(gsn))
        } else {
            console.warn('Warning, OPENGSN_FORWARDER environment variable is not set. Meta transactions will not work')
        }
        const _nvmConfigAddress = resolveAddress('NeverminedConfig', addressBook)
        if (addressBook.NFT1155Upgradeable) {
            await callContract(artifacts.NFT1155Upgradeable, a => a.setNvmConfigAddress(_nvmConfigAddress))
        }
        if (addressBook.NFT721Upgradeable) {
            await callContract(artifacts.NFT721Upgradeable, a => a.setNvmConfigAddress(_nvmConfigAddress))
        }
        if (addressBook.NFT1155SubscriptionUpgradeable) {
            await callContract(artifacts.NFT1155SubscriptionUpgradeable, a => a.setNvmConfigAddress(_nvmConfigAddress))
        }
        if (addressBook.NFT721SubscriptionUpgradeable) {
            await callContract(artifacts.NFT721SubscriptionUpgradeable, a => a.setNvmConfigAddress(_nvmConfigAddress))
        }
        if (addressBook.NeverminedToken) {
            await callContract(artifacts.NeverminedToken, a => a.setNvmConfigAddress(_nvmConfigAddress))
        }
        addresses.stage = 23
    }

    if (addresses.stage < 24 && addressBook.NFT1155Upgradeable) {
        const _address = resolveAddress('NFT1155Upgradeable', addressBook)
        console.log('Setting up NFT-1155: ' + _address)
        await callContract(artifacts.DIDRegistry, a => a.setNFT1155(_address))
        addresses.stage = 24
    }
    if (addressBook.NeverminedConfig && addressBook.NFTEscrowPaymentCondition && addresses.stage < 25) {
        const _address = resolveAddress('NFTEscrowPaymentCondition', addressBook)
        console.log('Grant Proxy Approval (NFTEscrowPaymentCondition): ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 25
    }
    if (addressBook.NeverminedConfig && addressBook.NFT721EscrowPaymentCondition && addresses.stage < 26) {
        const _address = resolveAddress('NFT721EscrowPaymentCondition', addressBook)
        console.log('Grant Proxy Approval (NFT721EscrowPaymentCondition): ' + _address)
        await callContract(artifacts.NeverminedConfig, a => a.grantNVMOperatorRole(_address))
        addresses.stage = 26
    }
}

module.exports = setupContracts
