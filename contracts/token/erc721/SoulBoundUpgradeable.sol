pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './NFT721Upgradeable.sol';

contract SoulBoundUpgradeable is NFT721Upgradeable {

    // solhint-disable-next-line
    function initialize(
        address owner,
        address didRegistryAddress,
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap
    )
    public
    override
    initializer
    {
        __NFT721Upgradeable_init(owner, didRegistryAddress, name, symbol, uri, cap);
        NFT_TYPE = keccak256('nft721-soulbound');
    }    
    
    function _beforeTokenTransfer(
        address, // from
        address, // to
        uint256, // firstTokenId
        uint256 // batchSize
    ) internal virtual override {
        revert('SoulBound can not be transferred');
    }
    
}
