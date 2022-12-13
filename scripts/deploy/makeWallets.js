const { loadWallet } = require('./wallets')

async function main() {
    const { roles } = await loadWallet({ makeWallet: true })
    console.log(roles)
}

main()
