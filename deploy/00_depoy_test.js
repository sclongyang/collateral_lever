const { network, ethers } = require("hardhat")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")
const abi = require("../constants/ctoken_abi.json")

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    // const { deployer ,user} = await getNamedAccounts()
    const signers = await ethers.getSigners()
    const deployer = signers[0]
    const user = signers[1]


    const waitBlockConfirmations = developmentChains.includes(network.name) ? 1 : VERIFICATION_BLOCK_CONFIRMATIONS

    arguments = []
    console.log(`deployer:${deployer.address}`)
    console.log("begin deploy MyTest")
    const contract = await deploy("MyTest",
        {
            from: deployer.address,
            args: arguments,
            log: true,
            waitConfirmations: waitBlockConfirmations,
            // gasLimit:4000000,
        }
    )
    console.log(`fermi deploy MyTest address: ${contract.address}`)

    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(contract.address, arguments)
    }
    console.log("------------------------------")

    // mainnetCTokenDAI = process.env.MAINNET_COMPOUND_CBAT_ADDRESS
    // myTestContract = await ethers.getContract("MyTest", deployer)
    // console.log(`getUnderlying: ${await myTestContract.getUnderlying(mainnetCTokenDAI)}`)

    // ctoken = await ethers.getContractAt(abi, mainnetCTokenDAI,deployer)
    // console.log(`ctoken->token: ${await ctoken.underlying()}`)

    // collateralContract = await ethers.getContract("CollateralLever", deployer)
    // await collateralContract.openPosition("0x6B175474E89094C44Da98b954EedeAC495271d0F","0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",1,false,3,false)
    // console.log(`Position:${await collateralContract.s_userAddress2PositionInfos(deployer,0)}`) 


}

module.exports.tags = ["all", "tt"]