const initializeContracts = require('./deploy/initializeContracts.js')
const setupContracts = require('./deploy/setupContracts.js')
const evaluateContracts = require('./evaluateContracts.js')
const { ethers, web3 } = require('hardhat')
const { exportArtifacts, exportLibraryArtifacts } = require('./artifacts')
const { loadWallet } = require('./wallets.js')
const { readArtifact } = require('./artifacts')

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

async function deployLibrary(name, addresses) {
    if (addresses[name]) {
        console.log(`Contract ${name} found from cache`)
        return addresses[name]
    } else {
        const factory = await ethers.getContractFactory(name)
        const library = await factory.deploy()
        const h1 = library.deployTransaction.hash
        await library.deployed()
        const address = (await web3.eth.getTransactionReceipt(h1)).contractAddress
        addresses[name] = address
        return address
    }
}

async function deployContracts({ contracts: origContracts, verbose, testnet, makeWallet, addresses, deeperClean }) {
    const contracts = evaluateContracts({
        contracts: origContracts,
        verbose,
        testnet
    })

    if (!deeperClean) {
        for (const el of contracts.concat(['DIDRegistryLibrary', 'EpochLibrary'])) {
            const afact = readArtifact(el)
            if (afact.address) {
                console.log(`Using existing artifact for ${el}`)
                addresses[el] = afact.address
            }
        }
    }

    const { roles } = await loadWallet({ makeWallet })

    console.log('wallet', roles)

    const didRegistryLibraryAddress = await deployLibrary('DIDRegistryLibrary', addresses)
    console.log('Registry library', didRegistryLibraryAddress)

    const epochLibraryAddress = await deployLibrary('EpochLibrary', addresses)
    console.log('Epoch library', epochLibraryAddress)

    const { cache, addressBook, proxies } = await initializeContracts({
        contracts,
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
        addresses
    })

    // Move proxy admin to upgrader wallet
    try {
        const addr = await ethers.provider.getStorageAt(addressBook.DIDRegistry, '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103')
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
        await exportArtifacts(contracts.filter(a => a !== 'AaveCreditVault' && a !== 'PlonkVerifier'), addressBook, libraries)
        await exportLibraryArtifacts(['EpochLibrary', 'DIDRegistryLibrary', 'PlonkVerifier'], addressBook)

        if (contracts.indexOf('AaveCreditVault') > -1) {
            await exportLibraryArtifacts(['AaveCreditVault'], addressBook)
        }
    }

    return addressBook
}

module.exports = {
    deployContracts
}
