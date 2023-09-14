/* eslint-env mocha */
/* global artifacts, contract, describe, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const NFT = artifacts.require('NFT721Upgradeable')
const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')

contract('Mintable DIDRegistry (ERC-721)', (accounts) => {
    const deployer = accounts[0]
    const owner = accounts[1]
    const other = accounts[2]
    const consumer = accounts[3]
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    const nftMetadataURL = 'https://nevermined.io/metadata/'
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
            await nft.initialize(owner, didRegistry.address, '', '', nftMetadataURL, 0, { from: deployer })

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
                nft.mint(did, { from: owner })
            )

            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.burn(did, did, { from: owner })
            )
        })

        it('Should mint and burn NFTs after initialization', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, true, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            await nft.burn(did, { from: owner })
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
            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, true, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            const _nftURI = await nft.tokenURI(did)
            assert.strictEqual(`${nftMetadataURL}${did}`, _nftURI)
        })

        it('The royalties should be initialized and retrieved (ERC-2981)', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, nft.address, 10, true, { from: owner })

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

            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, true, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should mint if is not capped', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, false, { from: owner })

            await assert.isRejected(nft.ownerOf(did))

            await nft.methods['mint(uint256)'](did, { from: owner })

            const nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)
        })

        it('Should not mint a NFTs over minting cap', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, false, { from: owner })

            await nft.methods['mint(uint256)'](did, { from: owner })
            let nftOwner = await nft.ownerOf(did)
            assert.strictEqual(owner, nftOwner)

            await assert.isRejected(
                nft.methods['mint(uint256)'](did, { from: owner }),
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
                didRegistry.enableAndMintDidNft721(did, nft.address, 0, true, { from: other }),
                'Only owner'
            )

            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, true, { from: owner })
            await assert.isRejected(
                // Must not allow to mint tokens without previous initialization
                nft.methods['mint(uint256)'](did, { from: other }),
                'only nft operator can mint'
            )
        })

        it('Should not burn if not NFT Holder', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()
            await didRegistry.registerAttribute(
                didSeed, checksum, [], value, { from: owner })

            await didRegistry.enableAndMintDidNft721(did, nft.address, 0, false, { from: owner })

            await nft.methods['mint(address,uint256)'](
                other,
                did,
                { from: owner }
            )

            await assert.isRejected(
                // Must not allow to burn if not NFT holder
                nft.burn(did, { from: consumer }),
                'ERC721: caller is not owner or not have balance'
            )

            await nft.burn(did, { from: other })
        })

        it('Checks the royalties are right', async () => {
            const didSeed = testUtils.generateId()
            const did = await didRegistry.hashDID(didSeed, owner)
            const checksum = testUtils.generateId()

            await didRegistry.registerAttribute(didSeed, checksum, [], value, { from: owner })
            await didRegistry.enableAndMintDidNft721(did, nft.address, 100000, false, { from: owner })
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
