const { RelayProvider } = require('@opengsn/provider')
const { GsnTestEnvironment } = require('@opengsn/dev')
const { ethers, web3 } = require('hardhat')
const { it, describe, before } = require('mocha')
const { assert } = require('chai')
const constants = require('./helpers/constants.js')
const testUtils = require('./helpers/utils.js')
const Web3HttpProvider = require('web3-providers-http')

async function deployLibrary(name, signer) {
    const factory = await ethers.getContractFactory(name, signer)
    const library = await factory.deploy()
    const h1 = library.deployTransaction.hash
    await library.deployed()
    const address = (await web3.eth.getTransactionReceipt(h1)).contractAddress
    console.log(`Library ${name} deployed into address ${address}`)
    return address
}

async function deployContract(contract, deployer, libraries, args) {
    const C = await ethers.getContractFactory(contract, { libraries })
    const signer = C.connect(deployer)
    const c = await signer.deploy()
    await c.deployed()
    const tx = await c.initialize(...args)
    await tx.wait()
    return c
}

describe('using ethers with OpenGSN', () => {
    let didRegistry, nft
    let accounts
    // let web3provider
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'https://nevermined.io/metadata.json'
    let account
    before(async () => {
        const env = await GsnTestEnvironment.startGsn('localhost')

        const { paymasterAddress, forwarderAddress } = env.contractsDeployment

        const web3provider = new Web3HttpProvider('http://localhost:8545')

        const deploymentProvider = new ethers.providers.Web3Provider(web3provider)
        const deployer = await deploymentProvider.getSigner(8)

        accounts = await web3.eth.getAccounts()
        const owner = accounts[0]
        const governor = accounts[1]
        // const owner = accounts[0]

        const didlib = await deployLibrary('DIDRegistryLibrary', deployer)

        const nvmConfig = await deployContract('NeverminedConfig', deployer, {}, [owner, governor, false])

        nft = await deployContract('NFTUpgradeable', deployer, {}, [''])

        didRegistry = await deployContract(
            'DIDRegistry',
            deployer,
            { DIDRegistryLibrary: didlib },
            [owner, nft.address, constants.address.zero, nvmConfig.address, constants.address.zero]
        )

        await nft.connect(deployer).addMinter(didRegistry.address)
        await nvmConfig.connect(await deploymentProvider.getSigner(governor)).setTrustedForwarder(forwarderAddress)

        const config = await {
            // loggerConfiguration: { logLevel: 'error'},
            paymasterAddress: paymasterAddress,
            auditorsCount: 0
        }
        // const hdweb3provider = new HDWallet('0x123456', 'http://localhost:8545')
        const gsnProvider = RelayProvider.newProvider({ provider: web3provider, config })
        await gsnProvider.init()
        // The above is the full provider configuration. can use the provider returned by startGsn:
        // const gsnProvider = env.relayProvider

        const wallet = new ethers.Wallet(Buffer.from('1'.repeat(64), 'hex'))
        gsnProvider.addAccount(wallet.privateKey)
        account = wallet.address

        // gsnProvider is now an rpc provider with GSN support. make it an ethers provider:
        const etherProvider = new ethers.providers.Web3Provider(gsnProvider)

        didRegistry = didRegistry.connect(etherProvider.getSigner(account))
    })

    describe('Register an Asset with a DID', () => {
        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, account)
            const checksum = testUtils.generateId()

            await didRegistry['registerMintableDID(bytes32,bytes32,address[],string,uint256,uint256,bytes32,string,string)'](
                didSeed, checksum, [], value, 20, 0, constants.activities.GENERATED, nftMetadataURL, '', { from: account })
            await didRegistry['mint(bytes32,uint256)'](did, 20, { from: account })

            let balance = await nft.balanceOf(account, did)
            assert.strictEqual(20, balance.toNumber())

            await didRegistry.burn(did, 5, { from: account })

            balance = await nft.balanceOf(account, did)
            assert.strictEqual(15, balance.toNumber())

            const _nftURI = await nft.uri(did)
            assert.strictEqual(nftMetadataURL, _nftURI)
        })
    })
})
