const BigNumber = require('bignumber.js')
/* globals web3 BigInt */

const getBalance = async (token, address, checkpoint = {}) => {
    const current = web3.utils.toDecimal(await token.balanceOf.call(address))
    const orig = checkpoint[address] || 0
    return current - orig
}

const getCheckpoint = async (token, addresses) => {
    const res = {}
    for (const addr of addresses) {
        res[addr] = web3.utils.toDecimal(await token.balanceOf.call(addr))
    }
    return res
}

const getETHBalance = async (address) => {
    return web3.eth.getBalance(address, 'latest')
        .then((balance) => {
            return BigInt(balance)
        })
}

const getETHBalanceBN = async (address) => {
    return web3.eth.getBalance(address, 'latest')
        .then((balance) => {
            return new BigNumber(balance)
        })
}

const getTokenBalance = getBalance

module.exports = { getBalance, getETHBalance, getETHBalanceBN, getCheckpoint, getTokenBalance }
