// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {PaymentsVault} from '../PaymentsVault.sol';

/**
 * @title Nevermined Payments Vault V2 contract
 * @author Nevermined AG
 * @notice This contract extends PaymentsVault with new functionality for testing upgrades
 */
contract PaymentsVaultV2 is PaymentsVault {
    // keccak256(abi.encode(uint256(keccak256("nevermined.paymentsvaultv2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PAYMENTS_VAULT_V2_STORAGE_LOCATION =
        0x28ab533a612090f8cd9aa9d662c09230d4e0acaeaf3caaeb1869c2ae8ff57200;

    /// @custom:storage-location erc7201:nevermined.paymentsvaultv2.storage
    struct PaymentsVaultV2Storage {
        string version;
    }

    /**
     * @notice New function to initialize the version
     * @param _version The version string to set
     */
    function initializeV2(string memory _version) external restricted {
        _getPaymentsVaultV2Storage().version = _version;
    }

    /**
     * @notice New function to get the version
     * @return The current version string
     */
    function getVersion() external view returns (string memory) {
        return _getPaymentsVaultV2Storage().version;
    }

    function _getPaymentsVaultV2Storage() internal pure returns (PaymentsVaultV2Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := PAYMENTS_VAULT_V2_STORAGE_LOCATION
        }
    }
}
