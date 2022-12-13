/* eslint-disable no-console */
// List of contracts
// eslint-disable-next-line security/detect-non-literal-require
const contractNames = require('./contracts.json')
const coreContractNames = require('./contracts-core.json')
const { argv } = require('yargs')

function evaluateContracts({
    contracts,
    testnet,
    verbose
} = {}) {
    console.log('testnet', testnet)
    const core = coreContractNames
    if (!contracts || contracts.length === 0) {
        // contracts not supplied, loading from disc
        contracts = contractNames

        // if we are on a testnet, add dispenser
        if (
            testnet || argv['with-token'] ||
            contracts.indexOf('NeverminedToken') >= 0
        ) {
            // deploy the NeverminedTokens if we are in a testnet
            core.push('NeverminedToken')
            contracts = contracts.filter(a => a !== 'NeverminedToken')
        }

        // if we are on a testnet, add dispenser
        if (testnet && contracts.indexOf('Dispenser') < 0) {
            // deploy the Dispenser if we are in a testnet
            contracts.push('Dispenser')
        }
    }

    if (verbose) {
        console.log(
            `Contracts: '${contracts.join(', ')}'`
        )
    }

    return { contracts, core }
}

module.exports = evaluateContracts
