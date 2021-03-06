/* global web3, artifacts */
const { argv } = require('yargs')
const { audit } = require('@nevermined-io/contract-tools')
const evaluateContracts = require('./evaluateContracts.js')

module.exports = (cb) => {
    audit({
        web3,
        artifacts,
        evaluateContracts,
        strict: false,
        verbose: argv.verbose && true,
        testnet: argv.testnet || false
    })
        .then(() => cb())
        .catch(err => cb(err))
}
