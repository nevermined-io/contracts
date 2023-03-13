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
    const blocksExpiring = 3
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

    before(async () => {
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, constants.address.zero, constants.address.zero)

        nft = await TestERC1155.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestERC1155', 'TEST', '', { from: owner })
        await nft.grantOperatorRole(minter)
    })

    let nft
    let didRegistry

    async function setupTest() {

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
            const blockWhenMinted = new BigNumber(await nft.whenWasMinted(account1, tokenIdExpiring))
            assert.isTrue(blockWhenMinted > 0)
            assert.isTrue(blockWhenMinted < now)
        })
    })
})
