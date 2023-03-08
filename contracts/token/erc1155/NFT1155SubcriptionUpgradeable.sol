pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import './NFT1155Upgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT1155SubscriptionUpgradeable is NFT1155Upgradeable {

    // Mapping of expiration block number per user and tokenId
    // The key of this mapping is the `keccak256(abi.encode(address,tokenId))
    mapping(bytes32 => uint256) internal _expiration;
    
    /**
     * @dev This mint function allows to define when the tokenId of the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     */
    function mint(address to, uint256 tokenId, uint256 amount, uint256 expirationBlock, bytes memory data) public {
        super.mint(to, tokenId, amount, data);
        _expiration[keccak256(abi.encode(to, tokenId))] = expirationBlock;
    }
    
    /**
     * @dev See {NFT1155Upgradeableable-balanceOf}.
     */
    function balanceOf(address account, uint256 tokenId) public view virtual override returns (uint256) {
        bytes32 _expirationKey = keccak256(abi.encode(account, tokenId));
        if (_expiration[_expirationKey] == 0 || _expiration[_expirationKey] > block.number)
            return super.balanceOf(account, tokenId);
        return 0;
    }
}
