/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const TestERC721 = artifacts.require('NFT721SubscriptionUpgradeable')

const testUtils = require('../../helpers/utils.js')
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

    async function setupTest() {
        nft = await TestERC721.new({ from: deployer })
        await nft.initialize({ from: owner })
        await nft.addMinter(minter)
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

        it('As a minter I am minting a non expiring subscription', async () => {
            await nft.mint(account2, tokenIdNonExpiring, blocksNonExpiring, { from: minter })
        })

        it('The subscriber has the right balance for an unlimited subscription', async () => {
            const balance = new BigNumber(await nft.balanceOf(account2))
            assert.strictEqual(balance.toNumber(), 1)
        })
    })
})
