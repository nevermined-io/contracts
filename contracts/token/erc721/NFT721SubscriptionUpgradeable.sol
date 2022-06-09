pragma solidity ^0.8.0;

import './NFT721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT721SubscriptionUpgradeable is NFT721Upgradeable {

    function mint(address to, uint256 id, uint256 expirationBlock) public {
        require(hasRole(MINTER_ROLE, msg.sender), 'only minter can mint');
        _safeMint(to, id);
        _expiration[to] = expirationBlock;
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */    
    function balanceOf(address owner) public view override returns (uint256) {
        if (_expiration[owner] == 0 || _expiration[owner] > block.number)
            return super.balanceOf(owner);
        return 0;
    }
}
