/* global artifacts */
const EpochLibrary = artifacts.require('EpochLibrary')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')

const testUtils = require('./utils')

const deployManagers = async function(deployer, owner, governor = owner) {
    const didRegistryLibrary = await DIDRegistryLibrary.new()
    const epochLibrary = await EpochLibrary.new({ from: deployer })

    const token = await testUtils.deploy('NeverminedToken', [owner, owner], deployer)
    const nvmConfig = await testUtils.deploy('NeverminedConfig', [owner, governor], deployer)
    const nft = await testUtils.deploy('NFTUpgradeable', [''], deployer)
    const nft721 = await testUtils.deploy('NFT721Upgradeable', [], deployer)

    const didRegistry = await testUtils.deploy('DIDRegistry', [owner, nft.address, nft721.address], deployer, [didRegistryLibrary])
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
