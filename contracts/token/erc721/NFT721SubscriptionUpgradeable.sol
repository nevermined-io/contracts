pragma solidity ^0.8.0;

import './NFT721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT721SubscriptionUpgradeable is NFT721Upgradeable {
    
    // Mapping of expiration block number per user (subscription NFT holder)
    mapping(bytes32 => uint256) internal _expirationBlock;

    /**
     * @dev This mint function allows to define when the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     * @dev TransferNFT721Condition needs to have the `NVM_OPERATOR_ROLE`
     */
    function mint(address to, uint256 tokenId, uint256 expirationBlock) public {
        super.mint(to, tokenId);
        _expirationBlock[keccak256(abi.encode(to))] = expirationBlock;
    }
    
    /**
     * @dev See {IERC721-balanceOf}.
     */    
    function balanceOf(address owner) public view override returns (uint256) {
        bytes32 _expirationKey = keccak256(abi.encode(owner));
        if (_expirationBlock[_expirationKey] == 0 || _expirationBlock[_expirationKey] > block.number)
            return super.balanceOf(owner);
        return 0;
    }
}
