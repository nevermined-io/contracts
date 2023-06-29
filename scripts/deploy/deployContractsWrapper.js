const { argv } = require('yargs')
const { deployContracts } = require('./deployContracts')
const fs = require('fs')

let addresses = {}

process.on('SIGINT', () => {
    console.log('got interrupted, trying to exit cleanly')
    fs.writeFileSync('deploy-cache.json', JSON.stringify(addresses, undefined, 2))
    process.exit(1)
})

async function main() {
    const verbose = true
    const testnet = process.env.TESTNET === 'true'
    let restore = false
    try {
        try {
            addresses = JSON.parse(fs.readFileSync('deploy-cache.json'))
            console.log('Resuming deployment from deploy-cache.json')
            restore = true
        } catch (e) {
            addresses = {}
        }
        // read addresses from artifacts

        await deployContracts({
            contracts: argv._.splice(2),
            verbose,
            makeWallet: false,
            testnet,
            addresses,
            restore
        })
    } catch (err) {
        console.log(err)
        fs.writeFileSync('deploy-cache.json', JSON.stringify(addresses, undefined, 2))
        process.exit(1)
    }
    process.exit(0)
}

main()
