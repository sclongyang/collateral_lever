const { ethers, network } = require("hardhat")
const { moveBlock } = require("../utils/move_block")
const ctokenAbi = require("../constants/ctoken_abi.json")
const erc20Abi = require("../constants/erc20_abi.json")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")

async function exec() {
    let cDAIAddress = process.env.GOERLI_COMPOUND_CDAI_ADDRESS
    let cXXXAddress = process.env.GOERLI_COMPOUND_CCOMP_ADDRESS
    let comptrollerAddress = process.env.GOERLI_COMPTROLLER_ADDRESS

    console.log(`network.config.chainId:${network.config.chainId}`)
    if (network.config.chainId == 31337) {
        cDAIAddress = process.env.MAINNET_COMPOUND_CDAI_ADDRESS
        cXXXAddress = process.env.MAINNET_COMPOUND_CCOMP_ADDRESS
        comptrollerAddress = process.env.MAINNET_COMPTROLLER_ADDRESS

    }

    const DAIAddress = await getUnderlyingByCTokenAddress(cDAIAddress)
    const XXXAddress = await getUnderlyingByCTokenAddress(cXXXAddress)

    const signers = await ethers.getSigners()
    const deployer = signers[0]
    const user = signers[1]

    const tokenBase = DAIAddress
    const tokenQuote = XXXAddress
    const underlyingDecimalsOfDAI = 18
    const underlyingAsCollateral = 0.031 //DAI         
    const investmentAmount = (underlyingAsCollateral * Math.pow(10, underlyingDecimalsOfDAI)).toString();
    const investmentIsQuote = false
    const lever = 2
    const isShort = false

    const collateralLeverOnDeployer = await ethers.getContract("CollateralLever", deployer)

    console.log(`3333 contract: ${collateralLeverOnDeployer.address}`)
    console.log(`deployer addr: ${deployer.address}, user addr:${user.address}`)

    const collateralLeverOnUser = await collateralLeverOnDeployer.connect(user)

    const isLocal = developmentChains.includes(network.name)
    if (isLocal) {
        console.log(`is local:${network.name}`)
        const investmentAmount2 = (100 * Math.pow(10, 18)).toString();
        //transfer DAI to user
        const DAIAddress = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)
        const addressWithDAI = "0x604981db0C06Ea1b37495265EDa4619c8Eb95A3D"
        await network.provider.send("hardhat_impersonateAccount", [addressWithDAI])
        const impersonatedSigner = await ethers.getSigner(addressWithDAI)
        // const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"            
        const tokenConnectedByImpersonatedSigner = await ethers.getContractAt(erc20Abi, DAIAddress, impersonatedSigner)
        await tokenConnectedByImpersonatedSigner.transfer(user.address, investmentAmount2)
    }
    else {
        comptrollerAddress = process.env.GOERLI_UNITROLLER_ADDRESS //大坑:goerli要使用unitroller,而非comptroller
    }

    await closePostion(DAIAddress, XXXAddress, user, collateralLeverOnDeployer, collateralLeverOnUser, 3)

    if (network.config.chainId == 31337) {
        console.log(`7777`)
        await moveBlock(2, 1000)
    }
}

const closePostion = async (DAIAddress, XXXAddress, user, collateralLeverOnDeployer, collateralLeverOnUser, positionId) => {
    console.log(`before:DAI user balance:${await getERC20Balance(DAIAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
    console.log(`before:XXX user balance:${await getERC20Balance(XXXAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(XXXAddress, collateralLeverOnUser.address)}`)

    const postionInfo = await collateralLeverOnDeployer.s_userAddress2PositionInfos(user.address, positionId)
    if (postionInfo.positionId != 0) {
        console.log(`positionInfo:${postionInfo}`)

        const tx = await collateralLeverOnUser.closePosition(positionId, { gasLimit: 9000000 })
        console.log(`exec...`)
        const txReceipt = await tx.wait(1)
        console.log(`after:DAI user balance:${await getERC20Balance(DAIAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
        console.log(`after:XXX user balance:${await getERC20Balance(XXXAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(XXXAddress, collateralLeverOnUser.address)}`)

        const postionInfo2 = await collateralLeverOnDeployer.s_userAddress2PositionInfos(user.address, positionId)
        console.log(`after closePosition postionInfo should be null:${postionInfo2}`)
    }
    else {
        console.log(`error! user dont have positionId:${positionId}`)
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