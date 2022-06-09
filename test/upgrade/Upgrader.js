const { upgradeContracts } = require('../../scripts/deploy/truffle-wrapper/upgradeContracts')
const { deployContracts } = require('../../scripts/deploy/truffle-wrapper/deployContracts')

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
        forceWalletCreation: true,
        deeperClean: true,
        verbose,
        addresses: []
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
        strict: true,
        verbose
    })

    return taskBook
}

module.exports = {
    deploy,
    upgrade
}
