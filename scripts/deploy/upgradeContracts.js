const { upgrades, ethers } = require('hardhat')
const { readArtifact, updateArtifact, writeArtifact } = require('./artifacts')
const evaluateContracts = require('./evaluateContracts.js')
const Safe = require('@gnosis.pm/safe-core-sdk')
const { loadWallet } = require('./wallets')
const EthersAdapter = require('@gnosis.pm/safe-ethers-lib').default
const fs = require('fs')

// Only upgrade core contracts
async function upgradeContracts({ verbose, testnet, fail, strict }) {
    const { core: contracts } = evaluateContracts({
        verbose,
        testnet
    })

    let success
    try {
        success = JSON.parse(fs.readFileSync('upgrade-cache.json'))
    } catch (err) {
        success = {}
    }

    const taskBook = {}

    const transactions = []

    const { roles, contractNetworks } = await loadWallet({})

    for (const c of contracts) {
        if (success[c]) {
            console.log(`Already upgraded ${c}`)
            continue
        }
        if (c === 'PlonkVerifier') {
            console.log('Update PlonkVerifier with specific script')
            continue
        }
        if (c === 'AaveCreditVault') {
            console.log('AaveCreditVault not deployed')
            continue
        }
        const afact = readArtifact(c)
        if (!afact.address) {
            console.log(`contract ${c} didn't exist`)
            continue
        }
        const libraries = {}
        const C = await (await ethers.getContractFactory(c, { libraries })).connect(ethers.provider.getSigner(roles.deployer))
        if (verbose) {
            console.log(`upgrading ${c} at ${afact.address}`)
        }
        try {
            const contract = await upgrades.upgradeProxy(afact.address, C)
            await contract.deployed()
            taskBook[c] = await writeArtifact(c, contract, afact.libraries)
            success[c] = true
            if (!strict) {
                fs.writeFileSync('upgrade-cache.json', JSON.stringify(success, undefined, 2))
            }
        } catch (e) {
            console.log('Cannot upgrade', e)
            if (fail) {
                process.exit(-1)
            }
            const address = await upgrades.prepareUpgrade(afact.address, C, { unsafeAllowLinkedLibraries: true })
            taskBook[c] = await updateArtifact(c, afact.address, address, afact.libraries)
            const prevAddress = await upgrades.erc1967.getImplementationAddress(afact.address)
            if (address === prevAddress) {
                console.log('Nothing to upgrade')
            } else {
                console.log('Multisig upgrade', address, prevAddress)
                const adminAddress = await upgrades.erc1967.getAdminAddress(afact.address)
                const adminABI = [
                    {
                        inputs: [
                            {
                                name: 'proxy',
                                type: 'address'
                            },
                            {
                                name: 'implementation',
                                type: 'address'
                            }
                        ],
                        name: 'upgrade',
                        stateMutability: 'nonpayable',
                        type: 'function'
                    }
                ]
                const admin = new ethers.Contract(adminAddress, adminABI)
                const tx = await admin.populateTransaction.upgrade(afact.address, address)
                transactions.push(tx)

                try {
                    const ethAdapterOwner1 = new EthersAdapter({ ethers, signer: ethers.provider.getSigner(0), contractNetworks })
                    const ethAdapterOwner2 = new EthersAdapter({ ethers, signer: ethers.provider.getSigner(1), contractNetworks })
                    const safeSdk1 = await Safe.default.create({ ethAdapter: ethAdapterOwner1, safeAddress: roles.upgraderWallet, contractNetworks })
                    const safeTx = await safeSdk1.createTransaction({ ...tx, value: 0 })
                    const txHash = await safeSdk1.getTransactionHash(safeTx)
                    const res1 = await safeSdk1.approveTransactionHash(txHash)
                    await res1.transactionResponse?.wait()
                    const safeSdk2 = await Safe.default.create({ ethAdapter: ethAdapterOwner2, safeAddress: roles.upgraderWallet, contractNetworks })
                    const res2 = await safeSdk2.executeTransaction(safeTx)
                    await res2.transactionResponse?.wait()
                    console.log('Succesfully executed multisig tx')
                } catch (err) {
                    console.log('Multisig tx to execute for signers')
                    console.log(tx)
                }
            }
        }
    }
    fs.writeFileSync('transactions.json', JSON.stringify(transactions, null, 2))
    return taskBook
}

module.exports = { upgradeContracts }
