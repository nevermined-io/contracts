/* eslint-env mocha */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const NFT = artifacts.require('NFT1155Upgradeable')
const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')

contract('Mintable DIDRegistry', (accounts) => {
    const deployer = accounts[0]
    const owner = accounts[1]
    const other = accounts[2]
    const consumer = accounts[3]
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'https://nevermined.io/metadata.json'
    let didRegistry
    let nft

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!didRegistry) {
            const StandardRoyalties = artifacts.require('StandardRoyalties')
            const standardRoyalties = await StandardRoyalties.new()

            config = await artifacts.require('NeverminedConfig').new()
            await config.initialize(owner, owner, true)

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, config.address, standardRoyalties.address)
            await standardRoyalties.initialize(didRegistry.address)

            nft = await NFT.new()
            await nft.initialize(owner, didRegistry.address, 'NFT1155', 'NVM', '', { from: deployer })

            await nft.setNvmConfigAddress(config.address, {from: owner})
            await config.setOperator(didRegistry.address, {from: owner})
            await config.setOperator(owner, {from: owner})

        }
    }

    describe('Register an Asset with a DID', () => {
        it('A Mintable DID can be found in the regular DIDRegistry', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 0, 0, constants.activities.GENERATED, '', '', { from: owner })

            const storedDIDRegister = await didRegistry.getDIDRegister(did)

            assert.strictEqual(
                value,
                storedDIDRegister.url
            )
            assert.strictEqual(
                owner,
                storedDIDRegister.owner
            )
        })

        it('Should not mint automatically a NFT associated with the DID', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 0, 0, constants.activities.GENERATED, '', '', { from: owner })

            const balance = await nft.balanceOf(owner, did)
            assert.strictEqual(0, balance.toNumber())
        })

        it('Should not mint or burn a NFTs without previous initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.mint(did, 10, { from: owner })
            )

            await assert.isRejected(
                // Must not allow to burn tokens
                nft.burn(did, 1, { from: owner })
            )
        })

        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 20, 0, constants.activities.GENERATED, nftMetadataURL, '', { from: owner })
            await nft.mint(did, 20, { from: owner })

            let balance = await nft.balanceOf(owner, did)
            assert.strictEqual(20, balance.toNumber())

            await nft.burn(did, 5, { from: owner })

            balance = await nft.balanceOf(owner, did)
            assert.strictEqual(15, balance.toNumber())

            const _nftURI = await nft.uri(did)
            assert.strictEqual(nftMetadataURL, _nftURI)
        })

        it('Should only burn if is NFT holder', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 1, 0, constants.activities.GENERATED, nftMetadataURL, '', { from: owner })

            await nft.methods['mint(address,uint256,uint256,bytes)'](
                other,
                did,
                1,
                '0x',
                { from: owner }
            )

            let balance = await nft.balanceOf(other, did)
            assert.strictEqual(1, balance.toNumber())

            const balanceOwner = await nft.balanceOf(owner, did)
            assert.strictEqual(0, balanceOwner.toNumber())

            await assert.isRejected(
                // Must not allow to burn because owner is not holder
                nft.burn(did, 1, { from: owner }),
                'ERC1155: burn amount exceeds balance'
            )

            await nft.methods['burn(uint256,uint256)'](did, 1, { from: other })

            balance = await nft.balanceOf(other, did)
            assert.strictEqual(0, balance.toNumber())
        })

        it('Should initialize the NFT in the registration', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 10, 0, constants.activities.GENERATED, '', '', { from: owner })
            await nft.mint(did, 10, { from: owner })

            const balance = await nft.balanceOf(owner, did)
            assert.strictEqual(10, balance.toNumber())
        })

        it('The royalties should be initialized and retrieved (ERC-2981)', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 999, 10, constants.activities.GENERATED, '', '', { from: owner })

            const { receiver, royaltyAmount } = await nft.royaltyInfo(did, 500)
            assert.strictEqual(owner, receiver)
            assert.strictEqual(50, royaltyAmount.toNumber())
        })

        it('Should Mint automatically if is configured that way', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed, nft.address, checksum, [], value, 5, 0, true, constants.activities.GENERATED, '', '', { from: owner })

            const balanceOwner = await nft.balanceOf(owner, did)
            assert.strictEqual(5, balanceOwner.toNumber())
        })

        it('Should mint if is not capped', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed, nft.address, checksum, [], value, 0, 0, false, constants.activities.GENERATED, '', '', { from: owner })
            await nft.mint(did, 10, { from: owner })

            const balance = await nft.balanceOf(owner, did)
            assert.strictEqual(10, balance.toNumber())
        })

        it('Should not mint a NFTs over minting cap', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerMintableDID(
                didSeed, nft.address, checksum, [], value, 5, 0, constants.activities.GENERATED, '', '', { from: owner })

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.mint(did, 10, { from: owner }),
                'Cap exceeded'
            )

            await nft.mint(did, 5, { from: owner })
            const balance = await nft.balanceOf(owner, did)
            assert.strictEqual(5, balance.toNumber())

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.mint(did, 1, { from: owner }),
                'Cap exceeded'
            )
            assert.strictEqual(5, balance.toNumber())
        })

        it('Should not mint or burn if not DID Owner', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await assert.isRejected(
                // Must not allow to initialize NFTs if not the owner
                didRegistry.enableAndMintDidNft(did, nft.address, 5, 0, true, nftMetadataURL, { from: other })
            )

            await didRegistry.enableAndMintDidNft(did, nft.address, 5, 0, true, nftMetadataURL, { from: owner })
            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.mint(did, 1, { from: other })
            )
        })

        it('Checks the royalties are right', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft(did, nft.address, 3, 100000, false, '', { from: owner })
            await didRegistry.transferDIDOwnership(did, other, { from: owner })

            assert.isNotOk( // MUST BE FALSE. Royalties for original creator are too low
                await didRegistry.areRoyaltiesValid(did, [91, 9], [consumer, owner], constants.address.zero))

            assert.isOk( // MUST BE TRUE. There is not payment
                await didRegistry.areRoyaltiesValid(did, [], [], constants.address.zero))

            assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
                await didRegistry.areRoyaltiesValid(did, [90, 10], [other, owner], constants.address.zero))

            assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
                await didRegistry.areRoyaltiesValid(did, [10, 90], [owner, other], constants.address.zero))

            assert.isNotOk( // MUST BE FALSE. Original creator is not getting royalties
                await didRegistry.areRoyaltiesValid(did, [100], [other], constants.address.zero))
        })
    })
})
