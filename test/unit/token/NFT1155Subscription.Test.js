/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const DIDRegistry = artifacts.require('DIDRegistry')
const TestERC1155 = artifacts.require('NFT1155SubscriptionUpgradeable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const increaseTime = require('../../helpers/increaseTime.js')
const BigNumber = require('bignumber.js')

contract('NFT1155 Subscription', (accounts) => {
    const web3 = global.web3

    const didSeedExpiring = testUtils.generateId()
    const didSeedNonExpiring = testUtils.generateId()

    let tokenIdExpiring
    let tokenIdNonExpiring

    const amount = 1
    const blocksExpiring = 10
    const blocksNonExpiring = 0
    const data = '0x'

    const checksum = testUtils.generateId()
    const url = 'https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png'

    const [
        owner,
        deployer,
        minter,
        account1,
        account2
    ] = accounts

    let nft
    let didRegistry

    async function setupTest() {
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, constants.address.zero, constants.address.zero)

        nft = await TestERC1155.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestERC1155', 'TEST', '', { from: owner })
        await nft.grantOperatorRole(minter)
    }

    describe('As a minter I want to use NFTs as subscriptions', () => {
        it('As a minter I am minting a subscription that will expire in a few blocks', async () => {
            await setupTest()

            tokenIdExpiring = await didRegistry.hashDID(didSeedExpiring, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeedExpiring, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            const currentBlockNumber = await ethers.provider.getBlockNumber()

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account1, tokenIdExpiring, amount, currentBlockNumber + blocksExpiring, data, { from: minter })
        })

        it('I want to check Im using a subscription contract', async () => {
            assert.strictEqual(await nft.nftType(), web3.utils.soliditySha3('nft1155-subscription'))
        })

        it('The subscriber has the right balance for a non expired NFT', async () => {
            const balance = new BigNumber(await nft.balanceOf(account1, tokenIdExpiring))
            assert.strictEqual(balance.toNumber(), amount)
        })

        it('The subscriber has no balance when the NFT is expired', async () => {
            // wait to expire the subscription
            await increaseTime.mineBlocks(web3, blocksExpiring)

            const balance = new BigNumber(await nft.balanceOf(account1, tokenIdExpiring))
            assert.strictEqual(balance.toNumber(), 0)
        })

        it('The subscriber mints again after expiration and get the right amount of tokens', async () => {
            // wait to expire the subscription
            await increaseTime.mineBlocks(web3, blocksExpiring)

            const currentBlockNumber = await ethers.provider.getBlockNumber()

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account1, tokenIdExpiring, amount, currentBlockNumber + blocksExpiring, data, { from: minter })

            const balance = new BigNumber(await nft.balanceOf(account1, tokenIdExpiring))
            assert.strictEqual(balance.toNumber(), amount)
        })

        it('As a minter I am minting a non expiring subscription', async () => {
            tokenIdNonExpiring = await didRegistry.hashDID(didSeedNonExpiring, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeedNonExpiring, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenIdNonExpiring, amount, blocksNonExpiring, data, { from: minter })
        })

        it('The subscriber has the right balance for an unlimited subscription', async () => {
            const balance = new BigNumber(await nft.balanceOf(account2, tokenIdNonExpiring))
            assert.strictEqual(balance.toNumber(), amount)
        })

        it('The block when the NFT was minted is registered', async () => {
            const now = await ethers.provider.getBlockNumber()
            const blocksWhenMinted = await nft.whenWasMinted(account1, tokenIdExpiring)

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
            const didSeed3 = testUtils.generateId()
            const tokenId3 = await didRegistry.hashDID(didSeed3, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed3, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            const currentBlockNumber = await ethers.provider.getBlockNumber()

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId3, 7, currentBlockNumber + blocksExpiring, data, { from: minter })

            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 7)

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId3, 10, currentBlockNumber + 500, data, { from: minter })

            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 17)

            await increaseTime.mineBlocks(web3, blocksExpiring)

            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 10)

            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account2, tokenId3, 15, { from: minter })

            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 2)
        })
    })
})
