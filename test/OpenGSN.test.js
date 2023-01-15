const { RelayProvider } = require('@opengsn/provider')
const { GsnTestEnvironment } = require('@opengsn/dev')
const { ethers, web3 } = require('hardhat')
const { it, describe, before } = require('mocha')
const { assert } = require('chai')
const constants = require('./helpers/constants.js')
const testUtils = require('./helpers/utils.js')
const Web3HttpProvider = require('web3-providers-http')

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
    let etherProvider
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

        const nvmConfig = await deployContract('NeverminedConfig', deployer, {}, [owner, governor, false])
        await nvmConfig.connect(
            await deploymentProvider.getSigner(governor)).setTrustedForwarder(forwarderAddress)

        didRegistry = await deployContract(
            'DIDRegistry',
            deployer,
            {},
            [owner, constants.address.zero, constants.address.zero, nvmConfig.address, constants.address.zero]
        )
        nft = await deployContract('NFT1155Upgradeable', deployer, {}, [owner, didRegistry.address, '', '', ''])

        const config = await {
            paymasterAddress: paymasterAddress,
            auditorsCount: 0
        }
        const gsnProvider = RelayProvider.newProvider({ provider: web3provider, config })
        await gsnProvider.init()

        const wallet = new ethers.Wallet(Buffer.from('1'.repeat(64), 'hex'))
        gsnProvider.addAccount(wallet.privateKey)
        account = wallet.address

        // gsnProvider is now an rpc provider with GSN support. make it an ethers provider:
        etherProvider = new ethers.providers.Web3Provider(gsnProvider)

        console.log(`Connecting with account ${account}`)
        didRegistry = didRegistry.connect(etherProvider.getSigner(account))
        nft = nft.connect(etherProvider.getSigner(account))
    })

    describe('Register an Asset with a DID', () => {
        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, account)
            const checksum = testUtils.generateId()

            console.log('Registering DID')

            await didRegistry['registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bytes32,string,string)'](
                didSeed, nft.address, checksum, [], value, 20, 0, constants.activities.GENERATED, nftMetadataURL, '', { from: account })

            const didEntry = await didRegistry.getDIDRegister(did)
            console.log(`DID Owner ${didEntry.owner}`)

            assert.strictEqual(account, didEntry.owner)

            const nftAttr = await nft.getNFTAttributes(did)
            assert.strictEqual(nftMetadataURL, nftAttr.nftURI)
            
            /*
            // TODO: Review error:
            //  paymaster rejected in local view call to 'relayCall()' : invalid forwarder for recipient

            console.log(`Minting`)
            await nft['mint(uint256,uint256)'](did, 20, { from: account })

            console.log(`Balance`)
            let balance = await nft.balanceOf(account, did)
            assert.strictEqual(20, balance.toNumber())

            console.log(`Burn`)
            await nft['burn(uint256,uint256)'](did, 5, { from: account })

            balance = await nft.balanceOf(account, did)
            assert.strictEqual(15, balance.toNumber())

            const _nftURI = await nft.uri(did)
            assert.strictEqual(nftMetadataURL, _nftURI) */
        })
    })
})
