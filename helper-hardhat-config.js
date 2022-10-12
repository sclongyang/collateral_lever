const networkConfig = {
    default:{
        name:"hardhat",        
    },
    31337:{
        name:"localhost",
    },
    5:{
        name:"goerli",
    },
    1:{
        name:"mainnet",
    },
}

const developmentChains = ["hardhat", "localhost"]
const VERIFICATION_BLOCK_CONFIRMATIONS = 6
const frontEndContractsAddressFile = "../frontend_collateral_lever/constants/networkMapping.json"
const frontEndABIDir = "../frontend_collateral_lever/constants/"

module.exports = {
    networkConfig,
    developmentChains,
    VERIFICATION_BLOCK_CONFIRMATIONS,
    frontEndContractsAddressFile,
    frontEndABIDir
}