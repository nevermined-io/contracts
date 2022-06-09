/* eslint-env mocha */
/* eslint-disable no-console */
/* global artifacts, contract, describe, it, web3 */

const chai = require('chai')
const { assert } = chai
const chaiAsPromised = require('chai-as-promised')
chai.use(chaiAsPromised)

const NeverminedConfig = artifacts.require('NeverminedConfig')

const constants = require('../../helpers/constants.js')

contract('NeverminedConfig', (accounts) => {
    const deployer = accounts[0]
    const owner = accounts[1]
    const governor = accounts[2]
    const governorRole = web3.utils.sha3('NVM_GOVERNOR_ROLE')
    let nvmConfig

    beforeEach(async () => {
        await setupTest()
    })

    async function setupTest() {
        if (!nvmConfig) {
            nvmConfig = await NeverminedConfig.new({ from: deployer })
            await nvmConfig.initialize(owner, governor, { from: deployer })
        }
    }

    describe('We can apply some configuration', () => {
        it('Configuration only can be changed by the Governor', async () => {
            await assert.isRejected(
                nvmConfig.setMarketplaceFees(5, accounts[3], { from: owner }),
                'NeverminedConfig: Only governor'
            )
        })

        it('We setup the marketplace fees configuration', async () => {
            await nvmConfig.setMarketplaceFees(5, accounts[3], { from: governor })
            const marketplaceFee = await nvmConfig.getMarketplaceFee()
            const feeReceiver = await nvmConfig.getFeeReceiver()

            assert.strictEqual(5, marketplaceFee.toNumber())
            assert.strictEqual(accounts[3], feeReceiver)
        })

        it('Marketplace fees should be in the right range', async () => {
            await assert.isRejected(
                nvmConfig.setMarketplaceFees(10001, accounts[3], { from: governor }),
                'NeverminedConfig: Fee must be between 0 and 100 percent'
            )
            await assert.isRejected(
                nvmConfig.setMarketplaceFees(5, constants.address.zero, { from: governor }),
                'NeverminedConfig: Receiver can not be 0x0'
            )
        })
    })

    describe('Only the owner can grant Governor permissions', () => {
        it('The owner grants governor permissions', async () => {
            const newGovernor = accounts[0]
            await nvmConfig.grantRole(
                governorRole, newGovernor,
                { from: owner })

            const isGovernor = await nvmConfig.isGovernor(accounts[0])
            assert.strictEqual(true, isGovernor)
        })

        it('The governor can not grant governor permissions', async () => {
            await assert.isRejected(
                nvmConfig.grantRole(governorRole, accounts[0], { from: governor }
                )
            )
        })
    })
})
