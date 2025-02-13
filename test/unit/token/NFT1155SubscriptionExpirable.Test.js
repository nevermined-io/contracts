/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const TestERC1155 = artifacts.require('NFT1155SubscriptionExpirable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const BigNumber = require('bignumber.js')
const increaseTime = require('../../helpers/increaseTime.js')

contract('NFT1155 Subscription Expirable', (accounts) => {
    const web3 = global.web3

    const didSeedExpiring = testUtils.generateId()
    const didSeedNonExpiring = testUtils.generateId()

    let tokenIdExpiring
    let tokenIdNonExpiring

    const amount = 1
    const duration = 5 // in seconds
    // const datetimeExpiring = new Date().getTime()
    const datetimeNonExpiring = 0
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
        await nft.initialize(owner, didRegistry.address, 'TestERC1155Expirable', 'TEST', '', config.address, { from: owner })

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
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account1, tokenId, initialAmount, 0, data, { from: minter })

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

    describe('As a minter I want to use NFTs as expirable subscriptions', () => {
        it('As a minter I am minting a subscription that will expire in a few seconds', async () => {
            await setupTest()

            tokenIdExpiring = await didRegistry.hashDID(didSeedExpiring, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeedExpiring, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account1, tokenIdExpiring, amount, duration, data, { from: minter })
            const minted = await nft.getMintedEntries(account1, tokenIdExpiring)
            console.log('Minted', minted)
        })

        it('The subscriber has the right balance for a non expired NFT', async () => {
            const balance = new BigNumber(await nft.balanceOf(account1, tokenIdExpiring))
            assert.strictEqual(balance.toNumber(), amount)
        })

        it('The subscriber has no balance when the NFT is expired', async () => {
            // wait to expire the subscription
            await testUtils.sleep(duration * 1000)
            await increaseTime.mineBlocks(web3, 1)

            const balance = new BigNumber(await nft.balanceOf(account1, tokenIdExpiring))
            assert.strictEqual(balance.toNumber(), 0)
        })

        it('The subscriber mints again after expiration and get the right amount of tokens', async () => {
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account1, tokenIdExpiring, amount, duration, data, { from: minter })

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
            ](account2, tokenIdNonExpiring, amount, datetimeNonExpiring, data, { from: minter })
        })

        it('The subscriber has the right balance for an unlimited subscription', async () => {
            const balance = new BigNumber(await nft.balanceOf(account2, tokenIdNonExpiring))
            assert.strictEqual(balance.toNumber(), amount)
        })

        it('The block when the NFT was minted is registered', async () => {
            const now = new Date().getTime()
            const blocksWhenMinted = await nft.whenWasMinted(account1, tokenIdExpiring)

            assert.isTrue(blocksWhenMinted.length === 2)
            console.log('Block Now', now)
            console.log('Date Now', new Date().getTime())
            var _mintedBefore = 0
            for (var index = 0; index < blocksWhenMinted.length; index++) {
                const _minted = new BigNumber(blocksWhenMinted[index])
                console.log(`when was minted ${_minted}`)
                assert.isTrue(_minted > 0)
                assert.isTrue(_minted < now)
                assert.isTrue(_minted.gt(_mintedBefore))
                _mintedBefore = _minted
            }
        })

        it('I want to check Im using a subscription contract', async () => {
            assert.strictEqual(await nft.nftType(), web3.utils.soliditySha3('nft1155-subscription'))
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

            // const currentBlockNumber = await ethers.provider.getBlockNumber()

            // MINT 7 tokens
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId3, 7, duration, data, { from: minter })

            // Balance is 7
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 7)

            // MINT 10 tokens
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId3, 10, duration + 500, data, { from: minter })

            // Balance is 17
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 17)

            // EXPIRE 7 tokens
            await testUtils.sleep((duration + 1) * 1000)
            await increaseTime.mineBlocks(web3, 1)
            // await increaseTime.mineBlocks(web3, blocksExpiring)

            // Balance is 10
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 10)

            // BURN 4 tokens
            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account2, tokenId3, 4, { from: minter })

            // Balance is 6
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            assert.strictEqual(balance.toNumber(), 6)

            // Batch mint
            const didSeed4 = testUtils.generateId()
            const tokenId4 = await didRegistry.hashDID(didSeed4, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed4, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            // Also test balance batch
            await nft.mintBatch(account2, [tokenId3, tokenId4], [10, 15], [duration + 5000, duration + 5000], data, { from: minter })
            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            let balance2 = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 16)
            assert.strictEqual(balance2.toNumber(), 15)

            const balances = (await nft.balanceOfBatch([account2, account2], [tokenId3, tokenId4])).map(a => new BigNumber(a).toNumber())
            assert.strictEqual(balances[0], 16)
            assert.strictEqual(balances[1], 15)

            await nft.burnBatch(account2, [tokenId3, tokenId4], [15, 14], { from: minter })

            balance = new BigNumber(await nft.balanceOf(account2, tokenId3))
            balance2 = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 1)
            assert.strictEqual(balance2.toNumber(), 1)
        })

        it('Tokens are minted, burned and expired', async () => {
            await setupTest()

            let balance
            const didSeed4 = testUtils.generateId()
            const tokenId4 = await didRegistry.hashDID(didSeed4, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed4, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            // let currentBlockNumber = await ethers.provider.getBlockNumber()

            // We MINT 10 tokens
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId4, 10, duration, data, { from: minter })

            // Balance is 10
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 10)

            // We BURN 2 tokens
            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account2, tokenId4, 2, { from: minter })

            // Balance is 8
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 10 - 2)

            await testUtils.sleep(duration * 1000)
            await increaseTime.mineBlocks(web3, 1)

            // await increaseTime.mineBlocks(web3, blocksExpiring)

            // Balance is 0
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 0)

            // currentBlockNumber = await ethers.provider.getBlockNumber()

            // We MINT 15 tokens
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId4, 15, duration, data, { from: minter })

            // Balance is 15
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 15)

            // BURN 3 tokens
            await nft.methods[
                'burn(address,uint256,uint256)'
            ](account2, tokenId4, 3, { from: minter })

            // Balance is 12
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 12)

            // EXPIRE 12 tokens
            await testUtils.sleep(duration * 1000)
            await increaseTime.mineBlocks(web3, 1)

            // await increaseTime.mineBlocks(web3, blocksExpiring)

            // Balance is 0
            balance = new BigNumber(await nft.balanceOf(account2, tokenId4))
            assert.strictEqual(balance.toNumber(), 0)

            const minted = await nft.getMintedEntries(account2, tokenId4)
            for (var index = 0; index < minted.length; index++) {
                console.log(`Token ${minted[index].isMintOps ? 'MINTED' : 'BURNED'} on block ${minted[index].mintBlock}, amount ${minted[index].amountMinted} and expiring = ${minted[index].expirationBlock}`)
            }
            assert.strictEqual(minted.length, 4)
        })

        it('Multiple tokens can be burned without generating provenance issues', async () => {
            await setupTest()

            const didSeed5 = testUtils.generateId()
            const tokenId5 = await didRegistry.hashDID(didSeed5, minter)
            await didRegistry.methods[
                'registerMintableDID(bytes32,address,bytes32,address[],string,uint256,uint256,bool,bytes32,string,string)'
            ](didSeed5, nft.address, checksum, [], url, 0, 0, false, constants.activities.GENERATED, '', '', { from: minter })

            // const currentBlockNumber = await ethers.provider.getBlockNumber()

            // We MINT 10 tokens
            await nft.methods[
                'mint(address,uint256,uint256,uint256,bytes)'
            ](account2, tokenId5, 10, duration, data, { from: minter })

            // We BURN 1 tokens 2 times
            await nft.burnBatch(account2, [tokenId5, tokenId5], [1, 1], { from: minter })
            await testUtils.sleep(2 * 1000)
            // await increaseTime.mineBlocks(web3, 1)

            await increaseTime.mineBlocks(web3, 2)

            // Balance is 8
            const balance = new BigNumber(await nft.balanceOf(account2, tokenId5))
            assert.strictEqual(balance.toNumber(), 10 - 2)
        })
    })
})
