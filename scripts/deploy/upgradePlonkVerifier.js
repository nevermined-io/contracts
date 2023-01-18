const { web3, ethers } = require('hardhat')
const { readArtifact, exportLibraryArtifact } = require('./artifacts')
const { loadWallet } = require('./wallets')

async function deployLibrary(c, verbose) {
    const afact = readArtifact(c)
    const factory = await ethers.getContractFactory(c, { libraries: afact.libraries })
    if (verbose) {
        console.log(`upgrading ${c} from ${afact.address}`)
    }
    const library = await factory.deploy()
    const h1 = library.deployTransaction.hash
    await library.deployed()
    const address = (await web3.eth.getTransactionReceipt(h1)).contractAddress
    await exportLibraryArtifact(c, address)
    return address
}

async function main() {
    const verbose = true

    const { roles } = await loadWallet({})

    const plonkAddress = await deployLibrary('PlonkVerifier', verbose)

    if (verbose) {
        console.log(`setting dispute manager to ${plonkAddress}`)
    }
    {
        const afactCond = readArtifact('AccessProofCondition')
        const AccessProofCondition = await ethers.getContractFactory('AccessProofCondition')
        const cond = AccessProofCondition.attach(afactCond.address)
        // console.log('owner', await cond.owner(), roles.owner, roles)
        const tx = await cond.connect(ethers.provider.getSigner(roles.ownerWallet)).changeDisputeManager(plonkAddress)
        await tx.wait()
    }

    const vaultAddress = await deployLibrary('AaveCreditVault', verbose)
    if (verbose) {
        console.log(`setting aave credit vault to ${vaultAddress}`)
    }
    {
        const afactCond = readArtifact('AaveCreditTemplate')
        const AaveCreditTemplate = await ethers.getContractFactory('AaveCreditTemplate')
        const cond = AaveCreditTemplate.attach(afactCond.address)
        const tx = await cond.connect(ethers.provider.getSigner(roles.ownerWallet)).changeCreditVaultLibrary(vaultAddress)
        await tx.wait()
    }
}

main()
