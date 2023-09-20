const constants = require('./constants.js')
const testUtils = require('./utils')

const deployManagers = async function(deployer, owner, governor = owner, subscription = false) {
    const token = await testUtils.deploy('NeverminedToken', [owner, owner], deployer)
    const nvmConfig = await testUtils.deploy('NeverminedConfig', [owner, governor, false], deployer)
    const didRegistry = await testUtils.deploy('DIDRegistry', [owner, constants.address.zero, constants.address.zero, nvmConfig.address, constants.address.zero], deployer)

    const nft = await testUtils.deploy('NFT1155Upgradeable', [deployer, didRegistry.address, 'NFT1155', 'NVM', 'http'], deployer, [], 'initialize')

    let nft721
    if (subscription) {
        nft721 = await testUtils.deploy('NFT721SubscriptionUpgradeable', [deployer, didRegistry.address, 'NFT721', 'NVM', '', 0], deployer, [], 'initialize')
    } else {
        nft721 = await testUtils.deploy('NFT721Upgradeable', [deployer, didRegistry.address, 'NFT721', 'NVM', '', 0], deployer, [], 'initialize')
    }

    const royaltyManager = await testUtils.deploy('StandardRoyalties', [didRegistry.address], deployer)

    const templateStoreManager = await testUtils.deploy('TemplateStoreManager', [owner], deployer)

    const conditionStoreManager = await testUtils.deploy(
        'ConditionStoreManager',
        [deployer, owner, nvmConfig.address],
        deployer
    )

    const agreementStoreManager = await testUtils.deploy(
        'AgreementStoreManager',
        [owner, conditionStoreManager.address, templateStoreManager.address, didRegistry.address],
        deployer
    )

    await nvmConfig.setMarketplaceFees(
        0,
        owner,
        { from: governor }
    )

    if (testUtils.deploying) {
        await nvmConfig.grantNVMOperatorRole(didRegistry.address, { from: owner })
        await nvmConfig.grantNVMOperatorRole(owner, { from: owner })
        await nvmConfig.grantNVMOperatorRole(deployer, { from: owner })
        await nft.setNvmConfigAddress(nvmConfig.address, { from: deployer })
        await nft721.setNvmConfigAddress(nvmConfig.address, { from: deployer })
        await conditionStoreManager.delegateCreateRole(
            agreementStoreManager.address,
            { from: owner }
        )
        await didRegistry.registerRoyaltiesChecker(royaltyManager.address, { from: owner })
        await didRegistry.setDefaultRoyalties(royaltyManager.address, { from: owner })
    }

    return {
        token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        nft,
        nvmConfig,
        nft721,
        deployer,
        owner,
        royaltyManager
    }
}

module.exports = deployManagers
