/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@openzeppelin/hardhat-upgrades')
require('@nomiclabs/hardhat-truffle5')
require('@nomiclabs/hardhat-etherscan')
require('hardhat-dependency-compiler')
require('hardhat-gas-reporter')
require('solidity-coverage')
require('solidity-docgen')
require('hardhat-ignore-warnings')
require('hardhat-contract-sizer')

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
                version: '0.8.17',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 10
                    }
                }
            }
        ]
    },
    warnings: {
        '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol': {
            unreachable: 'off'
        }
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
    gasReporter: {
        enabled: !!(process.env.REPORT_GAS),
        showTimeSpent: true,
        currency: 'EUR'
    },
    docgen: {
        outputDir: 'docs/generated/'
        // Following lines are commented until solidity-docgen v0.6 provides a proper templates support
        //        pages: 'files',
        //        templates: 'docs/docgen_template/'
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
        local: {
            url: 'http://localhost:8545',
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
        goerli: {
            url: url || `https://goerli.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 0x5, // 5
            skipDryRun: true,
            from: '0x73943d14131268F23b721E668911bCDDEcA9da62'
        },
        'arbitrum-goerli': {
            url: url || `https://arbitrum-goerli.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 421613,
            skipDryRun: true,
            from: '0x73943d14131268F23b721E668911bCDDEcA9da62'
        },
        'arbitrum-one': {
            url: url || `https://arbitrum-mainnet.infura.io/v3/${process.env.INFURA_TOKEN}`,
            accounts,
            chainId: 42161,
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
            url: url || `https://polygon-mumbai.infura.io/v3/${process.env.INFURA_TOKEN}`,
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
        }
    },
    etherscan: {
        apiKey: {
            goerli: process.env.ETHERSCAN_TOKEN,
            mainnet: process.env.ETHERSCAN_TOKEN,
            polygonMumbai: process.env.POLYGONSCAN_TOKEN,
            polygon: process.env.POLYGONSCAN_TOKEN,
            arbitrumTestnet: process.env.ARBISCAN_TOKEN,
            arbitrumOne: process.env.ARBISCAN_TOKEN
        },
        customChains: [{
            network: 'arbitrum-goerli',
            chainId: 421613,
            urls: {
                apiURL: 'https://api-testnet.arbiscan.io/api',
                browserURL: 'https://testnet.arbiscan.io'
            }
        }]
    }
}
