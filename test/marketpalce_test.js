const { expect, assert } = require("chai");
const { network, deployments, ethers } = require("hardhat");
const { developmentChains } = require("../../helper-hardhat-config");

!developmentChains.includes(network.name)
    ? describe.skip : describe("NFT marketplace unit tests", () => {
        let nftMarketplace, deployer, user, baseNFT, nftMarketplaceOfUser
        const TOKEN_ID = 0
        const TOKEN_ID_Of_USER = 1
        const PRICE = ethers.utils.parseEther("0.01")

        beforeEach(async () => {
            await deployments.fixture("all")
            const signers = await ethers.getSigners()
            deployer = signers[0]
            user = signers[1]
            nftMarketplace = await ethers.getContract("NFTMarketplace", deployer)
            nftMarketplaceOfUser = await nftMarketplace.connect(user)
            baseNFT = await ethers.getContract("BaseNFT", deployer)
            baseNFTOfuser = await ethers.getContract("BaseNFT", user)
            // baseNFT2 = await ethers.getContract("BaseNFT2", user)
            await baseNFT.mintNft()
            await baseNFTOfuser.mintNft()
            await baseNFT.approve(nftMarketplace.address, TOKEN_ID)
            await baseNFTOfuser.approve(nftMarketplace.address, TOKEN_ID_Of_USER)
        })
        describe("addItem", () => {
            it("price check error", async () => {
                await expect(nftMarketplace.addItem(baseNFT.address, TOKEN_ID, 0)).to.be.revertedWith("NFTMarketplace__PriceMustBeAbove0")
            })

            it("modifier NotAdded test", async () => {
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, 3)                
                await expect(nftMarketplace.addItem(baseNFT.address, TOKEN_ID, 4)).to.be.revertedWith(`NFTMarketplace__AlreadyAdded("${baseNFT.address}", ${TOKEN_ID})`)
            })

            it("mofifier IsNFTOwner test", async () => {
                nftMarketplaceOfUser = nftMarketplace.connect(user)
                await expect(nftMarketplaceOfUser.addItem(baseNFT.address, TOKEN_ID, 5)).to.be.revertedWith("NFTMarketplace__NotOwner")
            })

            it("event AddedItem is emitted", async () => {
                await expect(nftMarketplace.addItem(baseNFT.address, TOKEN_ID, 6)).to.emit(nftMarketplace, "AddedItem")
            })
            it("check added item", async () => {
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, PRICE)
                const item = await nftMarketplace.getAddedItem(baseNFT.address, TOKEN_ID)
                // console.log(item.price)
                // console.log(PRICE)
                // console.log(item.seller)
                assert(item.price.toString() == PRICE.toString())
                assert(item.seller == deployer.address)
            })
            it("other user added item", async () => {
                await nftMarketplaceOfUser.addItem(baseNFT.address, TOKEN_ID_Of_USER, PRICE)
                const item = await nftMarketplaceOfUser.getAddedItem(baseNFTOfuser.address, TOKEN_ID_Of_USER)
                assert(item.price.toString() == PRICE.toString())
                assert(item.seller == user.address)
            })
        })

        describe("deleteItem", () => {
            beforeEach(async ()=>{
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, PRICE)                
            })

            // it("tokenId param is error",async()=>{
            //     await expect(nftMarketplace.deleteItem(baseNFT.address, TOKEN_ID)).to.be.revertedWith("NFTMarketplace__NotAdded")
            // })
            
            it("modifier isNFTOwner check", async()=>{
                await expect( nftMarketplaceOfUser.deleteItem(baseNFT.address, TOKEN_ID)).to.be.revertedWith("NFTMarketplace__NotOwner")
            })
            it("emit event and item check", async()=>{
                await expect( nftMarketplace.deleteItem(baseNFT.address, TOKEN_ID)).to.emit(nftMarketplace,"DeletedItem")
                const item = await nftMarketplace.getAddedItem(baseNFT.address, TOKEN_ID)
                // console.log(item.seller) 
                assert(item.price.toString() == 0)                
            })
        })

        describe("modifyPrice", () => {
            beforeEach(async ()=>{
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, PRICE)                
            })
            it("modifier AlreadyAdded", async()=>{
                await expect(nftMarketplace.modifyPrice(baseNFT.address, TOKEN_ID_Of_USER, PRICE)).to.be.revertedWith("NFTMarketplace__NotAdded")
            })
            it("modifier isNFTOwner", async()=>{
                await expect(nftMarketplaceOfUser.modifyPrice(baseNFT.address, TOKEN_ID, PRICE)).to.be.revertedWith("NFTMarketplace__NotOwner")
            })
            it("param price error", async()=>{
                await expect(nftMarketplace.modifyPrice(baseNFT.address, TOKEN_ID, 0)).to.be.revertedWith("NFTMarketplace__PriceMustBeAbove0")
            })
            it("emit event", async()=>{
                const newPrice = ethers.utils.parseEther("0.02")
                await expect(nftMarketplace.modifyPrice(baseNFT.address, TOKEN_ID, newPrice)).to.emit(nftMarketplace,"AddedItem")
            })            

            it("item check", async()=>{         
                const newPrice = ethers.utils.parseEther("0.02")       
                await nftMarketplace.modifyPrice(baseNFT.address, TOKEN_ID, newPrice)
                const item = await nftMarketplace.getAddedItem(baseNFT.address, TOKEN_ID)
                assert(item.price.toString() == newPrice.toString())                
                assert(item.seller == deployer.address)
            })            
        })
        describe("buyNFT", () => {
            beforeEach(async ()=>{
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, PRICE)                
            })
            it("modifier AlreadyAdded", async()=>{
                await expect(nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID_Of_USER)).to.be.revertedWith("NFTMarketplace__NotAdded")
            })
            it("revert if price not met", async()=>{
                const inputPrice = ethers.utils.parseEther("0.009")
                await expect(nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID, {value: inputPrice})).to.be.revertedWith("NFTMarketplace__BuyWithNotEnoughValue")
            })
            it("emit event", async()=>{                
                await expect(nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})).to.emit(nftMarketplaceOfUser, "BuyNFT")
            })

            it("item check", async()=>{                
                await nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})
                const item = await nftMarketplaceOfUser.getAddedItem(baseNFT.address, TOKEN_ID)
                const proceeds = await nftMarketplace.getProceeds(deployer.address)
                assert(item.price.toString()==0)                
                assert(proceeds.toString() == PRICE.toString())
            })
            it("balance of marketplace contract is PRICE", async()=>{                
                await nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})
                const marketplaceBalance = await ethers.provider.getBalance(nftMarketplace.address)                                
                assert(marketplaceBalance.toString() == PRICE.toString())                
            })
        })
        describe("withdrawProceeds", () => {
            beforeEach(async ()=>{
                await nftMarketplace.addItem(baseNFT.address, TOKEN_ID, PRICE)                
                await nftMarketplaceOfUser.buyNFT(baseNFT.address, TOKEN_ID, {value: PRICE})
            })
            it("revert if proceeds <= 0", async()=>{
                await expect(nftMarketplaceOfUser.withdrawProceeds()).to.be.revertedWith("NFTMarketplace__withdrawNoProceeds")
            })
            it("emit event", async()=>{
                await expect(nftMarketplace.withdrawProceeds()).to.emit(nftMarketplace,"WithdrawProceeds")
            })
            it("contract balance is 0", async()=>{
                await nftMarketplace.withdrawProceeds()
                const balance = await ethers.provider.getBalance(nftMarketplace.address)
                assert(balance.toString() == 0)
            })
            it("deployer balance check ", async()=>{
                const balanceBefore = await deployer.getBalance()
                const proceeds = await nftMarketplace.getProceeds(deployer.address)
                const txResp = await nftMarketplace.withdrawProceeds()
                console.log("提现了")
                const txRecept = await txResp.wait(1)
                console.log("after wait 1")
                const {gasUsed, effectiveGasPrice} = txRecept
                const gasCost = gasUsed.mul(effectiveGasPrice)
                const balanceAfter = await deployer.getBalance()                
                // console.log(`before balance:${balanceBefore}, gascost:${gasCost.toString()}, proceeds:${proceeds.toString()}, after balance:${balanceAfter.toString()}`)
                assert(balanceBefore.add(proceeds).toString() == balanceAfter.add(gasCost).toString())
            })
        })
    })