const { ethers } = require('hardhat')
const { readArtifact } = require('./artifacts')

async function callContract(instance, f) {
    // console.log('Calling contract ...', instance)
    const contractOwner = await instance.owner()
    // console.log('Contract Owner: ', contractOwner)
    let tx
    try {
        const signer = await ethers.provider.getSigner(contractOwner)
        tx = await f(instance.connect(signer).populateTransaction)
        // console.log('Got tx', tx)
        const res = await signer.sendTransaction(tx)
        await res.wait()
    } catch (err) {
        console.log('Warning: TX fail')
        console.log(err)
        console.log(tx)
    }
}

async function main() {
    const readContract = async function(name) {
        const afact = readArtifact(name)
        return new ethers.Contract(afact.address, afact.abi, await ethers.provider.getSigner())
    }

    const didRegistry = await readContract('DIDRegistry')
    const transferCondition = await readContract('TransferDIDOwnershipCondition')
    const nftLock = await readContract('NFTLockCondition')
    const nft1155 = await readContract('NFT1155Upgradeable')
    const nft721 = await readContract('NFT721Upgradeable')
    const transfer721 = await readContract('TransferNFT721Condition')
    const lock721 = await readContract('NFT721LockCondition')
    const transfer1155 = await readContract('TransferNFTCondition')
    // Remove contracts from managers
    await callContract(didRegistry, a => a.setManager(transferCondition.address, false))
    await callContract(nft1155, a => a.setProxyApproval(nftLock.address, false))
    await callContract(nft721, a => a.setProxyApproval(lock721.address, false))
    await callContract(nft721, a => a.setProxyApproval(nftLock.address, false))
    await callContract(nft1155, a => a.setProxyApproval(transfer1155.address, false))
    await callContract(nft721, a => a.setProxyApproval(transfer721.address, false))
    await callContract(nft1155, a => a.revokeMinter(transfer1155.address))
    await callContract(nft721, a => a.revokeMinter(transfer721.address))
}

main()
