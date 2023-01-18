const { argv } = require('yargs')
const { upgradeContracts } = require('./upgradeContracts')

async function main() {
    const parameters = argv._
    const verbose = true
    const testnet = process.env.TESTNET === 'true'
    const fail = process.env.FAIL === 'true'
    await upgradeContracts({
        contracts: parameters.splice(2),
        verbose,
        testnet,
        fail
    })
}

main()
