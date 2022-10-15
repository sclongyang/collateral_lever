const { ethers, network } = require("hardhat")
const { moveBlock } = require("../utils/move_block")
const ctokenAbi = require("../constants/ctoken_abi.json")
const erc20Abi = require("../constants/erc20_abi.json")

async function openPosition() {
    let cDAIAddress = process.env.GOERLI_COMPOUND_CDAI_ADDRESS
    let cXXXAddress = process.env.GOERLI_COMPOUND_CUNI_ADDRESS
    let cCOMPAddress = "0x0fF50a12759b081Bb657ADaCf712C52bb015F1Cd"
    console.log(`network.config.chainId:${network.config.chainId}`)
    if (network.config.chainId == 31337) {
        cDAIAddress = process.env.MAINNET_COMPOUND_CDAI_ADDRESS
        cXXXAddress = process.env.MAINNET_COMPOUND_CBAT_ADDRESS
        cCOMPAddress = "0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4" //mainnet cCOMP
    }

    const DAIAddress = getUnderlyingByCTokenAddress(cDAIAddress)
    const XXXAddress = getUnderlyingByCTokenAddress(cXXXAddress)

    const signers = await ethers.getSigners()
    const deployer = signers[0]
    const user = signers[1]

    console.log(`1111`)
    const tokenBase = DAIAddress
    const tokenQuote = XXXAddress
    const underlyingDecimalsOfDAI = 18
    const underlyingAsCollateral = 0.031 //DAI         
    const investmentAmount = (underlyingAsCollateral * Math.pow(10, underlyingDecimalsOfDAI)).toString();
    const investmentIsQuote = false
    const lever = 2
    const isShort = false    

    console.log(`2222`)

    const collateralLeverOnDeployer = await ethers.getContract("CollateralLever", deployer)

    console.log(`3333 contract: ${collateralLeverOnDeployer.address}`)
    console.log(`deployer addr: ${deployer.address}, user addr:${user.address}`)

    const collateralLeverOnUser = await collateralLeverOnDeployer.connect(user)

    console.log(`44441`)
    
    console.log(`before: user balance:${await getERC20Balance(DAIAddress, user.address)}, contract balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
    // await approveERC20(DAIAddress, user, collateralLeverOnUser.address, investmentAmount)
    // const tx = await collateralLeverOnUser.testTransferFrom(DAIAddress, user.address,collateralLeverOnUser.address, investmentAmount )
    // console.log(`after: user balance:${await getERC20Balance(DAIAddress, user.address)}, contract balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)

    // // const tx = await collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort, { gasLimit: 9000000 })
    // // const tx = await collateralLeverOnDeployer.addSupportedCToken(cDAIAddress,{ gasLimit: 4100000 })

    // console.log(`5555`)

    // const txReceipt = await tx.wait(1)

    // console.log(`6666`)

    // console.log(`collateralLever addr: ${collateralLeverOnUser.address}, positionId: ${txReceipt.events[0].args.positionInfo.positionId},positionInfo: ${txReceipt.events[0].args.positionInfo}`)
    // // console.log(`collateralLever addr: ${collateralLeverOnUser.address},sss: ${ txReceipt.events[0].args.cTokenAddress}`)

    // if (network.config.chainId == 31337) {
    //     console.log(`7777`)

    //     await moveBlock(2, 1000)
    // }
    // console.log(`8888`)
}

const getUnderlyingByCTokenAddress = async (ctokenAddress) => {
    const ctoken = await ethers.getContractAt(ctokenAbi, ctokenAddress)
    return await ctoken.underlying()
}

openPosition().then((resolve) => process.exit(0)).catch((e) => {
    console.log(e)
})

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