const { ethers, network } = require("hardhat")
const { moveBlock } = require("../utils/move_block")
const ctokenAbi = require("../constants/ctoken_abi.json")
const erc20Abi = require("../constants/erc20_abi.json")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")

async function exec() {
    const signers = await ethers.getSigners()
    const deployer = signers[0]
    const user = signers[1]

    const collateralLeverOnDeployer = await ethers.getContract("CollateralLever", deployer)

    console.log(`3333 contract: ${collateralLeverOnDeployer.address}`)
    console.log(`deployer addr: ${deployer.address}, user addr:${user.address}`)

    const collateralLeverOnUser = await collateralLeverOnDeployer.connect(user)

    const postionInfo2 = await collateralLeverOnDeployer.s_userAddress2PositionInfos(user.address, 2)
    console.log(`position :${postionInfo2}`)      

    if (network.config.chainId == 31337) {
        console.log(`7777`)
        await moveBlock(2, 1000)
    }
}


const getUnderlyingByCTokenAddress = async (ctokenAddress) => {
    const ctoken = await ethers.getContractAt(ctokenAbi, ctokenAddress)
    return await ctoken.underlying()
}

const approveERC20 = async (tokenAddress, from, to, amount) => {
    const DAIWithUser = await ERC20TokenWithSigner(tokenAddress, from)
    await DAIWithUser.approve(to, amount)
}

const ERC20TokenWithSigner = async (tokenAddress, signerAccount) => {
    return await ethers.getContractAt(erc20Abi, tokenAddress, signerAccount)
}

const getERC20Balance = async (tokenAddress, userAddress) => {
    const token = await ethers.getContractAt(erc20Abi, tokenAddress)
    return await token.balanceOf(userAddress);
}

exec().then((resolve) => process.exit(0)).catch((e) => {
    console.log(e)
})