const { network, ethers } = require("hardhat")


const moveBlock = async (blockAmounts, sleepMs/*ms*/ = 0) => {
    for (let index = 0; index < blockAmounts; index++) {
        await network.provider.request({
            method: "evm_mine",
            params: []
        })
        if (sleepMs > 0) {
            console.log(`mine sleep for ${sleepMs/1000} s`)
            await sleep(sleepMs)
        }
        console.log(`curBlockNum:${await ethers.provider.getBlockNumber()}`)
    }
}

const sleep = async (sleepMs) => {
    return new Promise((resolve) => {
        setTimeout(resolve(), sleepMs)
    })
}

module.exports = {
    moveBlock,
    sleep,
}