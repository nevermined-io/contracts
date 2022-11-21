/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)
const { ethers } = require('hardhat')

const NFT721 = artifacts.require('NFT721Upgradeable')
const NFT1155 = artifacts.require('NFTUpgradeable')

const testUtils = require('../../helpers/utils.js')
const increaseTime = require('../../helpers/increaseTime.js')
const BigNumber = require('bignumber.js')

contract('NFT Clones', (accounts) => {
    const web3 = global.web3

    const tokenIdExpiring = testUtils.generateId()

    const [
        owner,
        deployer,
        minter,
        account1,
        account2
    ] = accounts

    before(async () => {
    })

    let nft721
    let nft

    async function setupTest() {
        nft721 = await NFT721.new({ from: deployer })
        await nft721.initializeWithName('TestERC721', 'TEST', 'http', 10, { from: owner })
        await nft721.addMinter(minter)
    }

    describe('As a user I want to clone an existing ERC-721 NFT Contract', () => {
        it('I can clone an existing ERC-721 NFT Contract', async () => {
            await setupTest()

            const cloneAddress = await nft721.createClone(nft721.address, 'My Name', 'xXx', 'cid', 100, { from: account1 })

            assert.notEqual(nft721.address, cloneAddress)

            const newNFT = await NFT721(cloneAddress)
            const newName = await newNFT.name()
            assert.strictEqual('My Name', newName)
        })

//        it('If the address is wrong the clone fails', async () => {
//        })
//
//        it('', async () => {
//        })


    })
})
