// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {NVMConfig} from '../NVMConfig.sol';

/**
 * @title Nevermined Config V2 contract
 * @author Nevermined AG
 * @notice This contract extends NVMConfig with new functionality for testing upgrades
 */
contract NVMConfigV2 is NVMConfig {
    // keccak256(abi.encode(uint256(keccak256("nevermined.nvmconfigv2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NVM_CONFIG_V2_STORAGE_LOCATION =
        0xb5bb4068c8b208c83c281a1aca2086fb61708189787baebdb5fa9085d27f5d00;

    /// @custom:storage-location erc7201:nevermined.nvmconfigv2.storage
    struct NVMConfigV2Storage {
        string version;
    }

    /**
     * @notice New function to initialize the version
     * @param _version The version string to set
     */
    function initializeV2(string memory _version) external restricted {
        NVMConfigV2Storage storage $ = _getNVMConfigV2Storage();
        $.version = _version;
    }

    /**
     * @notice New function to get the version
     * @return The current version string
     */
    function getVersion() external view returns (string memory) {
        NVMConfigV2Storage storage $ = _getNVMConfigV2Storage();
        return $.version;
    }

    function _getNVMConfigV2Storage() internal pure returns (NVMConfigV2Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NVM_CONFIG_V2_STORAGE_LOCATION
        }
    }
}
