/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const DIDRegistry = artifacts.require('DIDRegistry')
const POAPUpgradeable = artifacts.require('POAPUpgradeable')

const testUtils = require('../../helpers/utils.js')
const constants = require('../../helpers/constants.js')
const BigNumber = require('bignumber.js')

contract('POAP', (accounts) => {
    const eventId = testUtils.generateId()

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
        const config = await artifacts.require('NeverminedConfig').new()
        await config.initialize(owner, owner, true)
        didRegistry = await DIDRegistry.new()
        await didRegistry.initialize(owner, constants.address.zero, constants.address.zero, config.address, constants.address.zero)

        nft = await POAPUpgradeable.new({ from: deployer })
        await nft.initialize(owner, didRegistry.address, 'TestPOAP', 'TEST', '', 0, config.address, { from: owner })

        await nft.setNvmConfigAddress(config.address, { from: owner })
        await config.grantNVMOperatorRole(didRegistry.address, { from: owner })
        await config.grantNVMOperatorRole(owner, { from: owner })
        await config.grantNVMOperatorRole(minter, { from: owner })
    }

    describe('As a minter I want to distribute POAPs', () => {
        it('As a minter I am minting a POAP', async () => {
            await setupTest()

            await nft.methods['mint(address,uint256)'](
                account1,
                eventId,
                { from: minter }
            )
        })

        it('The receiver has the right balance for POAPs', async () => {
            const balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 1)
        })

        it('The minter can mint more POAPs for the same and other users', async () => {
            await nft.methods['mint(address,uint256)'](
                account1,
                eventId,
                { from: minter }
            )

            await nft.methods['mint(address,uint256)'](
                account2,
                eventId,
                { from: minter }
            )
        })

        it('And everybody has the right POAPs balances', async () => {
            const balance = new BigNumber(await nft.balanceOf(account1))
            assert.strictEqual(balance.toNumber(), 2)

            const balance2 = new BigNumber(await nft.balanceOf(account2))
            assert.strictEqual(balance2.toNumber(), 1)
        })

        it('The receiver can get the correct token details', async () => {
            const { tokenIds, eventIds } = await nft.tokenDetailsOfOwner(account1)

            assert.strictEqual(tokenIds.length, 2)
            assert.strictEqual(eventIds.length, 2)

            const poaps = eventIds
                .map(v => new BigNumber(v).toNumber())
                .filter((v, i, a) => a.indexOf(v) === i)

            assert.strictEqual(poaps.length, 1)
            assert.strictEqual(new BigNumber(tokenIds[0]).toNumber(), 1)
            assert.strictEqual(new BigNumber(tokenIds[1]).toNumber(), 2)
            assert.strictEqual(new BigNumber(eventIds[0]).toNumber(), BigNumber(eventId).toNumber())
            assert.strictEqual(new BigNumber(eventIds[1]).toNumber(), BigNumber(eventId).toNumber())
        })
    })
})
