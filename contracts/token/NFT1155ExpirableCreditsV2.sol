// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {NFT1155Base} from './NFT1155Base.sol';

import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {RedBlackTreeLib} from 'lib/solady/src/utils/RedBlackTreeLib.sol';

/**
 * @title NFT1155ExpirableCredits
 * @author Nevermined
 * @notice Implementation of ERC1155 credits with expiration functionality for the Nevermined ecosystem
 * @dev This contract extends NFT1155Base to implement credit tokens that can expire after a specified duration.
 */
contract NFT1155ExpirableCreditsV2 is NFT1155Base {
    using RedBlackTreeLib for RedBlackTreeLib.Tree;

    // keccak256(abi.encode(uint256(keccak256("nevermined.nft1155expirablecreditsv2.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFT1155_EXPIRABLE_CREDITS_V2_STORAGE_LOCATION =
        0xf44ce29990440f027976fdc0785fc371c768d4fd23adb636fb6dddc381f40200;

    event Minted(address indexed _to, uint256 _planId, uint256 _value, uint256 _expiration);
    event Burned(address indexed _from, uint256 _planId, uint256 _value, uint256 _expiration);

    error NotEnoughCreditsToBurn(address _from, uint256 _planId, uint256 _value);

    struct CreditsLedger {
        RedBlackTreeLib.Tree expirations;
        mapping(uint256 expiration => uint256 amount) amounts;
    }

    /// @custom:storage-location erc7201:nevermined.nft1155expirablecreditsv2.storage
    struct NFT1155ExpirableCreditsStorage {
        mapping(address account => mapping(uint256 planId => CreditsLedger ledger)) ledgers;
    }

    /**
     * @notice Initializes the NFT1155ExpirableCredits contract with required dependencies
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
        virtual
        initializer
    {
        ERC1155Upgradeable.__ERC1155_init('');
        __NFT1155Base_init(_authority, _assetsRegistryAddress);
    }

    /**
     * @notice Mints credits for a specific plan with no expiration
     * @param _to Address that will receive the credits
     * @param _planId Identifier of the plan
     * @param _value Amount of credits to mint
     * @param _data Additional data to pass to the receiver
     * @dev Delegates to the overloaded mint function with 0 expiration duration
     */
    function mint(address _to, uint256 _planId, uint256 _value, bytes memory _data) public virtual override {
        mint(_to, _planId, _value, 0, _data);
    }

    /**
     * @notice Mints credits with an expiration duration for a specific plan
     * @param _to Address that will receive the credits
     * @param _planId Identifier of the plan
     * @param _value Amount of credits to mint
     * @param _secsDuration Duration in seconds before the credits expire (0 for non-expiring)
     * @param _data Additional data to pass to the receiver
     * @dev Records the minting operation with timestamp and expiration information
     */
    function mint(address _to, uint256 _planId, uint256 _value, uint256 _secsDuration, bytes memory _data)
        public
        virtual
    {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        CreditsLedger storage ledger = $.ledgers[_to][_planId];

        // Handle non-expiring credits (0 duration means never expire)
        uint256 expiration;
        if (_secsDuration == 0) {
            // For non-expiring credits, use a very large timestamp
            expiration = type(uint256).max;
        } else {
            expiration = block.timestamp + _secsDuration;
        }

        // Insert the expiration into the ledger if it's not already there
        if (!ledger.expirations.exists(expiration)) {
            ledger.expirations.insert(expiration);
        }

        // Update the amount of credits that will expire at the given expiration
        ledger.amounts[expiration] += _value;

        super.mint(_to, _planId, _value, _data);

        emit Minted(_to, _planId, _value, expiration);
    }

    /**
     * @notice Mints credits for multiple plans with no expiration
     * @param _to Address that will receive the credits
     * @param _ids Array of plan identifiers
     * @param _values Array of credit amounts to mint
     * @param _data Additional data to pass to the receiver
     * @dev Delegates to the overloaded mintBatch function with all zero expiration durations
     */
    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _values, bytes memory _data)
        public
        virtual
        override
    {
        uint256 _length = _ids.length;
        uint256[] memory _secsDurations = new uint256[](_length);

        mintBatch(_to, _ids, _values, _secsDurations, _data);
    }

    /**
     * @notice Mints multiple credits with expiration durations for multiple plans
     * @param _to Address that will receive the credits
     * @param _ids Array of plan identifiers
     * @param _values Array of credit amounts to mint
     * @param _secsDurations Array of durations in seconds before credits expire
     * @param _data Additional data to pass to the receiver
     * @dev Validates array lengths match before minting each credit batch
     */
    function mintBatch(
        address _to,
        uint256[] memory _ids,
        uint256[] memory _values,
        uint256[] memory _secsDurations,
        bytes memory _data
    ) public virtual {
        uint256 _length = _ids.length;
        if (_length != _values.length) revert InvalidLength(_length, _values.length);
        if (_length != _secsDurations.length) revert InvalidLength(_length, _secsDurations.length);

        for (uint256 i = 0; i < _length; i++) {
            mint(_to, _ids[i], _values[i], _secsDurations[i], _data);
        }
    }

    /**
     * @notice Burns credits from a specific plan, tracking the burn operation
     * @param _from Address from which credits will be burned
     * @param _planId Identifier of the plan
     * @param _value Amount of credits to burn
     * @param _keyspace The keyspace of the nonce used to generate the signature
     * @param _signature The signature of the credits burn proof
     * @dev Implements custom burn logic that records each burn operation against valid, non-expired credits
     */
    function burn(address _from, uint256 _planId, uint256 _value, uint256 _keyspace, bytes calldata _signature)
        public
        virtual
        override
    {
        _processPreCreditBurn(_from, _planId, _value);

        super.burn(_from, _planId, _value, _keyspace, _signature);
    }

    /**
     * @notice Burns multiple credits from multiple plans in a single transaction
     * @param _from Address from which credits will be burned
     * @param _ids Array of plan identifiers
     * @param _values Array of credit amounts to burn
     * @dev Validates array lengths match before burning each batch
     */
    function burnBatch(
        address _from,
        uint256[] memory _ids,
        uint256[] memory _values,
        uint256 _keyspace,
        bytes calldata _signature
    ) public virtual override restricted {
        uint256 _length = _ids.length;
        if (_length != _values.length) revert InvalidLength(_length, _values.length);

        for (uint256 i = 0; i < _length; i++) {
            _processPreCreditBurn(_from, _ids[i], _values[i]);
        }

        super.burnBatch(_from, _ids, _values, _keyspace, _signature);
    }

    /**
     * @notice Purges expired credits from the ledger
     * @param _from Address of the credits owner
     * @param _planId Identifier of the plan
     * @param _expirations Array of expirations to purge. This is provided explicitly in order to avoid DoS due to too many expired credit entries.
     * @dev Purges expired credits from the ledger
     */
    function purgeExpiredCredits(address _from, uint256 _planId, uint256[] calldata _expirations) external {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();
        CreditsLedger storage ledger = $.ledgers[_from][_planId];

        uint256 totalToBurn = 0;
        for (uint256 i = 0; i < _expirations.length; i++) {
            uint256 expiration = _expirations[i];
            require(expiration < block.timestamp, NotExpired(expiration));

            uint256 amount = ledger.amounts[expiration];
            totalToBurn += amount;
            require(amount > 0, NoCreditsToBurn(expiration));

            delete ledger.amounts[expiration];
            ledger.expirations.remove(expiration);

            emit Purged(_from, _planId, amount, expiration);
        }

        _burn(_from, _planId, totalToBurn);
    }

    function _processPreCreditBurn(address _from, uint256 _planId, uint256 _value) internal {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        CreditsLedger storage ledger = $.ledgers[_from][_planId];

        uint256 _pendingToBurn = _value;

        // Loop through the expirations and burn the credits in the order of expiration
        bytes32 ptr = ledger.expirations.nearestAfter(block.timestamp + 1);
        while (_pendingToBurn > 0 && ptr != bytes32(0)) {
            uint256 expiration = RedBlackTreeLib.value(ptr);
            uint256 availableCredits = ledger.amounts[expiration];
            uint256 creditsToBurn = Math.min(_pendingToBurn, availableCredits);
            unchecked {
                ledger.amounts[expiration] -= creditsToBurn;
                _pendingToBurn -= creditsToBurn;
            }

            // Find the next expiration and cache it
            bytes32 nextPtr = RedBlackTreeLib.next(ptr);

            // If all credits at this expiration have been burned, remove the expiration from the tree
            if (availableCredits == creditsToBurn) {
                RedBlackTreeLib.remove(ptr);
            }

            ptr = nextPtr;

            emit Burned(_from, _planId, creditsToBurn, expiration);
        }

        require(_pendingToBurn == 0, NotEnoughCreditsToBurn(_from, _planId, _value));
    }

    /**
     * @notice Gets the current balance of credits for a specific owner and plan
     * @param _owner Address of the credits owner
     * @param _planId Identifier of the plan
     * @return The current balance of non-expired credits
     */
    function balanceOf(address _owner, uint256 _planId) public view virtual override returns (uint256) {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        CreditsLedger storage ledger = $.ledgers[_owner][_planId];

        uint256 balance = 0;
        bytes32 ptr = ledger.expirations.nearestAfter(block.timestamp + 1);
        while (ptr != bytes32(0)) {
            uint256 expiration = RedBlackTreeLib.value(ptr);
            balance += ledger.amounts[expiration];
            ptr = RedBlackTreeLib.next(ptr);
        }

        return balance;
    }

    /**
     * @notice Access function for the contract's storage
     * @return $ Reference to the contract's storage struct
     * @dev Uses diamond storage pattern with ERC-7201 namespacing
     */
    function _getNFT1155ExpirableCreditsStorage() internal pure returns (NFT1155ExpirableCreditsStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NFT1155_EXPIRABLE_CREDITS_V2_STORAGE_LOCATION
        }
    }
}
