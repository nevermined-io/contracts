/* global web3 */

const testUtils = require('../../../helpers/utils.js')
const { getBalance } = require('../../../helpers/getBalance.js')
const constants = require('../../../helpers/constants.js')

function nftLockWrapper(contract) {
    contract.hashWrap = (did, escrowPaymentAddress, tokenAddress, amounts, receivers) => {
        return contract.hashValuesMarked(did, escrowPaymentAddress, amounts[0], receivers[0], tokenAddress)
    }
    contract.fulfillWrap = async (agreementId, did, escrowPaymentAddress, tokenAddress, amounts, receivers, owner) => {
        return contract.fulfillMarked(agreementId, did, escrowPaymentAddress, amounts[0], receivers[0], tokenAddress)
    }
    contract.initWrap = (owner, conditionStoreManagerAddress, _didRegistryAddress, args) => {
        return contract.initialize(
            owner,
            conditionStoreManagerAddress,
            owner,
            args
        )
    }
    return contract
}

function tokenLockWrapper(contract) {
    contract.hashWrap = (did, escrowPaymentAddress, tokenAddress, amounts, receivers) => {
        return contract.hashValues(did, escrowPaymentAddress, tokenAddress, amounts, receivers)
    }
    contract.fulfillWrap = (agreementId, did, escrowPaymentAddress, tokenAddress, amounts, receivers) => {
        return contract.fulfill(agreementId, did, escrowPaymentAddress, tokenAddress, amounts, receivers)
    }
    contract.initWrap = (owner, conditionStoreManagerAddress, didRegistryAddress, args) => {
        return contract.initialize(
            owner,
            conditionStoreManagerAddress,
            didRegistryAddress,
            args
        )
    }

    return contract
}

function nft721LockWrapper(contract) {
    contract.hashWrap = (did, escrowPaymentAddress, tokenAddress, amounts, receivers) => {
        return contract.hashValuesMarked(did, escrowPaymentAddress, amounts[0], receivers[0], tokenAddress)
    }
    contract.fulfillWrap = async (agreementId, did, escrowPaymentAddress, tokenAddress, amounts, receivers) => {
        return contract.fulfillMarked(agreementId, did, escrowPaymentAddress, amounts[0], receivers[0], tokenAddress)
    }
    contract.initWrap = (owner, conditionStoreManagerAddress, _didRegistryAddress, args) => {
        return contract.initialize(
            owner,
            conditionStoreManagerAddress,
            args
        )
    }
    return contract
}

function tokenEscrowWrapper(contract) {
    contract.hashWrap = (did, amounts, receivers, reta, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId) => {
        return contract.hashValuesMulti(did, amounts, receivers, reta, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId)
    }
    contract.fulfillWrap = (agreementId, did, amounts, receivers, returnAdddress, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId) => {
        return contract.fulfillMulti(
            agreementId,
            did,
            amounts,
            receivers,
            returnAdddress,
            escrowPaymentAddress,
            tokenAddress,
            lockConditionId,
            releaseConditionId
        )
    }

    return contract
}

function nftEscrowWrapper(contract) {
    contract.hashWrap = (did, amounts, receivers, returnAdddress, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId) => {
        return contract.hashValues(did, amounts[0], receivers[0], returnAdddress, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId)
    }
    contract.fulfillWrap = (agreementId, did, amounts, receivers, returnAdddress, escrowPaymentAddress, tokenAddress, lockConditionId, releaseConditionId) => {
        return contract.fulfill(
            agreementId,
            did,
            amounts[0],
            receivers[0],
            returnAdddress,
            escrowPaymentAddress,
            tokenAddress,
            lockConditionId,
            releaseConditionId
        )
    }

    return contract
}

function tokenTokenWrapper(contract) {
    contract.initWrap = async (a, b, _registry) => {
        return contract.initialize(a, b)
    }
    contract.getBalance = (addr) => {
        return getBalance(contract, addr)
    }
    contract.mintWrap = async (_registry, target, amount, from) => {
        return contract.mint(target, amount, { from })
    }
    contract.makeDID = (sender, registry) => {
        return testUtils.generateId()
    }
    contract.approveWrap = (addr, amount, args) => {
        return contract.approve(addr, amount, args)
    }
    contract.transferWrap = (addr, amount, { from }) => {
        return contract.transfer(addr, amount, { from })
    }
    return contract
}

function nftTokenWrapper(contract) {
    contract.initWrap = async (owner, _b, registry, config) => {
        await contract.initialize(owner, registry.address, '', '', '', config.address)
    }
    contract.getBalance = async (addr) => {
        if (!contract.did) {
            return 0
        }
        return web3.utils.toDecimal(await contract.balanceOf(addr, contract.did))
    }
    contract.makeDID = async (sender, registry) => {
        const didSeed = testUtils.generateId()
        const checksum = testUtils.generateId()
        contract.did = await registry.hashDID(didSeed, sender)
        await registry.registerMintableDID(
            didSeed, contract.address, checksum, [], '', 1000, 0, constants.activities.GENERATED, '', '', { from: sender }
        )
        return contract.did
    }
    contract.mintWrap = async (registry, target, amount, from) => {
        await contract.mint(contract.did, amount, { from: target })
    }
    contract.approveWrap = (addr, amount, args) => {
        return contract.grantOperatorRole(addr, args)
    }
    contract.transferWrap = async (target, amount, { from }) => {
        await contract.safeTransferFrom(from, target, contract.did, amount, '0x', { from })
    }
    return contract
}

function nft721TokenWrapper(contract) {
    contract.initWrap = async (owner, _b, registry, config) => {
        await contract.initialize(owner, registry.address, '', '', '', 0, config.address)
    }
    contract.getBalance = async (addr) => {
        if (!contract.did) {
            return 0
        }
        try {
            const res = await contract.ownerOf(contract.did)
            return res === addr ? 1 : 0
        } catch (e) {
            return 0
        }
    }
    contract.makeDID = async (sender, registry) => {
        const didSeed = testUtils.generateId()
        const checksum = testUtils.generateId()
        contract.did = await registry.hashDID(didSeed, sender)
        await registry.registerMintableDID721(
            didSeed, contract.address, checksum, [], '', 0, false, constants.activities.GENERATED, '', { from: sender }
        )
        return contract.did
    }
    contract.mintWrap = async (registry, target, amount, from) => {
        await contract.mint(target, contract.did, { from: target })
    }
    contract.approveWrap = (addr, amount, args) => {
        return contract.grantOperatorRole(addr, args)
    }
    contract.transferWrap = async (target, amount, { from }) => {
        await contract.safeTransferFrom(from, target, contract.did, { from })
    }
    return contract
}

module.exports = {
    normal: {
        lockWrapper: tokenLockWrapper,
        escrowWrapper: tokenEscrowWrapper,
        tokenWrapper: tokenTokenWrapper
    },
    nft: {
        lockWrapper: nftLockWrapper,
        escrowWrapper: nftEscrowWrapper,
        tokenWrapper: nftTokenWrapper
    },
    nft721: {
        lockWrapper: nft721LockWrapper,
        escrowWrapper: nftEscrowWrapper,
        tokenWrapper: nft721TokenWrapper
    }
}
