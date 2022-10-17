const { ethers, network } = require("hardhat")
const { moveBlock } = require("../utils/move_block")
const ctokenAbi = require("../constants/ctoken_abi.json")
const erc20Abi = require("../constants/erc20_abi.json")
const { developmentChains, VERIFICATION_BLOCK_CONFIRMATIONS } = require("../helper-hardhat-config")

async function exec() {
    let cDAIAddress = process.env.GOERLI_COMPOUND_CDAI_ADDRESS
    let cXXXAddress = process.env.GOERLI_COMPOUND_CUSDC_ADDRESS
    let comptrollerAddress = process.env.GOERLI_COMPTROLLER_ADDRESS

    console.log(`network.config.chainId:${network.config.chainId}`)
    if (network.config.chainId == 31337) {
        cDAIAddress = process.env.MAINNET_COMPOUND_CDAI_ADDRESS
        cXXXAddress = process.env.MAINNET_COMPOUND_CUSDC_ADDRESS
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
    // let nonce = 204
    // const tx = await deployer.sendTransaction({
    //     to: user.address,
    //     value: ethers.utils.parseEther("0.001"),
    //     nonce:nonce,
    //     gasPrice:13000000000
    //   })
    // console.log(`position:${await collateralLeverOnDeployer.s_userAddress2PositionInfos(deployer.address, 1)}`)
    
    await openPostion(DAIAddress, XXXAddress, cDAIAddress, cXXXAddress, user, collateralLeverOnDeployer, collateralLeverOnUser, tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)


    if (network.config.chainId == 31337) {
        console.log(`7777`)
        await moveBlock(2, 1000)
    }
}

const openPostion = async (DAIAddress, XXXAddress, cDAIAddress, cXXXAddress, user, collateralLeverOnDeployer, collateralLeverOnUser, tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort) => {
    const gasPrice = 10000000000
    await approveERC20(DAIAddress, user, collateralLeverOnUser.address, investmentAmount)
    const txAdd = await collateralLeverOnDeployer.addSupportedCToken(cDAIAddress, { gasLimit: 3000000,gasPrice:gasPrice})
    const txAdd2 = await collateralLeverOnDeployer.addSupportedCToken(cXXXAddress, { gasLimit: 3000000,gasPrice:gasPrice})
    console.log(`txadd: gaslimit:${txAdd.gasLimit.toString()},gasPrice:${txAdd.gasPrice.toString()}`)        
    await txAdd.wait(1)
    await txAdd2.wait(1)
    
    console.log(`before:DAI user balance:${await getERC20Balance(DAIAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
    console.log(`before:XXX user balance:${await getERC20Balance(XXXAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(XXXAddress, collateralLeverOnUser.address)}`)
    const tx = await collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort, { gasLimit: 9000000,gasPrice:gasPrice })


    // //----------------------------------------------mytest

    // const mantissa = investmentAmount;

    // const DAIWithUser = await ERC20TokenWithSigner(DAIAddress, user)

    // const myTestContractByDeployer = await ethers.getContract("MyTest", deployer)

    // const myTestContractByUser = await myTestContractByDeployer.connect(user)

    // await DAIWithUser.transfer(myTestContractByUser.address, mantissa, { gasLimit: 3000000 })


    // console.log(`before:DAI user balance:${await getERC20Balance(DAIAddress, user.address)}, mytestContract balance:${await getERC20Balance(DAIAddress, myTestContractByUser.address)}`)
    // console.log(`before:XXX user balance:${await getERC20Balance(XXXAddress, user.address)}, mytestContract balance:${await getERC20Balance(XXXAddress, myTestContractByUser.address)}`)
    // console.log(`comptrollerAddress: ${comptrollerAddress}`)
    // const param = {
    //     _cEtherAddress: cXXXAddress, //borrow
    //     _comptrollerAddress: comptrollerAddress,
    //     _cTokenAddress: cDAIAddress, //collateral
    //     _underlyingAddress: DAIAddress,
    //     _underlyingToSupplyAsCollateral: mantissa
    // }
    // // const tx = await myTestContractByUser.erc20BorrowErc20Example(param,{gasLimit:3000000})
    // const tx = await myTestContractByUser._borrow(comptrollerAddress, cDAIAddress, cXXXAddress, mantissa, 11, { gasLimit: 3000000 })

    // //----------------------------------------------mytest over

    console.log(`5555`)

    const txReceipt = await tx.wait(1)

    console.log(`position:${await collateralLeverOnDeployer.s_userAddress2PositionInfos(user.address, 1)}, collateralLeverOnUser balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
    console.log(`after:DAI user balance:${await getERC20Balance(DAIAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(DAIAddress, collateralLeverOnUser.address)}`)
    console.log(`after:XXX user balance:${await getERC20Balance(XXXAddress, user.address)}, collateralLeverOnUser balance:${await getERC20Balance(XXXAddress, collateralLeverOnUser.address)}`)


    for (let i = 0; i < txReceipt.events.length; i++) {
        const element = txReceipt.events[i];
        if (element.args != undefined && element.args.positionInfo != undefined) {
            positionId = element.args.positionInfo.positionId
            console.log(`positionInfo:${element.args.positionInfo}`)
        }
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