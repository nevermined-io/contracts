// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {NFT1155Base} from './NFT1155Base.sol';
import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title NFT1155Credits
 * @author Nevermined
 * @notice Implementation of non-expiring ERC1155 credits for the Nevermined ecosystem
 * @dev This contract extends NFT1155Base to implement standard credit tokens that never expire.
 * It provides a simple implementation for managing credits tied to specific plans, where
 * credits continue to be valid indefinitely after minting.
 *
 * This contract inherits permissions management and redemption rules from NFT1155Base,
 * including restrictions on transfers (credits are non-transferable).
 */
contract NFT1155Credits is NFT1155Base {
    /**
     * @notice Initializes the NFT1155Credits contract with required dependencies
     * @param _authority Address of the AccessManager contract
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract
     * @dev Also accepts unused name and symbol parameters for compatibility with other token standards
     */
    function initialize(
        IAccessManager _authority,
        IAsset _assetsRegistryAddress,
        string memory, // name
        string memory // symbol
    )
        external
        initializer
    {
        ERC1155Upgradeable.__ERC1155_init('');
        __NFT1155Credits_init(_authority, _assetsRegistryAddress);
    }

    /**
     * @notice Mints credits for a specific plan
     * @param _to Address that will receive the credits
     * @param _planId Identifier of the plan
     * @param _value Amount of credits to mint
     * @param _data Additional data to pass to the receiver
     * @dev Inherits minting permission checks from NFT1155Base
     */
    function mint(address _to, uint256 _planId, uint256 _value, bytes memory _data) public virtual override {
        super.mint(_to, _planId, _value, _data);
    }

    /**
     * @notice Mints multiple credits for multiple plans in a single transaction
     * @param _to Address that will receive the credits
     * @param _ids Array of plan identifiers
     * @param _values Array of credit amounts to mint
     * @param _data Additional data to pass to the receiver
     * @dev Inherits minting permission checks from NFT1155Base
     */
    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        public
        virtual
        override
    {
        super.mintBatch(_to, _ids, _values, _data);
    }

    /**
     * @notice Burns credits from a specific plan
     * @param _from Address from which credits will be burned
     * @param _planId Identifier of the plan
     * @param _value Amount of credits to burn
     * @param _keyspace The keyspace of the nonce used to generate the signature
     * @param _signature The signature of the credits burn proof
     * @dev Inherits redemption permission checks from NFT1155Base
     */
    function burn(address _from, uint256 _planId, uint256 _value, uint256 _keyspace, bytes calldata _signature)
        public
        virtual
        override
    {
        super.burn(_from, _planId, _value, _keyspace, _signature);
    }

    /**
     * @notice Burns multiple credits from multiple plans in a single transaction
     * @param _from Address from which credits will be burned
     * @param _ids Array of plan identifiers
     * @param _values Array of credit amounts to burn
     * @param _keyspace The keyspace of the nonce used to generate the signature
     * @param _signature The signature of the credits burn proof
     * @dev Inherits redemption permission checks from NFT1155Base
     */
    function burnBatch(
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        uint256 _keyspace,
        bytes calldata _signature
    ) public virtual override {
        super.burnBatch(_from, _ids, _values, _keyspace, _signature);
    }

    /**
     * @notice Internal initialization function for NFT1155Credits
     * @param _authority Address of the AccessManager contract
     * @param _assetsRegistryAddress Address of the AssetsRegistry contract
     * @dev Called by the initialize function
     */
    // solhint-disable-next-line func-name-mixedcase
    function __NFT1155Credits_init(IAccessManager _authority, IAsset _assetsRegistryAddress) internal onlyInitializing {
        __NFT1155Base_init(_authority, _assetsRegistryAddress);
    }
}
