const evaluateContracts = require('../../scripts/deploy/truffle-wrapper/evaluateContracts')
const initializeContracts = require('../../scripts/deploy/truffle-wrapper/deploy/initializeContracts')
const setupContracts = require('../../scripts/deploy/truffle-wrapper/deploy/setupContracts')

const {
    upgradeContracts,
    deployContracts
} = require('@nevermined-io/contract-tools')

const deploy = async function({
    web3,
    artifacts,
    contracts,
    verbose
}) {
    return deployContracts({
        web3,
        artifacts,
        contracts,
        evaluateContracts: ({
            contracts,
            testnet,
            verbose
        }) => evaluateContracts({
            contracts,
            testnet,
            verbose,
            handleAliases: false
        }),
        initializeContracts,
        setupContracts,
        forceWalletCreation: true,
        deeperClean: true,
        verbose
    })
}

const upgrade = async function({
    web3,
    contracts,
    verbose
}) {
    const taskBook = await upgradeContracts({
        web3,
        contracts,
        evaluateContracts: ({
            contracts,
            testnet,
            verbose
        }) => evaluateContracts({
            contracts,
            testnet,
            verbose,
            handleAliases: false
        }),
        strict: true,
        verbose
    })

    return taskBook
}

module.exports = {
    deploy,
    upgrade
}
