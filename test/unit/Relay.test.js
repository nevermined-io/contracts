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

describe('using ethers with OpenGSN forwarder', () => {
    let didRegistry, nft
    let accounts
    let etherProvider
    // let web3provider
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'https://nevermined.io/metadata.json'
    let account
    let forwarder
    before(async () => {
        const deployer = await ethers.provider.getSigner(8)
        const deploymentProvider = ethers.provider
        const Forwarder = await ethers.getContractFactory("Forwarder")
        const signer = Forwarder.connect(deployer)
        forwarder = await signer.deploy()
        await forwarder.deployed()

        await forwarder.registerDomainSeparator("Nevermined", "1")


        accounts = await web3.eth.getAccounts()
        const owner = accounts[0]
        const governor = accounts[1]

        const nvmConfig = await deployContract('NeverminedConfig', deployer, {}, [owner, governor, false])
        await nvmConfig.connect(
            await deploymentProvider.getSigner(governor)).setTrustedForwarder(forwarder.address)

        didRegistry = await deployContract(
            'DIDRegistry',
            deployer,
            {},
            [owner, constants.address.zero, constants.address.zero, nvmConfig.address, constants.address.zero]
        )
        nft = await deployContract('NFT1155Upgradeable', deployer, {}, [owner, didRegistry.address, '', '', ''])
        nft.connect(await deploymentProvider.getSigner(owner)).setNvmConfigAddress(nvmConfig.address)

    })

    describe('Register an Asset with a DID', () => {
        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            console.log('Make DID')
            account = accounts[4]
            const signer = await ethers.provider.getSigner(4)
            const did = await didRegistry.hashDID(didSeed, account)
            const checksum = testUtils.generateId()

            console.log('Registering DID')

            /*
            await didRegistry['registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bytes32,string,string)'](
                didSeed, nft.address, checksum, [], value, 20, 0, constants.activities.GENERATED, nftMetadataURL, '', { from: account, gasLimit: 5000000 })
            */
            const req = {
                from: account,
                to: didRegistry.address,
                value: "0",
                nonce: 0,
                validUntil: 0,
                gas: 5000000,
                data: didRegistry.interface.encodeFunctionData('registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bytes32,string,string)', [
                    didSeed, nft.address, checksum, [], value, 20, 0, constants.activities.GENERATED, nftMetadataURL, ''
                ])
            }
            console.log('Req made', req)

            let data = await forwarder._getEncoded(req, "0x2510fc5e187085770200b027d9f2cc4b930768f3b2bd81daafb71ffeb53d21c4", [])
            console.log('Data', data)

            let domain = {
                name: "Nevermined",
                version: "1",
                chainId: await web3.eth.getChainId(),
                verifyingContract: forwarder.address,
            }
            console.log('Domain', domain)

            const types = {
                ForwardRequest: [
                    { name: "from", type: "address" },
                    { name: "to", type: "address" },
                    { name: "value", type: "uint256" },
                    { name: "gas", type: "uint256" },
                    { name: "nonce", type: "uint256" },
                    { name: "data", type: "bytes" },
                    { name: "validUntil", type: "uint256" },
                ],
            }

            // let sig = await web3.eth.sign(data, account)
            let sig = await signer._signTypedData(domain, types, req)
            console.log('Signature', sig)

            await forwarder.execute(
                req,
                "0xc3f2eba0fc9b898fe103e579c225132f6b31c351c0e50ddc84c09ee64e8c5f73",
                "0x2510fc5e187085770200b027d9f2cc4b930768f3b2bd81daafb71ffeb53d21c4",
                [],
                sig
            )

            const didEntry = await didRegistry.getDIDRegister(did)
            assert.strictEqual(account, didEntry.owner)

            const nftAttr = await nft.getNFTAttributes(did)
            assert.strictEqual(nftMetadataURL, nftAttr.nftURI)

            /*
            console.log('Minting')
            await nft['mint(uint256,uint256)'](did, 20, { from: account, gasLimit: 1000000 })

            console.log('Balance')
            let balance = await nft.balanceOf(account, did)
            assert.strictEqual(20, balance.toNumber())

            console.log('Burn')
            await nft['burn(uint256,uint256)'](did, 5, { from: account, gasLimit: 1000000 })

            balance = await nft.balanceOf(account, did)
            assert.strictEqual(15, balance.toNumber())

            const _nftURI = await nft.uri(did)
            assert.strictEqual(nftMetadataURL, _nftURI)
            */
        })
    })
})
