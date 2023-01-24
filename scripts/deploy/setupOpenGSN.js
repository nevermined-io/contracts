const { ethers } = require('hardhat')
const { readArtifact } = require('./artifacts')
const { loadWallet } = require('./wallets')

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

    const relay = process.env.OPENGSN_FORWARDER
    if (verbose) {
        console.log(`setting opengsn forwarder address to ${relay}`)
    }
    await callContract('NeverminedConfig', roles, a => a.setTrustedForwarder(relay))

    const config = readArtifact('NeverminedConfig')
    if (verbose) {
        console.log('Setting up token contracts')
    }
    await callContract('NFT1155Upgradeable', a => a.setNvmConfigAddress(config))
    await callContract('NFT721Upgradeable', a => a.setNvmConfigAddress(config))
    await callContract('NeverminedToken', a => a.setNvmConfigAddress(config))
}

main()
