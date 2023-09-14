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
        config = await artifacts.require('NeverminedConfig').new()
        await config.initialize(owner, owner, true)
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, config.address, constants.address.zero)

        nft = await TestERC721.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestERC721', 'TEST', '', 0, { from: owner })

        await nft.setNvmConfigAddress(config.address, {from: owner})
        await config.setOperator(didRegistry.address, {from: owner})
        await config.setOperator(owner, {from: owner})
        await config.setOperator(minter, {from: owner})
    }

    describe('As a minter I want to use NFTs as subscriptions', () => {
        it('As a minter I am minting a subscription that will expire in a few blocks', async () => {
            await setupTest()

            await increaseTime.mineBlocks(web3, 10000)

            const currentBlockNumber = await ethers.provider.getBlockNumber()

            console.log('currentBlockNumber', currentBlockNumber)
            await nft.mint(account1, tokenIdExpiring, currentBlockNumber + blocksExpiring, { from: minter })
        })

        it('I want to check Im using a subscription contract', async () => {
            assert.strictEqual(await nft.nftType(), web3.utils.soliditySha3('nft721-subscription'))
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

    describe('Mint and burn', () => {
        it('New tokens can be minted and burned', async () => {
            await setupTest()

            let balance
            const newTokenIdExpiring = testUtils.generateId()
            const newTokenIdNotExpiring = testUtils.generateId()
            const currentBlockNumber = await ethers.provider.getBlockNumber()

            balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 0)

            await nft.mint(account1, newTokenIdExpiring, currentBlockNumber + blocksExpiring, { from: minter })
            balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 1)

            await nft.mint(account1, newTokenIdNotExpiring, 90000, { from: minter })
            balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 2)

            await increaseTime.mineBlocks(web3, blocksExpiring + 1)

            balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 1)

            await nft.burn(newTokenIdExpiring, { from: account1 })
            balance = new BigNumber(await nft.balanceOf(account1))
            // Balance is still 1 because the other token is not expiring yet
            assert.strictEqual(balance.toNumber(), 1)

            await nft.burn(newTokenIdNotExpiring, { from: account1 })
            balance = new BigNumber(await nft.balanceOf(account1))
            // Balance is now 0
            assert.strictEqual(balance.toNumber(), 0)
        })
    })
})
