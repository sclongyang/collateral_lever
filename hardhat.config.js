require("@nomiclabs/hardhat-waffle")
require("@nomiclabs/hardhat-etherscan")
require("hardhat-deploy")
require("solidity-coverage")
require("hardhat-gas-reporter")
require("hardhat-contract-sizer")
require("dotenv").config()

const MAINNET_RPC_URL = process.env.ALCHEMY_MAINNET_RPC_URL
const GOERLI_RPC_URL = process.env.GOERLI_RPC_URL
const PRIVATE_KEY = process.env.GOERLI_PRIVATE_KEY_1
const PRIVATE_KEY_USER = process.env.GOERLI_PRIVATE_KEY_2
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY
const REPORT_GAS = process.env.REPORT_GAS || false

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {            
            forking: {
              url: MAINNET_RPC_URL,
              blockNumber: 15733251,
            },
            // chainId: 31337,
        },
        localhost: {
            chainId: 31337,
        },
        goerli: {
            url: GOERLI_RPC_URL,
            accounts: [PRIVATE_KEY,PRIVATE_KEY_USER],
            saveDeployments: true,
            chainId: 5,    
            // allowUnlimitedContractSize: true,
        },
        mainnet: {
            url: MAINNET_RPC_URL,
            accounts: [PRIVATE_KEY,PRIVATE_KEY_USER],
            saveDeployments: true,
            chainId: 1,
        },        
    },
    etherscan: {        
        apiKey: {
            goerli: ETHERSCAN_API_KEY,            
        },
    },
    gasReporter: {
        enabled: REPORT_GAS,
        currency: "USD",
        outputFile: "gas-report.txt",
        noColors: true,        
    },
    contractSizer: {
        runOnCompile: false,
        only: [""],
    },
    namedAccounts: {
        deployer: {
            default: 0, 
            1: 0, 
            31337:0,
        },
        user: {
            default: 1,
            1: 1, 
            31337:1,
        },
    },
    solidity: {
        compilers: [
            {
                version: "0.8.7",
            },
            {
                version: "0.5.0",
            },
        ],
    },
    mocha: {
        timeout: 200000, // 200s
    },
}