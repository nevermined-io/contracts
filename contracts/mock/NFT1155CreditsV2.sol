// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {NFT1155Credits} from '../token/NFT1155Credits.sol';

/**
 * @title Nevermined NFT1155Credits V2 contract
 * @author Nevermined AG
 * @notice This contract extends NFT1155Credits with new functionality for testing upgrades
 */
contract NFT1155CreditsV2 is NFT1155Credits {
    // keccak256(abi.encode(uint256(keccak256("nevermined.nft1155creditsv2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFT1155_CREDITS_V2_STORAGE_LOCATION =
        0x9e5e354eee8fcd5abb2fb6e9dbef8c04a86de6e4753c3ed91a44ff3c565e7800;

    /// @custom:storage-location erc7201:nevermined.nft1155creditsv2.storage
    struct NFT1155CreditsV2Storage {
        string version;
    }

    /**
     * @notice New function to initialize the version
     * @param _version The version string to set
     */
    function initializeV2(string memory _version) external restricted {
        NFT1155CreditsV2Storage storage $ = _getNFT1155CreditsV2Storage();
        $.version = _version;
    }

    /**
     * @notice New function to get the version
     * @return The current version string
     */
    function getVersion() external view returns (string memory) {
        NFT1155CreditsV2Storage storage $ = _getNFT1155CreditsV2Storage();
        return $.version;
    }

    function _getNFT1155CreditsV2Storage() internal pure returns (NFT1155CreditsV2Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NFT1155_CREDITS_V2_STORAGE_LOCATION
        }
    }
}
