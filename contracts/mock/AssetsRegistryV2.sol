// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {AssetsRegistry} from '../AssetsRegistry.sol';

/**
 * @title Nevermined Assets Registry V2 contract
 * @author Nevermined AG
 * @notice This contract extends AssetsRegistry with new functionality for testing upgrades
 */
contract AssetsRegistryV2 is AssetsRegistry {
    // keccak256(abi.encode(uint256(keccak256("nevermined.assetsregistryv2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSETS_REGISTRY_V2_STORAGE_LOCATION =
        0xfb8a89f709568928aef7149587aed044b47ec77b8aa8d90b5de19055793b5600;

    /// @custom:storage-location erc7201:nevermined.assetsregistryv2.storage
    struct AssetsRegistryV2Storage {
        string version;
    }

    /**
     * @notice New function to initialize the version
     * @param _version The version string to set
     */
    function initializeV2(string memory _version) external restricted {
        AssetsRegistryV2Storage storage $ = _getAssetsRegistryV2Storage();
        $.version = _version;
    }

    /**
     * @notice New function to get the version
     * @return The current version string
     */
    function getVersion() external view returns (string memory) {
        AssetsRegistryV2Storage storage $ = _getAssetsRegistryV2Storage();
        return $.version;
    }

    function _getAssetsRegistryV2Storage() internal pure returns (AssetsRegistryV2Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := ASSETS_REGISTRY_V2_STORAGE_LOCATION
        }
    }
}
