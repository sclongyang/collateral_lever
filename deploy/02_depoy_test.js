const { network, ethers } = require("hardhat")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")
const abi = require("../constants/abi.json")

module.exports = async ({ getNamedAccounts, deployments }) => {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const waitBlockConfirmations = developmentChains.includes(network.name) ? 1 : VERIFICATION_BLOCK_CONFIRMATIONS

    arguments = []
       
    console.log("begin deploy")
    const contract = await deploy("MyTest",
        {
            from: deployer,
            args: arguments,
            log: true,
            waitConfirmations: waitBlockConfirmations,
            // gasLimit:30000000,
        }
    )
    console.log(`fermi deploy MyTest address: ${contract.address}`)
    
    if(!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY){
        await verify(contract.address, arguments)        
    }   
    console.log("------------------------------")    

    // const signers = await ethers.getSigners()
    //         deployer = signers[0]
    mainnetCTokenDAI = process.env.MAINNET_COMPOUND_CBAT_ADDRESS
    myTestContract = await ethers.getContract("MyTest", deployer)
    console.log(`getUnderlying: ${await myTestContract.getUnderlying(mainnetCTokenDAI)}`)
    console.log(`blocknum:${await ethers.provider.getBlockNumber()}`) 
    
    ctoken = await ethers.getContractAt(abi, mainnetCTokenDAI,deployer)
    console.log(`ctoken->token: ${await ctoken.underlying()}`)
}

module.exports.tags = ["all", "tt"]