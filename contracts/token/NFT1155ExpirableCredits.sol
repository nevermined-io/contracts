// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {NFT1155Base} from './NFT1155Base.sol';
import {ERC1155Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title NFT1155ExpirableCredits
 * @author Nevermined
 * @notice Implementation of ERC1155 credits with expiration functionality for the Nevermined ecosystem
 * @dev This contract extends NFT1155Base to implement credit tokens that can expire after a specified duration.
 * It provides detailed tracking of when credits were minted and when they expire, with a sophisticated
 * balance calculation system that accounts for expired credits.
 *
 * Each credit entry tracks:
 * - The amount minted or burned
 * - The timestamp when the operation occurred
 * - The expiration duration in seconds (0 for non-expiring credits)
 * - Whether the operation was a mint or burn
 *
 * This contract inherits permissions management from NFT1155Base but implements custom
 * balance calculation logic to exclude expired credits.
 */
contract NFT1155ExpirableCredits is NFT1155Base {
    // keccak256(abi.encode(uint256(keccak256("nevermined.nft1155expirablecredits.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFT1155_EXPIRABLE_CREDITS_STORAGE_LOCATION =
        0xad13115e659bb74b20198931946852537615445c0d1e91655e57181f5cb10400;

    error NotEnoughCreditsToBurn(address _from, uint256 _planId, uint256 _value);

    /**
     * @notice Struct to track minted credits and their expiration details
     * @param amountMinted Number of credits minted or burned in this operation
     * @param expirationSecs Duration in seconds before the credits expire (0 means they never expire)
     * @param mintTimestamp Timestamp when the credits were minted or burned
     * @param isMintOps True for minting operation, false for burning operation
     */
    struct MintedCredits {
        uint256 amountMinted; // uint64
        uint256 expirationSecs;
        uint256 mintTimestamp;
        bool isMintOps; // true means mint, false means burn
    }

    /// @custom:storage-location erc7201:nevermined.nft1155expirablecredits.storage
    struct NFT1155ExpirableCreditsStorage {
        mapping(bytes32 => MintedCredits[]) credits;
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
        bytes32 _key = _getTokenKey(_to, _planId);

        _getNFT1155ExpirableCreditsStorage()
        .credits[_key].push(MintedCredits(_value, _secsDuration, block.timestamp, true));

        super.mint(_to, _planId, _value, _data);
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

    function _processPreCreditBurn(address _from, uint256 _planId, uint256 _value) internal {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        bytes32 _key = _getTokenKey(_from, _planId);
        uint256 _pendingToBurn = _value;

        uint256 _numEntries = $.credits[_key].length;
        for (uint256 index = 0; index < _numEntries; index++) {
            MintedCredits storage entry = $.credits[_key][index];

            // If the entry is a burn operation, we skip it
            if (!entry.isMintOps) {
                continue;
            }

            if (entry.expirationSecs == 0 || block.timestamp < (entry.mintTimestamp + entry.expirationSecs)) {
                if (_pendingToBurn <= entry.amountMinted) {
                    $.credits[_key].push(MintedCredits(_pendingToBurn, entry.expirationSecs, block.timestamp, false));
                    _pendingToBurn = 0;
                    break;
                } else {
                    _pendingToBurn -= entry.amountMinted;
                    $.credits[_key].push(
                        MintedCredits(entry.amountMinted, entry.expirationSecs, block.timestamp, false)
                    );
                }
            }
        }

        require(_pendingToBurn == 0, NotEnoughCreditsToBurn(_from, _planId, _value));
    }

    /**
     * @notice Gets the current balance of credits for a specific owner and plan
     * @param _owner Address of the credits owner
     * @param _planId Identifier of the plan
     * @return The current balance of non-expired credits
     * @dev Calculates balance by tracking minted and burned credits, considering expiration
     */
    function balanceOf(address _owner, uint256 _planId) public view virtual override returns (uint256) {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        bytes32 _key = _getTokenKey(_owner, _planId);
        uint256 _amountBurned;
        uint256 _amountMinted;

        uint256 _length = $.credits[_key].length;
        for (uint256 index = 0; index < _length; index++) {
            if (
                $.credits[_key][index].mintTimestamp > 0
                    && ($.credits[_key][index].expirationSecs == 0
                        || block.timestamp
                            < ($.credits[_key][index].mintTimestamp + $.credits[_key][index].expirationSecs))
            ) {
                if ($.credits[_key][index].isMintOps) {
                    _amountMinted += $.credits[_key][index].amountMinted;
                } else {
                    _amountBurned += $.credits[_key][index].amountMinted;
                }
            }
        }

        if (_amountBurned >= _amountMinted) return 0;
        else return _amountMinted - _amountBurned;
    }

    /**
     * @notice Gets the timestamps when credits were minted for a specific owner and plan
     * @param _owner Address of the credits owner
     * @param _planId Identifier of the plan
     * @return Array of timestamps when credits were minted
     * @dev Useful for auditing purposes and tracking credit history
     */
    function whenWasMinted(address _owner, uint256 _planId) external view returns (uint256[] memory) {
        NFT1155ExpirableCreditsStorage storage $ = _getNFT1155ExpirableCreditsStorage();

        bytes32 _key = _getTokenKey(_owner, _planId);
        uint256 _length = $.credits[_key].length;

        uint256[] memory _whenMinted = new uint256[](_length);
        for (uint256 index = 0; index < _length; index++) {
            _whenMinted[index] = $.credits[_key][index].mintTimestamp;
        }
        return _whenMinted;
    }

    /**
     * @notice Gets all minted credit entries for a specific owner and plan
     * @param _owner Address of the credits owner
     * @param _planId Identifier of the plan
     * @return Array of MintedCredits structures containing detailed minting information
     * @dev Provides complete historical data for all credit operations for a user and plan
     */
    function getMintedEntries(address _owner, uint256 _planId) external view returns (MintedCredits[] memory) {
        return _getNFT1155ExpirableCreditsStorage().credits[_getTokenKey(_owner, _planId)];
    }

    /**
     * @notice Internal function to generate a unique key for tracking credits
     * @param _account Address of the credits owner
     * @param _planId Identifier of the plan
     * @return A unique bytes32 key generated from the account and plan ID
     * @dev Used as a mapping key to store credit entries for each user-plan combination
     */
    function _getTokenKey(address _account, uint256 _planId) internal pure returns (bytes32) {
        return keccak256(abi.encode(_account, _planId));
    }

    /**
     * @notice Access function for the contract's storage
     * @return $ Reference to the contract's storage struct
     * @dev Uses diamond storage pattern with ERC-7201 namespacing
     */
    function _getNFT1155ExpirableCreditsStorage() internal pure returns (NFT1155ExpirableCreditsStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NFT1155_EXPIRABLE_CREDITS_STORAGE_LOCATION
        }
    }
}
