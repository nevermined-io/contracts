const { hardhatArguments, upgrades, ethers, web3 } = require('hardhat')
const glob = require('glob')
const fs = require('fs')

const web3Utils = require('web3-utils')

const network = hardhatArguments.network || 'hardhat'
const { version } = JSON.parse(fs.readFileSync('./package.json'))

function createFunctionSignature({
    functionName,
    parameters
} = {}) {
    const signature = `${functionName}(${parameters.join(',')})`

    const signatureHash = web3Utils.sha3(signature)
    return signatureHash.substring(0, 10)
}

function generateFunctionSignaturesInABI(
    abi
) {
    abi
        .filter((abiEntry) => abiEntry.type === 'function')
        .forEach((abiEntry) => {
            const parameters = abiEntry.inputs.map((i) => i.type)
            abiEntry.signature = createFunctionSignature({
                functionName: abiEntry.name,
                parameters
            })
        })

    return abi
}

function createArtifact(
    name,
    contract,
    proxyAddress,
    implementationAddress,
    version,
    libraries
) {
    const _impAddress = implementationAddress instanceof Object ? implementationAddress.address : implementationAddress
    const _proxyAddress = proxyAddress instanceof Object ? proxyAddress.address : proxyAddress
    return {
        name,
        abi: generateFunctionSignaturesInABI(contract.abi),
        bytecode: contract.bytecode,
        address: _proxyAddress,
        implementation: _impAddress,
        version,
        libraries
    }
}

async function exportArtifacts(contracts, addressBook, libraries) {
    const files = glob.sync('./build/**/*.json').filter(a => !a.match('.dbg.')).filter(a => contracts.some(b => a.match(b + '.json')))
    for (const c of contracts) {
        if (!addressBook[c]) {
            console.warn(`Not deployed: ${c}`)
            continue
        }
        const implAddress = await upgrades.erc1967.getImplementationAddress(addressBook[c])
        const file = files.find(a => a.match(c))
        const contract = JSON.parse(fs.readFileSync(file))
        const artifact = createArtifact(c, contract, addressBook[c], implAddress, `v${version}`, libraries[c] || {})

        fs.writeFileSync(`artifacts/${c}.${network}.json`, JSON.stringify(artifact, null, 2))
    }
    fs.writeFileSync('artifacts/ready', '')
}

async function exportLibraryArtifacts(contracts, addressBook) {
    const files = glob.sync('./build/**/*.json').filter(a => !a.match('.dbg.')).filter(a => contracts.some(b => a.match(b + '.json')))
    for (const c of contracts) {
        const file = files.find(a => a.match(c))
        const contract = JSON.parse(fs.readFileSync(file))
        const artifact = createArtifact(c, contract, addressBook[c], addressBook[c], `v${version}`, {})
        fs.writeFileSync(`artifacts/${c}.${network}.json`, JSON.stringify(artifact, null, 2))
    }
    fs.writeFileSync('artifacts/ready', '')
}

async function exportLibraryArtifact(c, address) {
    const files = glob.sync('./build/**/*.json').filter(a => !a.match('.dbg.')).filter(a => a.match(c + '.json'))
    const file = files.find(a => a.match(c))
    const contract = JSON.parse(fs.readFileSync(file))
    const artifact = createArtifact(c, contract, address, address, `v${version}`, {})
    fs.writeFileSync(`artifacts/${c}.${network}.json`, JSON.stringify(artifact, null, 2))
    fs.writeFileSync('artifacts/ready', '')
}

function readArtifact(c) {
    try {
        return JSON.parse(fs.readFileSync(`artifacts/${c}.${network}.json`))
    } catch (err) {
        console.log(`Warning: cannot read ${c}`)
        return {}
    }
}

async function writeArtifact(c, contract, libraries) {
    const files = glob.sync('./build/**/*.json').filter(a => !a.match('.dbg.')).filter(a => a.match(c + '.json'))
    const file = files.find(a => a.match(c))
    const data = JSON.parse(fs.readFileSync(file))
    const implAddress = await upgrades.erc1967.getImplementationAddress(contract.address)
    const artifact = createArtifact(c, data, contract.address, implAddress, `v${version}`, libraries || {})
    fs.writeFileSync(`artifacts/${c}.${network}.json`, JSON.stringify(artifact, null, 2))
    return artifact
}

async function updateArtifact(c, contractAddress, implAddress, libraries) {
    const files = glob.sync('./build/**/*.json').filter(a => !a.match('.dbg.')).filter(a => a.match(c + '.json'))
    const file = files.find(a => a.match(c))
    const data = JSON.parse(fs.readFileSync(file))
    const artifact = createArtifact(c, data, contractAddress, implAddress, `v${version}`, libraries || {})
    fs.writeFileSync(`artifacts/${c}.${network}.json`, JSON.stringify(artifact, null, 2))
    return artifact
}

async function deployLibrary(name, addresses, signer) {
    if (addresses[name]) {
        console.log(`Contract ${name} found from cache`)
        return addresses[name]
    } else {
        const factory = await ethers.getContractFactory(name, signer)
        const library = await factory.deploy()
        const h1 = library.deployTransaction.hash
        await library.deployed()
        const address = (await web3.eth.getTransactionReceipt(h1)).contractAddress
        console.log(`Library ${name} deployed into address ${address}`)
        addresses[name] = address
        return address
    }
}

// returns either the address from the address book or the address of the manual set proxies
function resolveAddress(contractName, addressBook, proxies = undefined) {
    let address = addressBook[contractName] || proxies[contractName]
    if (address instanceof Object) { address = address.address }
    console.log(`resolveAddress :: ${contractName} = ${address}`)
    return address
}

module.exports = {
    updateArtifact,
    writeArtifact,
    readArtifact,
    exportLibraryArtifacts,
    exportLibraryArtifact,
    exportArtifacts,
    deployLibrary,
    resolveAddress
}
