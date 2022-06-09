/* eslint-env mocha */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistryLibraryProxy = artifacts.require('DIDRegistryLibraryProxy')
const DIDRegistry = artifacts.require('DIDRegistry')
const NFT = artifacts.require('NFT721Upgradeable')
const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')

contract('Mintable DIDRegistry (ERC-721)', (accounts) => {
    const owner = accounts[1]
    const other = accounts[2]
    const consumer = accounts[3]
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'https://nevermined.io/metadata.json'
    let didRegistry
    let didRegistryLibrary
    let didRegistryLibraryProxy
    let nft

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!didRegistry) {
            didRegistryLibrary = await DIDRegistryLibrary.new()
            await DIDRegistryLibraryProxy.link(didRegistryLibrary)
            didRegistryLibraryProxy = await DIDRegistryLibraryProxy.new()

            await DIDRegistry.link(didRegistryLibrary)

            nft = await NFT.new()
            await nft.initialize()

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, nft.address)
            await nft.addMinter(didRegistry.address)
        }
    }

    describe('Register an Asset with a DID', () => {
        it('A Mintable DID can be found in the regular DIDRegistry', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

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
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await assert.isRejected(nft.ownerOf(did))
        })

        it('Should not mint or burn a NFTs without previous initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                didRegistry.mint721(did, { from: owner }),
                'NFT not initialized'
            )

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                didRegistry.burn721(did, { from: owner }),
                'NFT not initialized'
            )
        })

        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, true, nftMetadataURL, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            await didRegistry.burn721(did, { from: owner })
            await assert.isRejected(nft.ownerOf(did))

            const _nftURI = await nft.tokenURI(did)
            assert.strictEqual(nftMetadataURL, _nftURI)
        })

        it('Should work with an empty NFT Metadata URL', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, true, '', { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            const _nftURI = await nft.tokenURI(did)
            assert.strictEqual('', _nftURI)
        })

        it('The royalties should be initialized and retrieved (ERC-2981)', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, 10, true, nftMetadataURL, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            const { receiver, royaltyAmount } = await nft.royaltyInfo(did, 500)
            assert.strictEqual(owner, receiver)
            assert.strictEqual(50, royaltyAmount.toNumber())
        })

        it('Should Mint automatically if is configured that way', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, 0, true, nftMetadataURL, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should mint if is not capped', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, false, nftMetadataURL, { from: owner })

            await assert.isRejected(nft.ownerOf(did))

            await didRegistry.mint721(did, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should not mint a NFTs over minting cap', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, false, nftMetadataURL, { from: owner })

            await didRegistry.mint721(did, { from: owner })
            let nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            await assert.isRejected(
                didRegistry.mint721(did, { from: owner }),
                'ERC721: token already minted'
            )
            nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should not mint if not DID Owner', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await assert.isRejected(
                // Must not allow to initialize NFTs if not the owner
                didRegistry.enableAndMintDidNft721(did, 0, true, nftMetadataURL, { from: other }),
                'Only owner'
            )

            await didRegistry.enableAndMintDidNft721(did, 0, true, nftMetadataURL, { from: owner })
            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                didRegistry.mint721(did, { from: other }),
                'Only owner'
            )
        })

        it('Should not burn if not NFT Holder', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, 0, false, nftMetadataURL, { from: owner })

            await didRegistry.methods['mint721(bytes32,address)'](
                did,
                other,
                { from: owner }
            )

            await assert.isRejected(
                // Must not allow to burn if not NFT holder
                didRegistry.burn721(did, { from: consumer }),
                'ERC721: burn amount exceeds balance'
            )

            await didRegistry.burn721(did, { from: other })
        })

        it('Checks the royalties are right', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistryLibraryProxy.update(did, checksum, value, { from: owner })
            await didRegistryLibraryProxy.initializeNft721Config(did, 10, { from: owner })

            await didRegistryLibraryProxy.updateDIDOwner(did, other, { from: owner })

            const storedDIDRegister = await didRegistryLibraryProxy.getDIDInfo(did)

            assert.strictEqual(storedDIDRegister.owner, other)
            assert.strictEqual(storedDIDRegister.creator, owner)
            assert.strictEqual(Number(storedDIDRegister.royalties), 10)

            assert.isNotOk( // MUST BE FALSE. Royalties for original creator are too low
                await didRegistryLibraryProxy.areRoyaltiesValid(did, [91, 9], [consumer, owner], constants.address.zero))

            assert.isOk( // MUST BE TRUE. There is not payment
                await didRegistryLibraryProxy.areRoyaltiesValid(did, [], [], constants.address.zero))

            assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
                await didRegistryLibraryProxy.areRoyaltiesValid(did, [90, 10], [other, owner], constants.address.zero))

            assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
                await didRegistryLibraryProxy.areRoyaltiesValid(did, [10, 90], [owner, other], constants.address.zero))

            assert.isNotOk( // MUST BE FALSE. Original creator is not getting royalties
                await didRegistryLibraryProxy.areRoyaltiesValid(did, [100], [other], constants.address.zero))
        })
    })
})
