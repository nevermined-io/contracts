/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@openzeppelin/hardhat-upgrades')
require('@nomiclabs/hardhat-truffle5')
require('hardhat-dependency-compiler')
require('hardhat-gas-reporter')
require('solidity-coverage')

const utils = require('web3-utils')

const MNEMONIC = process.env.MNEMONIC || 'taxi music thumb unique chat sand crew more leg another off lamp'
const url = process.env.KEEPER_RPC_URL

const accounts = {
    mnemonic: MNEMONIC
}

const disableDependencies = process.env.DISABLE_DEPENDENCIES === 'true'

module.exports = {
    solidity: {
        compilers: [
            {
                version: '0.8.9',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 10
                    }
                }
            }
        ]
    },
    paths: {
        artifacts: 'build'
    },
    dependencyCompiler: disableDependencies ? undefined : {
        paths: [
            '@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol',
            '@gnosis.pm/safe-contracts/contracts/libraries/MultiSend.sol',
            '@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol'
        ]
    },
    networks: {
        hardhat: {
            allowUnlimitedContractSize: true,
            initialBaseFeePerGas: 0
        },
        spree: {
            url: url || 'http://localhost:8545',
            accounts: {
                mnemonic: 'taxi music thumb unique chat sand crew more leg another off lamp'
            }
        },
        external: {
            url: 'http://localhost:18545',
            timeout: 200000
        },
        development: {
            url: 'http://localhost:18545',
            timeout: 200000
        },
        'polygon-localnet': {
            url: url || 'http://localhost:8545',
            accounts,
            chainId: 8997,
            skipDryRun: true,
            gas: 8000000,
            gasPrice: 0,
            from: '0xe2DD09d719Da89e5a3D0F2549c7E24566e947260'
        },
        'geth-localnet': {
            url: url || 'http://localhost:8545',
            accounts,
            chainId: 1337,
            skipDryRun: true,
            //            gas: 4000000,
            //            gasPrice: 0,
            from: '0xe2DD09d719Da89e5a3D0F2549c7E24566e947260'
        },
        'geth-setup': {
            url: url || 'http://localhost:8545',
            chainId: 1337
        },
        'aurora-localnet': {
            url: url || 'http://localhost:8545',
            accounts,
            chainId: 0x4E454154, // 1313161556
            gas: 1000 * 1000000,
            gasPrice: 0,
            skipDryRun: true,
            from: '0x90bb8d2F28D67881eBD85Ef5a10FAADd55FB4b60'
        },
        'aurora-testnet': {
            url: url || 'https://testnet.aurora.dev',
            accounts,
            chainId: 0x4E454153, // 1313161555
            gas: 1000 * 1000000,
            gasPrice: 0,
            from: '0x90bb8d2F28D67881eBD85Ef5a10FAADd55FB4b60'
        },
        // aurora mainnet!
        aurora: {
            url: url || 'https://mainnet.aurora.dev',
            accounts,
            chainId: 0x4E454152, // 1313161554
            gas: 6 * 1000000,
            gasPrice: 0,
            skipDryRun: true,
            confirmations: 10,
            timeoutBlocks: 200,
            deploymentPollingInterval: 8000,
            from: '0xB6d47415AfCDD06c5155d0E191530027FD51CCfD'
        },
        // integration the ocean testnet
        integration: {
            url: url || 'https://integration.keyko.com',
            accounts,
            chainId: 0x897, // 2199
            gas: 6000000,
            gasPrice: 10000,
            from: '0x90eE7A30339D05E07d9c6e65747132933ff6e624'
        },
        // staging the ocean beta network
        staging: {
            url: url || 'https://staging.keyko.com',
            accounts,
            chainId: 0x2323, // 8995
            gas: 6000000,
            gasPrice: 10000,
            from: '0x90eE7A30339D05E07d9c6e65747132933ff6e624'
        },
        // kovan the ethereum testnet
        kovan: {
            url: url || `https://kovan.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 0x2A, // 42
            from: '0x2c0D5F47374b130EE398F4C34DBE8168824A8616'
        },
        // rinkeby the ethereum testnet
        rinkeby: {
            url: url || `https://rinkeby.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 0x4, // 4
            gas: 20 * 1000000,
            gasPrice: parseInt(utils.toWei('5', 'gwei')),
            skipDryRun: true,
            from: '0x73943d14131268F23b721E668911bCDDEcA9da62'
        },
        // alfajores the celo testnet
        'celo-alfajores': {
            url: url || 'https://alfajores-forno.celo-testnet.org',
            accounts,
            chainId: 44787,
            from: '0x4747eAb1698a5c72DC3fD07A3074B2E1795D7294'
        },
        // baklava the celo testnet
        'celo-baklava': {
            url: url || 'https://baklava-forno.celo-testnet.org',
            accounts,
            chainId: 62320
        },
        // celo mainnet
        celo: {
            url: url || 'https://forno.celo.org',
            accounts,
            chainId: 42220,
            from: '0xBb0EB77DC8967D61d82B059C7bDB9974425494C1'
        },
        // Polygon Networks: https://docs.matic.network/docs/develop/network-details/network/
        // Polygon: mumbai testnet
        mumbai: {
            url: url || 'https://matic-mumbai.chainstacklabs.com',
            accounts,
            chainId: 80001,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true,
            from: '0x73943d14131268F23b721E668911bCDDEcA9da62'
        },
        // Polygon: matic mainnet
        matic: {
            url: url || 'https://matic-mainnet.chainstacklabs.com',
            accounts,
            chainId: 137,
            confirmations: 2,
            timeoutBlocks: 200,
            skipDryRun: true,
            from: '0xCF3D200356Fe8e5E2fa9f6fd59B01D41732BCf4c',
            gas: 'auto',
            gasPrice: 'auto',
            gasMultiplier: 3
        },
        // mainnet the ethereum mainnet
        mainnet: {
            url: url || `https://mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 0x1, // 1
            from: '0x721ba7Dc4357D846778Bad4227D46f2cefBa7De7',
            gas: 10 * 1000000,
            gasPrice: parseInt(utils.toWei('45', 'gwei'))
        },
        // production mainnet
        production: {
            url: url || 'https://mainnet.nevermined.io',
            accounts,
            chainId: 0xCEA11, // 846353
            from: '0xba3e0ec852dc24ca7f454ea545d40b1462501711',
            gas: 6 * 1000000,
            gasPrice: parseInt(utils.toWei('10', 'mwei'))
        }
    }
}
