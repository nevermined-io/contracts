/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const DIDRegistry = artifacts.require('DIDRegistry')
const TestERC721 = artifacts.require('NFT721SubscriptionUpgradeable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const increaseTime = require('../../helpers/increaseTime.js')
const BigNumber = require('bignumber.js')

contract('NFT721 Subscription', (accounts) => {
    const web3 = global.web3

    const tokenIdExpiring = testUtils.generateId()
    const tokenIdNonExpiring = testUtils.generateId()

    const blocksExpiring = 3
    const blocksNonExpiring = 0

    const [
        owner,
        deployer,
        minter,
        account1,
        account2
    ] = accounts

    before(async () => {
    })

    let nft
    let didRegistry

    async function setupTest() {
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, constants.address.zero, constants.address.zero)

        nft = await TestERC721.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestERC721', 'TEST', '', 0, { from: owner })
        await nft.grantOperatorRole(minter)
    }

    describe('As a minter I want to use NFTs as subscriptions', () => {
        it('As a minter I am minting a subscription that will expire in a few blocks', async () => {
            await setupTest()

            const currentBlockNumber = await ethers.provider.getBlockNumber()

            await nft.mint(account1, tokenIdExpiring, currentBlockNumber + blocksExpiring, { from: minter })
        })

        it('The subscriber has the right balance for a non expired NFT', async () => {
            const balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 1)
        })

        it('The subscriber has no balance when the NFT is expired', async () => {
            // wait to expire the subscription
            await increaseTime.mineBlocks(web3, blocksExpiring)

            const balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 0)
        })

        it('The subscriber mints again and sees the right amount of tokens', async () => {
            const currentBlockNumber = await ethers.provider.getBlockNumber()

            await nft.mint(account1, testUtils.generateId(), currentBlockNumber + blocksExpiring, { from: minter })

            const balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 1)
        })

        it('As a minter I am minting a non expiring subscription', async () => {
            await nft.mint(account2, tokenIdNonExpiring, blocksNonExpiring, { from: minter })
        })

        it('The subscriber has the right balance for an unlimited subscription', async () => {
            const balance = new BigNumber(await nft.balanceOf(account2))
            assert.strictEqual(balance.toNumber(), 1)
        })

        it('The block when the NFT was minted is registered', async () => {
            const now = await ethers.provider.getBlockNumber()

            const blocksWhenMinted = await nft.whenWasMinted(account1)

            assert.isTrue(blocksWhenMinted.length === 2)
            var _mintedBefore = 0
            for (var index = 0; index < blocksWhenMinted.length; index++) {
                const _minted = new BigNumber(blocksWhenMinted[index])
                assert.isTrue(_minted > 0)
                assert.isTrue(_minted < now)
                assert.isTrue(_minted.gt(_mintedBefore))
                _mintedBefore = _minted
            }
        })
    })
})
