const { expect, assert } = require("chai");
const { network, deployments, ethers } = require("hardhat");
const { developmentChains } = require("../../helper-hardhat-config");
const ctokenAbi = require("../../constants/ctoken_abi.json")
const erc20Abi = require("../../constants/erc20_abi.json")

!developmentChains.includes(network.name)
    ? describe.skip : describe("my_test", () => {
        let myTestContractByDeployer, myTestContractByUser, deployer, user

        beforeEach(async () => {
            await deployments.fixture("tt")
            const signers = await ethers.getSigners()
            deployer = signers[0]
            user = signers[1]
            myTestContractByDeployer = await ethers.getContract("MyTest", deployer)
            myTestContractByUser = await myTestContractByDeployer.connect(user)
        })
        describe("borrowEthExample", () => {
            let tokenBase, tokenQuote, mantissa
            const underlyingDecimalsOfDAI = 10
            const transferToContractFactor = 5

            beforeEach(async () => {
                const underlyingAsCollateral = 5
                mantissa = (underlyingAsCollateral * Math.pow(10, underlyingDecimalsOfDAI)).toString();
                //transfer DAI to user
                const addressWithDAI = "0x604981db0C06Ea1b37495265EDa4619c8Eb95A3D"
                await network.provider.send("hardhat_impersonateAccount", [addressWithDAI])
                const impersonatedSigner = await ethers.getSigner(addressWithDAI)
                // const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"            
                const DAIAddress = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)
                const tokenConnectedByImpersonatedSigner = await ethers.getContractAt(erc20Abi, DAIAddress, impersonatedSigner)
                
                await tokenConnectedByImpersonatedSigner.transfer(user.address, mantissa * (transferToContractFactor + 1))


                // console.log(`balance: deployer: ${await deployer.getBalance()}, user:${await user.getBalance()}`)     
                // console.log(`tokenBase balance: deployer: ${await getERC20Balance(tokenBase,deployer.address) }, user:${await getERC20Balance(tokenBase,user.address)}`)     
            })
            it("print", async () => {
                //approve to collateralLever
                const DAIAddress = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)
                const DAIWithUser = await ERC20TokenWithSigner(DAIAddress, user)
                
                await DAIWithUser.transfer(myTestContractByUser.address, mantissa * transferToContractFactor)

                const cETHAddress = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5"
                const comptrollerAddress = "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B"
                const cTokenDAIAddress = process.env.MAINNET_COMPOUND_CDAI_ADDRESS
                const underlyingDAIAddress = await getUnderlyingByCTokenAddress(cTokenDAIAddress)


                const param = {
                    _cEtherAddress: cETHAddress,
                    _comptrollerAddress: comptrollerAddress,
                    _cTokenAddress: cTokenDAIAddress,
                    _underlyingAddress: underlyingDAIAddress,
                    _underlyingToSupplyAsCollateral: mantissa
                }
                await myTestContractByUser.borrowEthExample(param)
                console.log(`over`)
            })
        })
    })

const getUnderlyingByCTokenAddress = async (ctokenAddress) => {
    const ctoken = await ethers.getContractAt(ctokenAbi, ctokenAddress)
    return await ctoken.underlying()
}

const getERC20Balance = async (tokenAddress, userAddress) => {
    const token = await ethers.getContractAt(erc20Abi, tokenAddress)
    return await token.balanceOf(userAddress);
}

const ERC20TokenWithSigner = async (tokenAddress, signerAccount) => {
    return await ethers.getContractAt(erc20Abi, tokenAddress, signerAccount)
}