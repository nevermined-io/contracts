/* global artifacts */
const EpochLibrary = artifacts.require('EpochLibrary')
const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')
const ConditionStoreManager = artifacts.require('ConditionStoreManager')
const TemplateStoreManager = artifacts.require('TemplateStoreManager')
const AgreementStoreManager = artifacts.require('AgreementStoreManager')
const NeverminedToken = artifacts.require('NeverminedToken')
const NFT = artifacts.require('NFTUpgradeable')

let linked = false

const deployManagers = async function(deployer, owner) {
    if (!linked) {
        const didRegistryLibrary = await DIDRegistryLibrary.new()
        await DIDRegistry.link(didRegistryLibrary)

        const epochLibrary = await EpochLibrary.new({ from: deployer })
        await ConditionStoreManager.link(epochLibrary)
        linked = true
    }

    const token = await NeverminedToken.new({ from: deployer })
    await token.initialize(owner, owner)

    const nft = await NFT.new()
    await nft.initialize('')

    const didRegistry = await DIDRegistry.new()
    await didRegistry.initialize(owner, nft.address)
    await nft.addMinter(didRegistry.address)

    const conditionStoreManager = await ConditionStoreManager.new({ from: deployer })

    const templateStoreManager = await TemplateStoreManager.new({ from: deployer })
    await templateStoreManager.initialize(
        owner,
        { from: deployer }
    )

    const agreementStoreManager = await AgreementStoreManager.new({ from: deployer })
    await agreementStoreManager.methods['initialize(address,address,address,address)'](
        owner,
        conditionStoreManager.address,
        templateStoreManager.address,
        didRegistry.address,
        { from: deployer }
    )

    await conditionStoreManager.initialize(
        agreementStoreManager.address,
        { from: deployer }
    )

    return {
        token,
        didRegistry,
        agreementStoreManager,
        conditionStoreManager,
        templateStoreManager,
        nft,
        deployer,
        owner
    }
}

module.exports = deployManagers
