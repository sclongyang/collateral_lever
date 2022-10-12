const { network, ethers } = require("hardhat")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const waitBlockConfirmations = developmentChains.includes(network.name) ? 1 : VERIFICATION_BLOCK_CONFIRMATIONS

    cTokens = []
    arguments = []
    if(developmentChains.includes(network.name)){
        //fork mainnet
        cTokens = [process.env.MAINNET_COMPOUND_CDAI_ADDRESS,process.env.MAINNET_COMPOUND_CBAT_ADDRESS,process.env.MAINNET_COMPOUND_CUSDC_ADDRESS]
        arguments = [process.env.MAINNET_UNISWAP_V2_ROUTER02_ADDRESS,process.env.MAINNET_UNISWAP_V2_FACTORY_ADDRESS,process.env.MAINNET_COMPTROLLER_ADDRESS,cTokens]     
    }else{
        //goerli
        cTokens = [process.env.GOERLI_COMPOUND_CDAI_ADDRESS,process.env.GOERLI_COMPOUND_CETH_ADDRESS,process.env.GOERLI_COMPOUND_CUSDC_ADDRESS]
        arguments = [process.env.GOERLI_UNISWAP_V2_ROUTER02_ADDRESS,process.env.GOERLI_UNISWAP_V2_FACTORY_ADDRESS,process.env.GOERLI_COMPTROLLER_ADDRESS,cTokens]    
    }
    
    console.log("begin deploy")
    const collateralLever = await deploy("CollateralLever",
        {
            from: deployer,
            args: arguments,
            log: true,
            waitConfirmations: waitBlockConfirmations,
            gasLimit:30000000,
        }
    )
    console.log(`fermi deploy CollateralLever address: ${collateralLever.address}`)
    
    if(!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY){
        await verify(collateralLever.address, arguments)        
    }
    console.log("------------------------------")    
}

module.exports.tags = ["all", "collaterallever"]