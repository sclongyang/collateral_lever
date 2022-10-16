const { network, ethers } = require("hardhat")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")
const ctokenAbi = require("../constants/ctoken_abi.json")
const erc20Abi = require("../constants/erc20_abi.json")

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer, user } = await getNamedAccounts()
    // const waitBlockConfirmations = developmentChains.includes(network.name) ? 1 : VERIFICATION_BLOCK_CONFIRMATIONS
    const waitBlockConfirmations = 1

    let cTokens = []
    let arguments = []
    const isLocal = developmentChains.includes(network.name)
    if (isLocal) {
        //fork mainnet        
        arguments = [process.env.MAINNET_UNISWAP_V2_ROUTER02_ADDRESS, process.env.MAINNET_UNISWAP_V2_FACTORY_ADDRESS, process.env.MAINNET_COMPTROLLER_ADDRESS]
        cTokens = [process.env.MAINNET_COMPOUND_CDAI_ADDRESS, process.env.MAINNET_COMPOUND_CUNI_ADDRESS, process.env.MAINNET_COMPOUND_CUSDC_ADDRES]
    } else {
        //goerli        
        arguments = [process.env.GOERLI_UNISWAP_V2_ROUTER02_ADDRESS, process.env.GOERLI_UNISWAP_V2_FACTORY_ADDRESS, process.env.GOERLI_COMPTROLLER_ADDRESS]
        cTokens = [process.env.GOERLI_COMPOUND_CDAI_ADDRESS, process.env.GOERLI_COMPOUND_CUNI_ADDRESS, process.env.GOERLI_COMPOUND_CUSDC_ADDRESS]
    }

    console.log("begin deploy CollateralLever")
    const collateralLever = await deploy("CollateralLever",
        {
            from: deployer,
            args: arguments,
            log: true,
            waitConfirmations: waitBlockConfirmations,
            gasLimit: 4229450,
        }
    )
    console.log(`fermi deploy CollateralLever address: ${collateralLever.address}`)

    if (!isLocal && process.env.ETHERSCAN_API_KEY) {
        await verify(collateralLever.address, arguments)
    }
    //add cTokens
    collateralContract = await ethers.getContract("CollateralLever", deployer)
    console.log(`blocknum:${await ethers.provider.getBlockNumber()}`)
    console.log(`addSupportedCToken 3 cTokens for init`)
    cTokens.forEach(async element => {
        await collateralContract.addSupportedCToken(element)
    });


    console.log("------------------------------")
}

const getUnderlyingByCTokenAddress = async (ctokenAddress) => {
    const ctoken = await ethers.getContractAt(ctokenAbi, ctokenAddress)
    return await ctoken.underlying()
}

module.exports.tags = ["all", "collaterallever"]