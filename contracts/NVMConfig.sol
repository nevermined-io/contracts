// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IFeeController} from './interfaces/IFeeController.sol';
import {INVMConfig} from './interfaces/INVMConfig.sol';
import {AccessManagedUUPSUpgradeable} from './proxy/AccessManagedUUPSUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title Nevermined Config contract
 * @author Nevermined AG
 * @notice This contract serves as the central configuration registry for the Nevermined Protocol
 * @dev NVMConfig implements the following functionality:
 * - Role-based access control for configuration management
 * - Storage for protocol-wide configuration parameters
 * - Registration of contract addresses within the Nevermined ecosystem
 * - Management of network fees collected by the protocol
 *
 * The contract uses OpenZeppelin's AccessControl for role management and
 * implements UUPS (Universal Upgradeable Proxy Standard) pattern for upgradeability.
 */
contract NVMConfig is INVMConfig, AccessManagedUUPSUpgradeable {
    // Storage slot for the NVM configuration namespace following ERC-7201 standard
    // keccak256(abi.encode(uint256(keccak256("nevermined.nvmconfig.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NVM_CONFIG_STORAGE_LOCATION =
        0xd8dc47a566e10bab714c93f5587c29375a3dcfd68f88494af6f1cf90589ce900;

    /**
     * @title ParamEntry
     * @notice Represents a configuration parameter in the Nevermined ecosystem
     * @dev This struct stores all relevant information about a configuration parameter
     * @param value The raw bytes value of the parameter that can be decoded by the consumer
     * @param isActive Flag indicating if the parameter is currently active
     * @param lastUpdated Timestamp of when the parameter was last modified
     */
    struct ParamEntry {
        bytes value;
        bool isActive;
        uint256 lastUpdated;
    }

    /// @custom:storage-location erc7201:nevermined.nvmconfig.storage
    /**
     * @title NVMConfigStorage
     * @notice Main storage structure for the Nevermined configuration
     * @dev Uses ERC-7201 for namespaced storage pattern to prevent storage collisions during upgrades
     */
    struct NVMConfigStorage {
        /**
         * @notice Stores all configuration parameters of the protocol
         * @dev Maps parameter names (as bytes32) to their corresponding ParamEntry
         */
        mapping(bytes32 => ParamEntry) configParams;
        /////// NEVERMINED GOVERNABLE VARIABLES ////////////////////////////////////////////////
        /**
         * @notice The address that receives protocol fees
         * @dev This address collects all fees from service agreement executions
         */
        address feeReceiver;
        /**
         * @notice Default fee controller to use when plan's controller is zero
         */
        IFeeController defaultFeeController;
        /**
         * @notice Mapping of fee controller to creator to check if the fee controller is allowed to set the plan fee controller
         */
        mapping(IFeeController => mapping(address => bool)) isFeeControllerAllowed;
    }

    /**
     * @notice Initialization function. Sets up the contract with initial roles and permissions
     * @dev This function can only be called once when the proxy contract is initialized
     * @param _authority The access manager contract that will control upgrade permissions
     */
    function initialize(IAccessManager _authority, IFeeController _defaultFeeController) external initializer {
        require(_authority != IAccessManager(address(0)), InvalidAddress(address(0)));
        require(_defaultFeeController != IFeeController(address(0)), InvalidDefaultFeeControllerAddress());

        _getNVMConfigStorage().defaultFeeController = _defaultFeeController;
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    ///////////////////////////////////////////////////////////////////////////////////////
    /////// CONFIG FUNCTIONS //////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Sets the fee receiver address for the Nevermined protocol
     * @dev Only a governor address can call this function
     * @dev Emits NeverminedConfigChange events for both fee and receiver updates
     *
     * @param _feeReceiver The address that will receive collected fees
     *
     * @custom:error InvalidNetworkFee Thrown if the fee is outside the valid range (0-1,000,000)
     * @custom:error InvalidFeeReceiver Thrown if a fee is set but the receiver is the zero address
     */
    function setFeeReceiver(address _feeReceiver) external virtual override restricted {
        NVMConfigStorage storage $ = _getNVMConfigStorage();

        if (_feeReceiver == address(0)) {
            revert InvalidFeeReceiver(_feeReceiver);
        }

        $.feeReceiver = _feeReceiver;
        emit NeverminedConfigChange(msg.sender, keccak256('feeReceiver'), abi.encodePacked(_feeReceiver));
    }

    /**
     * @notice Retrieves the address that receives protocol fees
     * @dev If this returns the zero address and fees are set, fees cannot be collected
     * @return The current fee receiver address
     */
    function getFeeReceiver() external view override returns (address) {
        return _getNVMConfigStorage().feeReceiver;
    }

    /**
     * @notice Checks if the caller has a specific role in the Nevermined protocol
     * @dev If this returns true it means the caller has the specified role
     * @return Whether the caller has the specified role
     */
    function haveRole(uint64 roleId) external view returns (bool) {
        (bool hasRole,) = IAccessManager(authority()).hasRole(roleId, msg.sender);
        return hasRole;
    }

    /**
     * @notice Sets a parameter in the Nevermined configuration
     * @dev Only an account with GOVERNOR_ROLE can call this function
     * @dev Emits NeverminedConfigChange event on parameter update
     * @dev Parameters are generic key-value pairs that can store any configuration data
     *
     * @param _paramName The name/key of the parameter to set (as bytes32)
     * @param _value The value to set for the parameter (as arbitrary bytes)
     */
    function setParameter(bytes32 _paramName, bytes memory _value) external virtual override restricted {
        NVMConfigStorage storage $ = _getNVMConfigStorage();

        $.configParams[_paramName].value = _value;
        $.configParams[_paramName].isActive = true;
        $.configParams[_paramName].lastUpdated = block.timestamp;
        emit NeverminedConfigChange(msg.sender, _paramName, _value);
    }

    /**
     * @notice Retrieves a parameter from the Nevermined configuration
     * @dev Returns the complete parameter entry including value, status and timestamp
     *
     * @param _paramName The name/key of the parameter to retrieve
     * @return value The parameter's raw bytes value
     * @return isActive Whether the parameter is currently active
     * @return lastUpdated Timestamp of when the parameter was last updated
     */
    function getParameter(bytes32 _paramName)
        external
        view
        override
        returns (bytes memory value, bool isActive, uint256 lastUpdated)
    {
        NVMConfigStorage storage $ = _getNVMConfigStorage();

        return
            (
                $.configParams[_paramName].value,
                $.configParams[_paramName].isActive,
                $.configParams[_paramName].lastUpdated
            );
    }

    /**
     * @notice Disables a parameter in the Nevermined configuration
     * @dev Only an account with GOVERNOR_ROLE can call this function
     * @dev Emits NeverminedConfigChange event on parameter update
     * @dev Does nothing if the parameter is already inactive
     *
     * @param _paramName The name/key of the parameter to disable
     */
    function disableParameter(bytes32 _paramName) external virtual override restricted {
        NVMConfigStorage storage $ = _getNVMConfigStorage();

        if ($.configParams[_paramName].isActive) {
            $.configParams[_paramName].isActive = false;
            $.configParams[_paramName].lastUpdated = block.timestamp;
            emit NeverminedConfigChange(msg.sender, _paramName, $.configParams[_paramName].value);
        }
    }

    /**
     * @notice Checks if a parameter exists and is active in the Nevermined configuration
     * @dev A parameter is considered to exist only if it is marked as active
     *
     * @param _paramName The name/key of the parameter to check
     * @return Boolean indicating whether the parameter exists and is active
     */
    function parameterExists(bytes32 _paramName) external view override returns (bool) {
        return _getNVMConfigStorage().configParams[_paramName].isActive;
    }

    /**
     * @notice Sets the default fee controller for the Nevermined protocol
     * @dev Only a governor address can call this function
     * @param _defaultFeeController The address of the default fee controller contract
     */
    function setDefaultFeeController(IFeeController _defaultFeeController) external virtual override restricted {
        NVMConfigStorage storage $ = _getNVMConfigStorage();
        $.defaultFeeController = _defaultFeeController;
        emit NeverminedConfigChange(
            msg.sender, keccak256('defaultFeeController'), abi.encodePacked(address(_defaultFeeController))
        );
    }

    /**
     * @notice Gets the default fee controller contract
     * @return The address of the default fee controller contract
     */
    function getDefaultFeeController() external view override returns (IFeeController) {
        return _getNVMConfigStorage().defaultFeeController;
    }

    /**
     * @notice Sets the fee controller allowed status for creators
     * @param _feeControllerAddresses Array of fee controller addresses
     * @param _creator Array of creator addresses
     * @param _allowed Array of boolean values indicating if the fee controller is allowed for the creator
     */
    function setFeeControllerAllowed(
        IFeeController[] calldata _feeControllerAddresses,
        address[][] calldata _creator,
        bool[][] calldata _allowed
    ) external virtual override restricted {
        require(_feeControllerAddresses.length == _creator.length, InvalidInputLength());
        require(_feeControllerAddresses.length == _allowed.length, InvalidInputLength());

        NVMConfigStorage storage $ = _getNVMConfigStorage();

        for (uint256 i = 0; i < _feeControllerAddresses.length; i++) {
            require(_creator[i].length == _allowed[i].length, InvalidInputLength());
            for (uint256 j = 0; j < _creator[i].length; j++) {
                $.isFeeControllerAllowed[_feeControllerAddresses[i]][_creator[i][j]] = _allowed[i][j];
            }
        }

        emit FeeControllerAllowedUpdated(_feeControllerAddresses, _creator, _allowed);
    }

    /**
     * @notice Gets whether a fee controller is allowed for a creator
     * @param _feeController The fee controller to check
     * @param _creator The creator address to check
     * @return bool True if the fee controller is allowed for the creator
     */
    function isFeeControllerAllowed(IFeeController _feeController, address _creator)
        external
        view
        override
        returns (bool)
    {
        return _getNVMConfigStorage().isFeeControllerAllowed[_feeController][_creator];
    }

    /**
     * @notice Internal function to access the contract's namespaced storage
     * @dev Uses ERC-7201 storage pattern to prevent storage collisions during upgrades
     * @return $ A reference to the NVMConfigStorage struct at the designated storage slot
     */
    function _getNVMConfigStorage() internal pure returns (NVMConfigStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := NVM_CONFIG_STORAGE_LOCATION
        }
    }
}
