pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './NFT721Upgradeable.sol';

contract SoulBoundUpgradeable is NFT721Upgradeable {

    function transferFrom(
        address,
        address,
        uint256
    ) public virtual override {
        revert('SoulBound can not be transferred');
    }

    function safeTransferFrom(
        address,
        address,
        uint256
    ) public virtual override {
        revert('SoulBound can not be transferred');
    }

    function safeTransferFrom(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override {
        revert('SoulBound can not be transferred');
    }
}
