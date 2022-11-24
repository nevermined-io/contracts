/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const NFT721 = artifacts.require('NFT721Upgradeable')
const NFT1155 = artifacts.require('NFT1155Upgradeable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const BigNumber = require('bignumber.js')

contract('NFT Clones', (accounts) => {
    const [
        owner,
        deployer,
        account1
    ] = accounts

    before(async () => {
    })

    let nft721
    let nft1155

    async function setupTest() {
        nft721 = await NFT721.new({ from: deployer })
        await nft721.initializeWithAttributes('TestERC721', 'TEST', 'http', 10, { from: owner })

        nft1155 = await NFT1155.new({ from: deployer })
        await nft1155.initializeWithName('TestERC1155', '1155', 'http', { from: owner })
    }

    describe('As a user I want to clone an existing ERC-721 NFT Contract', () => {
        it('I can clone an existing ERC-721 NFT Contract', async () => {
            await setupTest()

            const result = await nft721.createClone(nft721.address, 'My Name', 'xXx', 'cid', 100, { from: account1 })

            const eventArgs = testUtils.getEventArgsFromTx(result, 'NFTCloned')

            const cloneAddress = eventArgs._newAddress
            const implementationAddress = eventArgs._fromAddress
            const ercType = eventArgs._ercType

            assert.notEqual(nft721.address, cloneAddress)
            assert.strictEqual(nft721.address, implementationAddress)
            assert.strictEqual(721, new BigNumber(ercType).toNumber())

            const signer = await ethers.provider.getSigner(account1)
            const instance = await ethers.getContractAt('NFT721Upgradeable', cloneAddress, signer)
            const newName = await instance.name()

            assert.strictEqual('My Name', newName)
        })

        it('If the address is wrong the clone fails', async () => {
            await assert.isRejected(
                nft721.createClone(constants.address.dummy, 'My Name', 'xXx', 'cid', 100, { from: account1 }),
                'Invalid contract address'
            )
        })
    })

    describe('As a user I want to clone an existing ERC-1155 NFT Contract', () => {
        it('I can clone an existing ERC-1155 NFT Contract', async () => {
            await setupTest()

            const result = await nft1155.createClone(nft1155.address, 'My 1155', 'yYy', 'cid', { from: account1 })

            const eventArgs = testUtils.getEventArgsFromTx(result, 'NFTCloned')

            const cloneAddress = eventArgs._newAddress
            const implementationAddress = eventArgs._fromAddress
            const ercType = eventArgs._ercType

            assert.notEqual(nft1155.address, cloneAddress)
            assert.strictEqual(nft1155.address, implementationAddress)
            assert.strictEqual(1155, new BigNumber(ercType).toNumber())

            const signer = await ethers.provider.getSigner(account1)
            const instance = await ethers.getContractAt('NFT1155Upgradeable', cloneAddress, signer)
            const newName = await instance.name()

            assert.strictEqual('My 1155', newName)
        })

        it('If the address is wrong the clone fails', async () => {
            await assert.isRejected(
                nft1155.createClone(constants.address.dummy, 'My Name', 'xXx', 'cid', { from: account1 }),
                'Invalid contract address'
            )
        })
    })
})
