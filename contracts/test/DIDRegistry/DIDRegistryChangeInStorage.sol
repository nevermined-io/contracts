pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

// Contain upgraded version of the contracts for test
import '../../registry/DIDRegistry.sol';

contract DIDRegistryChangeInStorage is DIDRegistry {

    // New variables should be added after the last variable
    // Old variables should be kept even if unused
    // https://github.com/jackandtheblockstalk/upgradeable-proxy#331-you-can-1
    mapping(bytes32 => uint256) public timeOfRegister;
}
