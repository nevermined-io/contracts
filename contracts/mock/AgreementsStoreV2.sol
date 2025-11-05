// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {AgreementsStore} from '../agreements/AgreementsStore.sol';

/**
 * @title Nevermined Agreements Store V2 contract
 * @author Nevermined AG
 * @notice This contract extends AgreementsStore with new functionality for testing upgrades
 */
contract AgreementsStoreV2 is AgreementsStore {
    // keccak256(abi.encode(uint256(keccak256("nevermined.agreementsstorev2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AGREEMENTS_STORE_V2_STORAGE_LOCATION =
        0x3066dda5e50fbe03df39fcab279dfffe7da3f5f8f7c27789ff36d18da4ac4500;

    /// @custom:storage-location erc7201:nevermined.agreementsstorev2.storage
    struct AgreementsStoreV2Storage {
        string version;
    }

    /**
     * @notice New function to initialize the version
     * @param _version The version string to set
     */
    function initializeV2(string memory _version) external restricted {
        AgreementsStoreV2Storage storage $asv2 = _getAgreementsStoreV2Storage();

        $asv2.version = _version;
    }

    /**
     * @notice New function to get the version
     * @return The current version string
     */
    function getVersion() external view returns (string memory) {
        AgreementsStoreV2Storage storage $ = _getAgreementsStoreV2Storage();
        return $.version;
    }

    function _getAgreementsStoreV2Storage() internal pure returns (AgreementsStoreV2Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := AGREEMENTS_STORE_V2_STORAGE_LOCATION
        }
    }
}
