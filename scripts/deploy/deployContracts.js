const initializeContracts = require('./initializeContracts.js')
const setupContracts = require('./setupContracts.js')
const evaluateContracts = require('./evaluateContracts.js')
const { ethers, web3 } = require('hardhat')
const { exportArtifacts, exportLibraryArtifacts } = require('./artifacts')
const { loadWallet } = require('./wallets.js')
const { readArtifact, deployLibrary } = require('./artifacts')
const { GsnTestEnvironment } = require('@opengsn/dev')
const fs = require('fs')

const PROXY_ADMIN_ABI = `[{
    "inputs": [],
    "name": "owner",
    "outputs": [
      {
        "internalType": "address",
        "name": "",
        "type": "address"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  }, {
    "inputs": [
      {
        "internalType": "address",
        "name": "newOwner",
        "type": "address"
      }
    ],
    "name": "transferOwnership",
    "outputs": [],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
}]`

async function deployContracts({ contracts: origContracts, verbose, testnet, makeWallet, addresses, deeperClean }) {
    const { core, contracts } = evaluateContracts({
        contracts: origContracts,
        verbose,
        testnet
    })

    if (!deeperClean) {
        for (const el of core.concat(['DIDRegistryLibrary', 'EpochLibrary'])) {
            const afact = readArtifact(el)
            if (afact.address) {
                console.log(`Using existing artifact for ${el}`)
                addresses[el] = afact.address
            }
        }
    }

    const { roles } = await loadWallet({ makeWallet })

    console.log('addresses', addresses)

    const didRegistryLibraryAddress = await deployLibrary('DIDRegistryLibrary', addresses, roles.deployerSigner)
    console.log('Registry library', didRegistryLibraryAddress)

    const epochLibraryAddress = await deployLibrary('EpochLibrary', addresses, roles.deployerSigner)
    console.log('Epoch library', epochLibraryAddress)

    let gsn
    // Add OpenGSN contracts
    if (testnet) {
        try {
            const env = await GsnTestEnvironment.startGsn('localhost')
            const { forwarderAddress } = env.contractsDeployment
            gsn = forwarderAddress
            fs.writeFileSync('artifacts/opengsn.json', JSON.stringify(env.contractsDeployment))
        } catch (e) {
            console.log('Cannot deploy OpenGSN contracts', e)
        }
    }

    const { cache, addressBook, proxies } = await initializeContracts({
        contracts,
        core,
        roles,
        network: '',
        didRegistryLibrary: didRegistryLibraryAddress,
        epochLibrary: epochLibraryAddress,
        verbose,
        addresses
    })

    await setupContracts({
        web3,
        addressBook,
        artifacts: cache,
        roles,
        verbose,
        addresses,
        gsn,
        testnet
    })

    // Move proxy admin to upgrader wallet
    try {
        const someContract = Object.values(addressBook)[0]
        const addr = await ethers.provider.getStorageAt(someContract, '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103')
        console.log('Proxy admin address', addr)
        const admin = new ethers.Contract('0x' + addr.substring(26), PROXY_ADMIN_ABI, ethers.provider)
        const adminOwner = await admin.owner()
        console.log('Proxy admin owner', adminOwner)
        const signer = ethers.provider.getSigner(adminOwner)
        await admin.connect(signer).transferOwnership(roles.upgraderWallet)
    } catch (err) {
        console.log('Cannot move proxy admin ownership', err)
    }

    addressBook.DIDRegistryLibrary = didRegistryLibraryAddress
    addressBook.EpochLibrary = epochLibraryAddress
    if (cache.PlonkVerifier) {
        addressBook.PlonkVerifier = proxies.PlonkVerifier
    }
    if (cache.AaveCreditVault) {
        addressBook.AaveCreditVault = proxies.AaveCreditVault
    }
    const libraries = {
        DIDRegistry: { DIDRegistryLibrary: didRegistryLibraryAddress },
        ConditionStoreManager: { EpochLibrary: epochLibraryAddress }
    }

    if (process.env.NO_PROXY === 'true') {
        await exportLibraryArtifacts(contracts, addressBook)
    } else {
        await exportLibraryArtifacts(contracts, addressBook, libraries)
        await exportArtifacts(core, addressBook, libraries)
        await exportLibraryArtifacts(['EpochLibrary', 'DIDRegistryLibrary'], addressBook)
    }

    return addressBook
}

module.exports = {
    deployContracts
}
