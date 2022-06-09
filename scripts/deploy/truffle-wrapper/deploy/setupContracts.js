/* eslint-disable no-console */
const ZeroAddress = '0x0000000000000000000000000000000000000000'

const { ethers } = require('hardhat')

async function callContract(instance, f) {
    // console.log('Calling contract ...')
    const contractOwner = await instance.owner()
    // console.log('Contract Owner: ', contractOwner)
    let tx
    try {
        const signer = await ethers.provider.getSigner(contractOwner)
        tx = await f(instance.connect(signer).populateTransaction)
        // console.log('Got tx', tx)
        const res = await signer.sendTransaction(tx)
        await res.wait()
    } catch (err) {
        console.log('Warning: TX fail')
        console.log(err)
        console.log(tx)
    }
}

async function approveTemplate({
    TemplateStoreManagerInstance,
    templateAddress
} = {}) {
    await callContract(TemplateStoreManagerInstance, a => a.approveTemplate(templateAddress, { gasLimit: 100000 }))
}

async function setupTemplate({ verbose, TemplateStoreManagerInstance, templateName, addressBook, roles } = {}) {
    const templateAddress = addressBook[templateName]
    if (templateAddress) {
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
    if (contractOwner === roles.deployer) {
        const tx = await ContractInstance.connect(ethers.provider.getSigner(roles.deployer)).transferOwnership(
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
    verbose = true,
    addresses
} = {}) {
    /*
     * -----------------------------------------------------------------------
     * setup deployed contracts
     * -----------------------------------------------------------------------
     */
    if (!addresses.stage) {
        addresses.stage = 0
    }
    if (addressBook.TemplateStoreManager && addresses.stage < 1) {
        const TemplateStoreManagerInstance = artifacts.TemplateStoreManager

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'AccessTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'AccessProofTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'EscrowComputeExecutionTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFTAccessTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFT721AccessTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFTSalesTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFTSalesWithAccessTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFTAccessProofTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFTAccessSwapTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFT721SalesWithAccessTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFT721AccessProofTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFT721AccessSwapTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'NFT721SalesTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'DIDSalesTemplate',
            addressBook,
            roles
        })

        await setupTemplate({
            verbose,
            TemplateStoreManagerInstance,
            templateName: 'AaveCreditTemplate',
            addressBook,
            roles
        })

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
            if (verbose) {
                console.log(
                    `Delegating create role to ${addressBook.AgreementStoreManager}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.delegateCreateRole(
                addressBook.AgreementStoreManager
            ))
        }

        if (addressBook.NeverminedConfig) {
            if (verbose) {
                console.log(
                    `Setting nevermined config ${addressBook.NeverminedConfig}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.setNvmConfigAddress(
                addressBook.NeverminedConfig
            ))
        }

        if (addressBook.EscrowPaymentCondition) {
            if (verbose) {
                console.log(
                    `Linking escrow to condition store manager ${addressBook.EscrowPaymentCondition}`
                )
            }

            await callContract(ConditionStoreManagerInstance, a => a.grantProxyRole(
                addressBook.EscrowPaymentCondition
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

    if (addressBook.NFTUpgradeable && addressBook.DIDRegistry && addresses.stage < 3) {
        console.log('Set NFT minter : ' + addressBook.NFTUpgradeable)
        await callContract(artifacts.NFTUpgradeable, a => a.addMinter(addressBook.DIDRegistry))
        await callContract(artifacts.NFTUpgradeable, a => a.setProxyApproval(addressBook.DIDRegistry, true))
        addresses.stage = 3
    }

    if (addressBook.LockPaymentCondition && addressBook.AgreementStoreManager && addresses.stage < 4) {
        console.log('Set lock payment condition proxy : ' + addressBook.LockPaymentCondition)
        await callContract(artifacts.LockPaymentCondition, a => a.grantProxyRole(addressBook.AgreementStoreManager))
        addresses.stage = 4
    }

    if (addressBook.AgreementStoreManager && addresses.stage < 5) {
        const agreements = [
            'NFTAccessTemplate',
            'NFTSalesTemplate',
            'NFT721AccessTemplate',
            'NFT721SalesTemplate',
            'AaveCreditTemplate',
            'AccessProofTemplate',
            'AccessTemplate',
            'DIDSalesTemplate',
            'DynamicAccessTemplate',
            'EscrowComputeExecutionTemplate'
        ]
        for (const a of agreements) {
            if (addressBook[a] && addressBook.AgreementStoreManager) {
                console.log('Set agreement manager proxy : ' + addressBook[a])
                await callContract(artifacts.AgreementStoreManager, c => c.grantProxyRole(addressBook[a]))
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
        console.log('Set NFT721 minter : ' + addressBook.NFT721Upgradeable)
        await callContract(artifacts.NFT721Upgradeable, a => a.addMinter(addressBook.DIDRegistry))
        addresses.stage = 8
    }

    if (addressBook.TransferDIDOwnershipCondition && addressBook.DIDRegistry && addresses.stage < 9) {
        console.log('TransferDIDOwnershipCondition : ' + addressBook.TransferDIDOwnershipCondition)
        await callContract(artifacts.DIDRegistry, a => a.setManager(addressBook.TransferDIDOwnershipCondition))
        addresses.stage = 9
    }

    if (addressBook.TransferNFTCondition && addressBook.NFTUpgradeable && addresses.stage < 10) {
        console.log('TransferNFTCondition : ' + addressBook.TransferNFTCondition)
        await callContract(artifacts.NFTUpgradeable, a => a.setProxyApproval(addressBook.TransferNFTCondition, true))
        addresses.stage = 10
    }

    if (addressBook.TransferNFTCondition && addressBook.DIDRegistry && addresses.stage < 11) {
        console.log('DIDRegistry : ' + addressBook.DIDRegistry)
        await callContract(artifacts.NFTUpgradeable, a => a.setProxyApproval(addressBook.DIDRegistry, true))
        await callContract(artifacts.NFTUpgradeable, a => a.addMinter(addressBook.TransferNFTCondition))
        addresses.stage = 11
    }

    if (addressBook.TransferNFT721Condition && addressBook.NFT721Upgradeable && addresses.stage < 12) {
        console.log('TransferNFT721Condition : ' + addressBook.TransferNFT721Condition)
        await callContract(artifacts.NFT721Upgradeable, a => a.setProxyApproval(addressBook.TransferNFT721Condition, true))
        await callContract(artifacts.NFT721Upgradeable, a => a.addMinter(addressBook.TransferNFT721Condition))
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

        if (addressBook.Dispenser) {
            if (verbose) {
                console.log(
                    `adding dispenser as a minter ${addressBook.Dispenser} from ${roles.deployer}`
                )
            }

            const tx = await token.connect(ethers.provider.getSigner(roles.deployer)).grantRole(
                web3.utils.toHex('minter').padEnd(66, '0'),
                addressBook.Dispenser,
                { from: roles.deployer }
            )
            await tx.wait()
        }

        if (verbose) {
            console.log(
                `Renouncing deployer as initial minter from ${roles.deployer}`
            )
        }

        const tx = await token.connect(ethers.provider.getSigner(roles.deployer)).revokeRole(
            web3.utils.toHex('minter').padEnd(66, '0'),
            roles.deployer,
            { from: roles.deployer }
        )
        await tx.wait()

        const tx2 = await token.connect(ethers.provider.getSigner(roles.deployer)).grantRole(
            web3.utils.toHex('minter').padEnd(66, '0'),
            roles.ownerWallet,
            { from: roles.deployer }
        )
        await tx2.wait()

        addresses.stage = 14
    }

    if (addressBook.NeverminedConfig && addresses.stage < 15) {
        const nvmConfig = artifacts.NeverminedConfig
        console.log('NeverminedConfig : ' + addressBook.NeverminedConfig)

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
        console.log('Set TransferNFTCondition proxy : ' + addressBook.TransferNFTCondition)
        console.log('Grant proxy role to AgreementStoreManager: ' + addressBook.AgreementStoreManager)

        await callContract(artifacts.TransferNFTCondition, a => a.grantProxyRole(addressBook.AgreementStoreManager))

        await transferOwnership({
            ContractInstance: artifacts.TransferNFTCondition,
            name: 'TransferNFTCondition',
            roles,
            verbose
        })

        addresses.stage = 16
    }

    if (addressBook.TransferNFT721Condition && addressBook.AgreementStoreManager && addresses.stage < 17) {
        console.log('Set transfer nft721 condition proxy : ' + addressBook.TransferNFT721Condition)
        await callContract(artifacts.TransferNFT721Condition, a => a.grantProxyRole(addressBook.AgreementStoreManager))
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
        await callContract(artifacts.DIDRegistry, a => a.registerRoyaltiesChecker(addressBook.StandardRoyalties))
        addresses.stage = 19
    }
}

module.exports = setupContracts
