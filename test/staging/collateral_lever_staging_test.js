const { expect, assert } = require("chai");
const { network, deployments, ethers } = require("hardhat");
const { developmentChains } = require("../../helper-hardhat-config");
const ctokenAbi = require("../../constants/ctoken_abi.json")
const erc20Abi = require("../../constants/erc20_abi.json")

developmentChains.includes(network.name)
    ? describe.skip : describe("Collateral Lever staging test", () => {
        let collateralLeverOnDeployer, collateralLeverOnUser, deployer, user, DAIAddress
        let tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort
        const cDAIAddress = process.env.GOERLI_COMPOUND_CDAI_ADDRESS
        const cUNIAddress = process.env.GOERLI_COMPOUND_CUNI_ADDRESS
        const cTokenAddressOfTokenBase = cDAIAddress
        const cTokenAddressOfTokenQuote = cUNIAddress

        beforeEach(async () => {
            const signers = await ethers.getSigners()
            deployer = signers[0]
            user = signers[1]
            collateralLeverOnDeployer = await ethers.getContract("CollateralLever", deployer)
            collateralLeverOnUser = await collateralLeverOnDeployer.connect(user)


            tokenBase = getUnderlyingByCTokenAddress(cTokenAddressOfTokenBase)
            tokenQuote = getUnderlyingByCTokenAddress(cTokenAddressOfTokenQuote)
            const underlyingDecimalsOfDAI = 18
            const underlyingAsCollateral = 0.3 //DAI         
            investmentAmount = (underlyingAsCollateral * Math.pow(10, underlyingDecimalsOfDAI)).toString();
            investmentIsQuote = false
            lever = 2
            isShort = false
        })
        describe("addSupportedCToken", () => {
            it("event AddSupportedCToken is emitted and check s_token2CToken ", async () => {
                await expect(collateralLeverOnDeployer.addSupportedCToken(process.env.GOERLI_COMPOUND_CDAI_ADDRESS)).to.emit(collateralLeverOnDeployer, "AddSupportedCToken")
                underlying = await getUnderlyingByCTokenAddress(process.env.GOERLI_COMPOUND_CDAI_ADDRESS)
                ctokenAddress = await collateralLeverOnUser.s_token2CToken(underlying)
                assert(ctokenAddress.toLowerCase() === process.env.GOERLI_COMPOUND_CDAI_ADDRESS.toLowerCase())
            })
            it("revert when param is not ctoken address", async () => {
                await expect(collateralLeverOnDeployer.addSupportedCToken(process.env.GOERLI_UNISWAP_V2_FACTORY_ADDRESS)).to.be.reverted
            })

            it("not owner revert", async () => {
                await expect(collateralLeverOnUser.addSupportedCToken(process.env.GOERLI_COMPOUND_CDAI_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner")
            })
        })

        describe("openPosition", () => {
            it("revert: tokenBase == tokenQuote", async () => {
                tokenQuote = tokenBase
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenBaseEqTokenQuote")
            })
            it("revert: investmentAmount == 0", async () => {
                investmentAmount = 0
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__investmentAmountIsZero")
            })
            it("revert: lever is wrong", async () => {
                lever = 4
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__leverIsWrong")
            })
            it("revert: not supported tokenBase", async () => {
                tokenBase = process.env.GOERLI_UNISWAP_V2_FACTORY_ADDRESS
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenNotSupport")
            })
            it("revert: not supported tokenQuote", async () => {
                tokenQuote = process.env.GOERLI_UNISWAP_V2_FACTORY_ADDRESS
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenNotSupport")
            })

            it("emit OpenPositionSucc and check s_userAddress2PositionInfos", async () => {
                const oldUserTokenBaseAmount = Number(await getERC20Balance(tokenBase, user.address))
                const oldUserTokenQuoteAmount = Number(await getERC20Balance(tokenQuote, user.address))

                //approve to collateralLever                
                await approveERC20(DAIAddress, user, collateralLeverOnUser.address, investmentAmount)
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.emit(collateralLeverOnUser, "OpenPositionSucc")
                const postionInfo = await collateralLeverOnUser.s_userAddress2PositionInfos(user.address, 0)
                console.log(`postion info:"${postionInfo}`)
                console.log(`cTokenAddressOfTokenBase: ${cTokenAddressOfTokenBase}`)
                console.log(`cTokenAddressOfTokenQuote: ${cTokenAddressOfTokenQuote}`)

                if (isShort) {
                    assert(cTokenAddressOfTokenBase.toLowerCase() === postionInfo.cTokenBorrowingAddress.toLowerCase())
                    assert(cTokenAddressOfTokenQuote.toLowerCase() === postionInfo.cTokenCollateralAddress.toLowerCase())
                } else {
                    assert(cTokenAddressOfTokenBase.toLowerCase() === postionInfo.cTokenCollateralAddress.toLowerCase())
                    assert(cTokenAddressOfTokenQuote.toLowerCase() === postionInfo.cTokenBorrowingAddress.toLowerCase())
                }
                if (investmentIsQuote) {
                    assert(oldUserTokenQuoteAmount == await getERC20Balance(tokenQuote, user.address) + investmentAmount)
                } else {
                    const curBalance = Number(await getERC20Balance(tokenBase, user.address))
                    assert(oldUserTokenBaseAmount == curBalance + Number(investmentAmount))
                }
                assert(investmentAmount * lever == postionInfo.collateralAmountOfCollateralToken)
                assert(isShort === postionInfo.isShort)

            })
        })

        describe("closePosition", () => {
            beforeEach(async () => {
                await approveERC20(DAIAddress, user, collateralLeverOnUser.address, investmentAmount)
                await expect(collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.emit(collateralLeverOnUser, "OpenPositionSucc")
            })
            it("modifier OwnerOfPosition", async () => {
                await expect(collateralLeverOnUser.closePosition(3333)).to.be.revertedWith("CollateralLever__notOwnerOfPosition")
            })
            it("emit ClosePositionSucc  and check s_userAddress2PositionInfos", async () => {
                // await expect(collateralLeverOnUser.closePosition(1))
                await expect(collateralLeverOnUser.closePosition(1)).to.emit(collateralLeverOnUser, "ClosePositionSucc")
                const postionInfo = await collateralLeverOnUser.s_userAddress2PositionInfos(user.address, 0)
                console.log(`postion info:"${postionInfo}`)

                assert("0x0000000000000000000000000000000000000000" === postionInfo.cTokenBorrowingAddress.toLowerCase())
                assert("0x0000000000000000000000000000000000000000" === postionInfo.cTokenCollateralAddress.toLowerCase())

                assert(0 == postionInfo.positionId)
                assert(0 == postionInfo.collateralAmountOfCollateralToken)
                assert(0 == postionInfo.borrowedAmountOfBorrowingToken)
            })
        })
        describe("uniswapV2Call", () => {
            beforeEach(async () => {
                //todo
            })
            it("test", async () => {
                //todo
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

const approveERC20 = async (tokenAddress, from, to, amount) => {
    const DAIWithUser = await ERC20TokenWithSigner(tokenAddress, from)
    await DAIWithUser.approve(to, amount)
}
