/* eslint-env mocha */
/* global artifacts, contract, it */
const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const CurveRoyalties = artifacts.require('CurveRoyalties')
const NFT = artifacts.require('NFT1155Upgradeable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')

contract('CurveRoyalties', (accounts) => {
    const owner = accounts[1]
    const other = accounts[2]
    const consumer = accounts[3]
    const value = 'https://nevermined.io/did/nevermined/test-attr-example.txt'
    let didRegistry
    let royalties
    let nft

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!didRegistry) {
            const config = await artifacts.require('NeverminedConfig').new()
            await config.initialize(owner, owner, true)
            didRegistry = await DIDRegistry.new()
            await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, config.address, constants.address.zero)

            nft = await NFT.new()
            await nft.initialize(owner, didRegistry.address, 'NFT1155', 'NVM', '')

            royalties = await CurveRoyalties.new()
            await royalties.initialize(didRegistry.address)
            await didRegistry.registerRoyaltiesChecker(royalties.address, { from: owner })

            await nft.setNvmConfigAddress(config.address, { from: owner })
            await config.setOperator(didRegistry.address, { from: owner })
            await config.setOperator(owner, { from: owner })
        }
    }

    it('setting royalty', async () => {
        const didSeed = testUtils.generateId()
        const did = await didRegistry.hashDID(didSeed, owner)
        const checksum = testUtils.generateId()

        await didRegistry.registerDID(didSeed, checksum, [], value, '0x0', '', { from: owner })
        await didRegistry.setDIDRoyalties(did, royalties.address, { from: owner })
        await royalties.setRoyalty(did, 10000, { from: owner })
        assert.strictEqual(10000, (await royalties.royalties(did)).toNumber())
    })

    it('checking royalty', async () => {
        const didSeed = testUtils.generateId()
        const did = await didRegistry.hashDID(didSeed, owner)
        const checksum = testUtils.generateId()

        await didRegistry.registerDID(didSeed, checksum, [], value, '0x0', '', { from: owner })
        await didRegistry.setDIDRoyalties(did, royalties.address, { from: owner })
        await didRegistry.enableAndMintDidNft(did, nft.address, 10, 0, false, '', { from: owner })
        await royalties.setRoyalty(did, 100000, { from: owner })

        assert.isNotOk( // MUST BE FALSE. Royalties for original creator are too low
            await royalties.check(did, [91, 9], [consumer, owner], nft.address))

        assert.isOk( // MUST BE TRUE. There is not payment
            await royalties.check(did, [], [], nft.address))

        assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
            await royalties.check(did, [90, 10], [other, owner], nft.address))

        assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
            await royalties.check(did, [10, 90], [owner, other], nft.address))

        assert.isNotOk( // MUST BE FALSE. Original creator is not getting royalties
            await royalties.check(did, [100], [other], nft.address)
        )

        await nft.methods['mint(uint256,uint256)'](did, 5, { from: owner })
        assert.isNotOk( // MUST BE FALSE. Royalties for original creator are too low
            await royalties.check(did, [96, 4], [consumer, owner], nft.address))

        assert.isOk( // MUST BE TRUE. There is not payment
            await royalties.check(did, [], [], nft.address))

        assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
            await royalties.check(did, [91, 10], [other, owner], nft.address))

        assert.isOk( // MUST BE TRUE. Original creator is getting 10% by royalties
            await royalties.check(did, [9, 91], [owner, other], nft.address))

        assert.isNotOk( // MUST BE FALSE. Original creator is not getting royalties
            await royalties.check(did, [100], [other], nft.address)
        )
    })
})
