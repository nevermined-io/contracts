/* global artifacts */
const EpochLibrary = artifacts.require('EpochLibrary')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')

const constants = require('./constants.js')
const testUtils = require('./utils')

const deployManagers = async function(deployer, owner, governor = owner, subscription = false) {
    const didRegistryLibrary = await DIDRegistryLibrary.new()
    const epochLibrary = await EpochLibrary.new({ from: deployer })

    const token = await testUtils.deploy('NeverminedToken', [owner, owner], deployer)
    const nvmConfig = await testUtils.deploy('NeverminedConfig', [owner, governor, false], deployer)
    const nft = await testUtils.deploy('NFTUpgradeable', [''], deployer)
    let nft721
    if (subscription) {
        nft721 = await testUtils.deploy('NFT721SubscriptionUpgradeable', ['NFT721', 'NVM', ''], deployer, [], 'initializeWithName')
    } else {
        nft721 = await testUtils.deploy('NFT721Upgradeable', ['NFT721', 'NVM', ''], deployer, [], 'initializeWithName')
    }

    const didRegistry = await testUtils.deploy('DIDRegistry', [owner, nft.address, nft721.address, nvmConfig.address, constants.address.zero], deployer, [didRegistryLibrary])
    const royaltyManager = await testUtils.deploy('StandardRoyalties', [didRegistry.address], deployer)

    const templateStoreManager = await testUtils.deploy('TemplateStoreManager', [owner], deployer)

    const conditionStoreManager = await testUtils.deploy(
        'ConditionStoreManager',
        [deployer, owner, nvmConfig.address],
        deployer,
        [epochLibrary]
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
        await nft.addMinter(didRegistry.address, { from: deployer })
        await nft.setProxyApproval(didRegistry.address, true, { from: deployer })
        await nft721.addMinter(didRegistry.address, { from: deployer })
        await nft721.setProxyApproval(didRegistry.address, true, { from: deployer })
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
