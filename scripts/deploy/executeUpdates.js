const fs = require('fs')
const Safe = require('@gnosis.pm/safe-core-sdk')
const { loadWallet } = require('./wallets')
const EthersAdapter = require('@gnosis.pm/safe-ethers-lib').default
const { ethers } = require('hardhat')

async function main() {
    const { roles, contractNetworks } = await loadWallet({})
    const transactions = JSON.parse(fs.readFileSync('transactions.json'))
    for (const tx of transactions) {
        const ethAdapterOwner = new EthersAdapter({ ethers, signer: ethers.provider.getSigner(1), contractNetworks })
        const safeSdk = await Safe.default.create({ ethAdapter: ethAdapterOwner, safeAddress: roles.upgraderWallet, contractNetworks })
        const safeTx = await safeSdk.createTransaction({ ...tx, value: 0 })
        const res = await safeSdk.executeTransaction(safeTx)
        await res.transactionResponse?.wait()
        console.log('Approved transaction')
    }
}

main()
