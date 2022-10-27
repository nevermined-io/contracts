/* eslint-env mocha */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistryLibrary = artifacts.require('DIDRegistryLibrary')
const DIDRegistry = artifacts.require('DIDRegistry')
const NFT = artifacts.require('NFT721Upgradeable')
const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')

contract('Mintable DIDRegistry (ERC-721)', (accounts) => {
    const owner = accounts[1]
    const other = accounts[2]
    const consumer = accounts[3]
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'http://metadata.nevermined.network/'
    let didRegistry
    let didRegistryLibrary
    let nft

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!didRegistry) {
            didRegistryLibrary = await DIDRegistryLibrary.new()
            await DIDRegistry.link(didRegistryLibrary)

            nft = await NFT.new()
            await nft.initializeWithAttributes('', '', nftMetadataURL, 0)

            const StandardRoyalties = artifacts.require('StandardRoyalties')
            const standardRoyalties = await StandardRoyalties.new()

            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, nft.address, constants.address.zero, standardRoyalties.address)
            await standardRoyalties.initialize(didRegistry.address)
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
                didRegistry.methods['mint721(bytes32)'](did, { from: owner }),
                'NFT721 not initialized'
            )

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                didRegistry.burn721(did, 0, { from: owner }),
                'NFT721 not initialized'
            )
        })

        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, true, { from: owner })

            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const tokenId = tokenIds[0]
            const nftOwner = await nft.ownerOf(tokenId)
            assert.strictEqual(owner, nftOwner)

            const _nftURI = await nft.tokenURI(tokenId)
            assert.strictEqual(`${nftMetadataURL}${tokenId}`, _nftURI)

            await didRegistry.burn721(did, tokenId, { from: owner })
            await assert.isRejected(nft.ownerOf(tokenId))
        })

        it('The royalties should be initialized and retrieved (ERC-2981)', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, 10, true, { from: owner })

            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const tokenId = tokenIds[0]

            const nftOwner = await nft.ownerOf(tokenId)
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

            await didRegistry.enableAndMintDidNft721(did, 0, true, { from: owner })

            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const tokenId = tokenIds[0]

            const nftOwner = await nft.ownerOf(tokenId)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should mint if is not capped', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, false, { from: owner })

            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const lastTokenId = tokenIds[tokenIds.length -1]

            await assert.isRejected(nft.ownerOf(lastTokenId + 1))

            await didRegistry.mint721(did, { from: owner })

            const { tokenIds: tokenIdsAfter, eventIds: eventIdsAfter } = await nft.tokenDetailsOfOwner(owner)
            const lastTokenIdAfter = tokenIdsAfter[tokenIdsAfter.length -1]

            const nftOwner = await nft.ownerOf(lastTokenIdAfter)
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
                didRegistry.enableAndMintDidNft721(did, 0, true, { from: other }),
                'Only owner'
            )

            await didRegistry.enableAndMintDidNft721(did, 0, true, { from: owner })
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

            await didRegistry.enableAndMintDidNft721(did, 0, false, { from: owner })

            await didRegistry.methods['mint721(bytes32,address)'](
                did,
                other,
                { from: owner }
            )

            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const lastTokenId = tokenIds[tokenIds.length -1]

            await assert.isRejected(
                // Must not allow to burn if not NFT holder
                didRegistry.methods['burn721(bytes32,uint256)'](did, lastTokenId, { from: consumer}),
                'ERC721: burn amount exceeds balance'
            )

            const { tokenIds: tokenIdsOther, eventIds: eventIdsOther } = await nft.tokenDetailsOfOwner(other)
            const lastTokenIdOther = tokenIdsOther[tokenIdsOther.length -1]

            await didRegistry.methods['burn721(bytes32,uint256)'](did, lastTokenIdOther, { from: other})
        })

        it('Checks the royalties are right', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 100000, false, { from: owner })
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

        it('Should not mint a NFTs over minting cap', async () => {
            const didRegistryLibrary = await DIDRegistryLibrary.new()
            const FreshDIDRegistry = artifacts.require('DIDRegistry')
            await FreshDIDRegistry.link(didRegistryLibrary)

            const StandardRoyalties = artifacts.require('StandardRoyalties')
            const standardRoyalties = await StandardRoyalties.new()
            didRegistry = await FreshDIDRegistry.new()

            const nftCapped = await NFT.new()
            await nftCapped.initializeWithAttributes('', '', nftMetadataURL, 1)
            await nftCapped.addMinter(didRegistry.address)


            await didRegistry.initialize(owner, constants.address.zero, nftCapped.address, constants.address.zero, standardRoyalties.address)

            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, 0, false, { from: owner })

            await didRegistry.mint721(did, { from: owner })
            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(owner)
            const tokenId = tokenIds[0]

            let nftOwner = await nft.ownerOf(tokenId)
            assert.strictEqual(owner, nftOwner)

            await assert.isRejected(
                didRegistry.mint721(did, { from: owner }),
                'ERC721: Cap exceed'
            )
            nftOwner = await nft.ownerOf(tokenId)
            assert.strictEqual(owner, nftOwner)
        })
    })
})
