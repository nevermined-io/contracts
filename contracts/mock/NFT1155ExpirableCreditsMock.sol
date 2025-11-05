// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {NFT1155ExpirableCredits} from '../token/NFT1155ExpirableCredits.sol';

contract NFT1155ExpirableCreditsMock is NFT1155ExpirableCredits {
    string private _version;

    function initializeV2(string memory newVersion) external restricted {
        _version = newVersion;
    }

    function getVersion() external view returns (string memory) {
        return _version;
    }
}
