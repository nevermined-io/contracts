const { web3, ethers } = require('hardhat')
const { readArtifact, exportLibraryArtifact } = require('./artifacts')
const { loadWallet } = require('./wallets')

const DEPLOY_AAVE = process.env.DEPLOY_AAVE === 'true'


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

async function callContract(name, roles, f) {
    const afact = readArtifact(name)
    const factory = await ethers.getContractFactory(name)
    const c = factory.attach(afact.address)
    // console.log('owner', await cond.owner(), roles.owner, roles)
    const tx = await f(c.connect(ethers.provider.getSigner(roles.ownerWallet)))
    await tx.wait()
}

async function main() {
    const verbose = true

    const { roles } = await loadWallet({})

    const plonkAddress = await deployLibrary('PlonkVerifier', verbose)

    if (verbose) {
        console.log(`setting dispute manager to ${plonkAddress}`)
    }

    if (DEPLOY_AAVE)    {
        await callContract('AccessProofCondition', roles, c => c.changeDisputeManager(plonkAddress))

        const vaultAddress = await deployLibrary('AaveCreditVault', verbose)
        if (verbose) {
            console.log(`setting aave credit vault to ${vaultAddress}`)
        }
        await callContract('AaveCreditTemplate', roles, c => c.changeCreditVaultLibrary(vaultAddress))
    }

}

main()
