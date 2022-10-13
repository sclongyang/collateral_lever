const { expect, assert } = require("chai");
const { network, deployments, ethers } = require("hardhat");
const { developmentChains } = require("../../helper-hardhat-config");
const ctokenAbi = require("../../constants/ctoken_abi.json")
const erc20Abi = require("../../constants/erc20_abi.json")

!developmentChains.includes(network.name)
    ? describe.skip : describe("Collateral Lever unit test", () => {
        let collateralLeverOnDeployer,collateralLeverOnUser, deployer, user                

        beforeEach(async () => {
            await deployments.fixture("all")
            const signers = await ethers.getSigners()
            deployer = signers[0]
            user = signers[1]
            collateralLeverOnDeployer = await ethers.getContract("CollateralLever", deployer)
            collateralLeverOnUser = await collateralLeverOnDeployer.connect(user)   
        })
        describe("addSupportedCToken", () => {
            it("event AddSupportedCToken is emitted and check s_token2CToken ", async () => {
                await expect(collateralLeverOnDeployer.addSupportedCToken(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)).to.emit(collateralLeverOnDeployer,"AddSupportedCToken")
                underlying = await getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)             
                ctokenAddress = await collateralLeverOnUser.s_token2CToken(underlying)
                assert(ctokenAddress.toLowerCase() === process.env.MAINNET_COMPOUND_CDAI_ADDRESS.toLowerCase())                
            })           
            it("revert when param is not ctoken address", async () => {
                await expect(collateralLeverOnDeployer.addSupportedCToken(process.env.MAINNET_UNISWAP_V2_FACTORY_ADDRESS)).to.be.reverted
            })

            it("not owner revert", async () => {
                await expect(collateralLeverOnUser.addSupportedCToken(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner")
            })          
        })

        describe("openPosition", () => {   
            let tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort                     
            beforeEach(async () => {
                tokenBase = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)         
                tokenQuote = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CBAT_ADDRESS)         
                investmentAmount = 11
                investmentIsQuote = false
                lever = 3
                isShort = false

                const addressWithDAI = "0x604981db0C06Ea1b37495265EDa4619c8Eb95A3D"    
                await network.provider.send("hardhat_impersonateAccount", [addressWithDAI])
                const impersonatedSigner = await ethers.getSigner(addressWithDAI)
                // const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"            
                const DAIAddress = getUnderlyingByCTokenAddress(process.env.MAINNET_COMPOUND_CDAI_ADDRESS)        
                const token = await ethers.getContractAt(erc20Abi, DAIAddress)            
                await token.connect(impersonatedSigner).transfer(user.address, "1111111")
                
                // console.log(`balance: deployer: ${await deployer.getBalance()}, user:${await user.getBalance()}`)     
                // console.log(`tokenBase balance: deployer: ${await getERC20Balance(tokenBase,deployer.address) }, user:${await getERC20Balance(tokenBase,user.address)}`)     
            })
            it("revert: tokenBase == tokenQuote", async()=>{
                tokenQuote = tokenBase
                await expect( collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenBaseEqTokenQuote")
            })
            it("revert: investmentAmount == 0", async()=>{
                investmentAmount = 0
                await expect( collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__investmentAmountIsZero")
            })
            it("revert: lever is wrong", async()=>{
                lever = 4
                await expect( collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__leverIsWrong")
            })
            it("revert: not supported tokenBase", async()=>{
                tokenBase = process.env.MAINNET_UNISWAP_V2_FACTORY_ADDRESS
                await expect( collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenNotSupport")
            })
            it("revert: not supported tokenQuote", async()=>{
                tokenQuote = process.env.MAINNET_UNISWAP_V2_FACTORY_ADDRESS
                await expect( collateralLeverOnUser.openPosition(tokenBase, tokenQuote, investmentAmount, investmentIsQuote, lever, isShort)).to.be.revertedWith("CollateralLever__tokenNotSupport")
            })
        })

        describe("closePosition", () => {
            beforeEach(async ()=>{
                await collateralLeverOnDeployer.addItem(baseNFT.address, TOKEN_ID, PRICE)                
            })
            it("modifier AlreadyAdded", async()=>{
                await expect(collateralLeverOnDeployer.modifyPrice(baseNFT.address, TOKEN_ID_Of_USER, PRICE)).to.be.revertedWith("NFTMarketplace__NotAdded")
            })
            it("modifier isNFTOwner", async()=>{
                await expect(collateralLeverOnUser.modifyPrice(baseNFT.address, TOKEN_ID, PRICE)).to.be.revertedWith("NFTMarketplace__NotOwner")
            })
            it("param price error", async()=>{
                await expect(collateralLeverOnDeployer.modifyPrice(baseNFT.address, TOKEN_ID, 0)).to.be.revertedWith("NFTMarketplace__PriceMustBeAbove0")
            })
            it("emit event", async()=>{
                const newPrice = ethers.utils.parseEther("0.02")
                await expect(collateralLeverOnDeployer.modifyPrice(baseNFT.address, TOKEN_ID, newPrice)).to.emit(collateralLeverOnDeployer,"AddedItem")
            })            

            it("item check", async()=>{         
                const newPrice = ethers.utils.parseEther("0.02")       
                await collateralLeverOnDeployer.modifyPrice(baseNFT.address, TOKEN_ID, newPrice)
                const item = await collateralLeverOnDeployer.getAddedItem(baseNFT.address, TOKEN_ID)
                assert(item.price.toString() == newPrice.toString())                
                assert(item.seller == deployer.address)
            })            
        })
        describe("uniswapV2Call", () => {
            beforeEach(async ()=>{
                await collateralLeverOnDeployer.addItem(baseNFT.address, TOKEN_ID, PRICE)                
            })
            it("modifier AlreadyAdded", async()=>{
                await expect(collateralLeverOnUser.buyNFT(baseNFT.address, TOKEN_ID_Of_USER)).to.be.revertedWith("NFTMarketplace__NotAdded")
            })
            it("revert if price not met", async()=>{
                const inputPrice = ethers.utils.parseEther("0.009")
                await expect(collateralLeverOnUser.buyNFT(baseNFT.address, TOKEN_ID, {value: inputPrice})).to.be.revertedWith("NFTMarketplace__BuyWithNotEnoughValue")
            })
            it("emit event", async()=>{                
                await expect(collateralLeverOnUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})).to.emit(collateralLeverOnUser, "BuyNFT")
            })

            it("item check", async()=>{                
                await collateralLeverOnUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})
                const item = await collateralLeverOnUser.getAddedItem(baseNFT.address, TOKEN_ID)
                const proceeds = await collateralLeverOnDeployer.getProceeds(deployer.address)
                assert(item.price.toString()==0)                
                assert(proceeds.toString() == PRICE.toString())
            })
            it("balance of marketplace contract is PRICE", async()=>{                
                await collateralLeverOnUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})
                const marketplaceBalance = await ethers.provider.getBalance(collateralLeverOnDeployer.address)                                
                assert(marketplaceBalance.toString() == PRICE.toString())                
            })
        })
    })

    const getUnderlyingByCTokenAddress = async(ctokenAddress)=>{
        const ctoken = await ethers.getContractAt(ctokenAbi, ctokenAddress)
        return await ctoken.underlying()   
    }

    const getERC20Balance = async(tokenAddress, userAddress)=>{        
        const token = await ethers.getContractAt(erc20Abi, tokenAddress)
        return await token.balanceOf(userAddress);
    }