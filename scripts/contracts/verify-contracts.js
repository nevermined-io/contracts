const { mkdtempSync } = require('fs')
const { execSync } = require('child_process') // eslint-disable-line
const path = require('path')
const fs = require('fs')
const defaultToVerify = require('../deploy/contracts-verify.json')

// Map of network names which are different in hardhat
const networksMap = {}
networksMap['arbitrum-one'] = 'arbitrum-one'
networksMap['gnosis'] = 'gnosis'

/**
* This script verify all the contracts source code for a given version, network & tag name
* It requires the following parameters:
* - Smart Contracts version. Example: v2.1.0
* - Network name. Example: mainnet, goerli, etc
* - Tag Name. Nevermined Smart Contracts can be deployed multiple times under different tag names. Example: public or common
* Optional parameters:
* - Temporary Path. Example: /tmp/nvm_contracts_verification_1234
* - Contract name to verify. Example: NeverminedToken or all
*/

function parseArguments() {
    const args = process.argv.slice(2)
    if (args.length < 3) {
        printHelp()
        process.exit(1)
    }
    return args
}

function createEphemeralFolder(version) {
    const tempDir = mkdtempSync('/tmp/nvm_contracts_verification_')
    const cloneCommand = `git clone git@github.com:nevermined-io/contracts.git --depth 1 -b ${version} ${tempDir}`
    console.log(cloneCommand)
    execSync(cloneCommand)
    execSync('yarn', { cwd: tempDir })
    execSync('yarn compile', { cwd: tempDir })
    execSync('yarn add @nomiclabs/hardhat-etherscan', { cwd: tempDir })

    return tempDir
}

function deleteEphemeralFolder(tempDir) {
    execSync(`rm -rf ${tempDir}`)
}

function downloadArtifacts(scriptsDir, version, network, tag, options) {
    var artifactsDir = mkdtempSync('/tmp/nvm_contracts_artifacts_')
    execSync(`mkdir -p ${artifactsDir}/scripts/`)
    const cpScriptCmd = `cp -f ${scriptsDir}/download_artifacts.sh ${artifactsDir}/scripts/`
    execSync(cpScriptCmd)
    execSync(`./scripts/download_artifacts.sh ${version} ${network} ${tag}`, { cwd: `${artifactsDir}` })
    artifactsDir = artifactsDir + '/artifacts'
    console.log(`Artifacts downloaded to ${artifactsDir}`)
    return artifactsDir
}

function processContracts(tempDir, artifactsDir, network, contractsToVerify) {
    var verified = []
    var notVerified = []

    const artifactFiles = fs.readdirSync(artifactsDir)
    artifactFiles.filter(file => file.indexOf('.json') > -1)
        .filter(file =>
            (contractsToVerify !== 'all' && file.includes(`${contractsToVerify}.${network}.json`)) ||
        (contractsToVerify === 'all' && defaultToVerify.indexOf(file.split('.')[0]) >= 0)
        )
        .forEach(abiFile => {
            const abiData = fs.readFileSync(`${artifactsDir}/${abiFile}`, 'UTF-8')
            const abi = JSON.parse(abiData)

            const findContractName = `find contracts/ -name ${abi.name}.sol`
            const output = execSync(findContractName, { cwd: `${tempDir}` })
            const contractName = output.toString().trim()
            if (contractName.length === 0) {
                console.log(`ABI ${abi.name} not found, skipping`)
                notVerified.push(abi.name)
            } else {
                const contractEntity = `${contractName}:${abi.name}`
                console.log(`Contract Entity ${contractEntity}`)
                try {
                    console.log(`Verifying Implementation address: ${abi.implementation}`)
                    verifyContract(abi.implementation, network, tempDir, contractEntity)

                    console.log(`Verifying Proxy address: ${abi.address}`)
                    verifyContract(abi.address, network, tempDir, contractEntity)
                    verified.push(abi.name)
                } catch (error) {
                    console.log(`Unable to verify contract: ${abi.name}`)
                    notVerified.push(abi.name)
                }
            }
        })
    console.log(`Verified contracts ${verified}`)
    console.log(`NOT Verified contracts ${notVerified}`)
}

function verifyContract(contractAddress, network, tempDir, contractEntity) {
    const networkName = networksMap[network] || network

    console.log(`Using Verification Network Name: ${networkName}`)

    const verifyCommand = `npx hardhat verify --network ${networkName} ${contractAddress} --contract ${contractEntity}`
    console.log(`Executing verification command: ${verifyCommand}`)
    execSync(verifyCommand, { cwd: `${tempDir}` })
}

function printHelp() {
    console.log('\nThis script verify all the contracts source code.')
    console.log('The parameters required are:')
    console.log(' - Smart Contracts version. Example: v2.1.0')
    console.log(' - Network name. Example: mainnet, goerli, etc')
    console.log(' - Tag Name. Example: common, public, etc')
    console.log(`\nExample: ${process.argv[1]} v2.1.0 goerli public\n\n`)
}

/// //////////////////////////////
/// //////// MAIN ////////////////
/// //////////////////////////////

const scriptsDir = path.dirname(path.dirname(process.argv[1]))

const args = parseArguments()

var tempDir
const version = args[0]
const network = args[1]
const tag = args[2]

let contractsToVerify = 'all'
if (args.length > 3) {
    contractsToVerify = args[3]
}

if (args.length > 4) { tempDir = args[4] } else { tempDir = createEphemeralFolder(version) }

console.log(`\nVerifying contracts (${contractsToVerify}) of version ${version} deployed on network ${network} using the tag ${tag}\n`)
console.log(`Using contracts folder ${tempDir}`)

const artifactsDir = downloadArtifacts(scriptsDir, version, network, tag)

processContracts(tempDir, artifactsDir, network, contractsToVerify)

if (args.length > 5 && args[5] === 'delete') { deleteEphemeralFolder(tempDir) }
