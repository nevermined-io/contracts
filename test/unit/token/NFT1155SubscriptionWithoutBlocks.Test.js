/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const TestERC1155 = artifacts.require('NFT1155SubscriptionWithoutBlocks')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const BigNumber = require('bignumber.js')

contract('NFT1155 Subscription', (accounts) => {
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
        const config = await artifacts.require('NeverminedConfig').new()
        await config.initialize(owner, owner, true)
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, config.address, constants.address.zero)

        nft = await TestERC1155.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestERC1155', 'TEST', '', config.address, { from: owner })

        await nft.setNvmConfigAddress(config.address, { from: owner })
        await config.grantNVMOperatorRole(didRegistry.address, { from: owner })
        await config.grantNVMOperatorRole(owner, { from: owner })
        await config.grantNVMOperatorRole(minter, { from: owner })
    }

    describe('Providers can burn', () => {
        const initialAmount = 10
        let tokenId

        it('As a minter can register a DID without providers', async () => {
            await setupTest()
            const didSeed = testUtils.generateId()

            tokenId = await didRegistry.hashDID(didSeed, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            await nft.methods[
                'mint(address,uint256,uint256,bytes)'
            ](account1, tokenId, initialAmount, data, { from: minter })

            const balance = new BigNumber(await nft.balanceOf(account1, tokenId))
            assert.strictEqual(balance.toNumber(), initialAmount)
        })

        it('NFT holder can burn', async () => {
            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account1, tokenId, 1, { from: account1 })

            const balance = new BigNumber(await nft.balanceOf(account1, tokenId))
            assert.strictEqual(balance.toNumber(), initialAmount - 1)
        })

        it('Account can not burn unless is a provider', async () => {
            await assert.isRejected(
                nft.methods[
                    'burn(address,uint256,uint256)'
                ](account1, tokenId, 1, { from: account2 }),
                'ERC1155: caller is not owner nor approved'
            )

            let balance = new BigNumber(await nft.balanceOf(account1, tokenId))
            assert.strictEqual(balance.toNumber(), initialAmount - 1)

            await didRegistry.addDIDProvider(tokenId, account2, { from: minter })

            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account1, tokenId, 1, { from: account2 })

            balance = new BigNumber(await nft.balanceOf(account1, tokenId))
            assert.strictEqual(balance.toNumber(), initialAmount - 2)
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

            // MINT 7 tokens
            await nft.methods[
                'mint(address,uint256,uint256,bytes)'
            ](account2, tokenId3, 7, data, { from: minter })

            // Balance is 7
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 7)

            // MINT 10 tokens
            await nft.methods[
                'mint(address,uint256,uint256,bytes)'
            ](account2, tokenId3, 10, data, { from: minter })

            // Balance is 17
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 17)

            // BURN 4 tokens
            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account2, tokenId3, 4, { from: minter })

            // Balance is 13
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 13)

            // Batch mint
            const didSeed4 = testUtils.generateId()
            const tokenId4 = await didRegistry.hashDID(didSeed4, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed4, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            // Also test balance batch
            await nft.mintBatch(account2, [tokenId3, tokenId4], [10, 15], data, { from: minter })
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            let balance2 = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 23)
            assert.strictEqual(balance2.toNumber(), 15)

            const balances = (await nft.balanceOfBatch([account2, account2], [tokenId3, tokenId4])).map(a => new BigNumber(a).toNumber())
            assert.strictEqual(balances[0], 23)
            assert.strictEqual(balances[1], 15)

            await nft.burnBatchFromHolders([account2, account2], [tokenId3, tokenId4], [22, 14], { from: minter })
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            balance2 = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 1)
            assert.strictEqual(balance2.toNumber(), 1)
        })
    })
})
