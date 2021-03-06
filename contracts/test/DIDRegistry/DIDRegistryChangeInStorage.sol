pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// This product includes software developed at BigchainDB GmbH and Ocean Protocol
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

// Contain upgraded version of the contracts for test
import '../../registry/DIDFactory.sol';

contract DIDRegistryChangeInStorage is DIDFactory {

    // New variables should be added after the last variable
    // Old variables should be kept even if unused
    // https://github.com/jackandtheblockstalk/upgradeable-proxy#331-you-can-1
    mapping(bytes32 => uint256) public timeOfRegister;
}
