// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IFeeController} from './IFeeController.sol';

/**
 * @title Nevermined Configuration Interface
 * @author Nevermined AG
 * @notice Interface defining the core configuration management functionality for the Nevermined Protocol
 * @dev This interface establishes the contract functions and events required for maintaining
 * protocol-wide configuration, managing roles, and controlling access to administrative features
 */
interface INVMConfig {
    /**
     * @notice Event that is emitted when a configuration parameter is changed
     * @param whoChanged The address of the governor changing the parameter
     * @param parameter The hash of the name of the parameter changed
     * @param value The new value of the parameter
     */
    event NeverminedConfigChange(address indexed whoChanged, bytes32 indexed parameter, bytes value);

    /**
     * @notice Error thrown when an invalid default fee controller address is provided in an agreement creation process
     * @dev The default fee controller address must be a valid address
     */
    error InvalidDefaultFeeControllerAddress();

    /**
     * @notice Error thrown when an invalid fee receiver address is provided
     * @dev The fee receiver cannot be the zero address when fees are enabled
     * @param feeReceiver The invalid fee receiver address that was provided
     */
    error InvalidFeeReceiver(address feeReceiver);

    /**
     * @notice Error thrown when an invalid address is provided to a function
     * @param _address The invalid address that was provided
     */
    error InvalidAddress(address _address);

    /**
     * @notice Error thrown when an invalid input length is provided
     */
    error InvalidInputLength();

    /**
     * @notice Retrieves the address that receives protocol fees
     * @dev If this returns the zero address and fees are set, fees cannot be collected
     * @return The current fee receiver address
     */
    function getFeeReceiver() external view returns (address);

    /**
     * @notice Sets the fee receiver address for the Nevermined protocol
     * @dev Only a governor address can call this function
     * @dev Emits NeverminedConfigChange events for both fee and receiver updates
     *
     * @param _feeReceiver The address that will receive collected fees
     */
    function setFeeReceiver(address _feeReceiver) external;

    /**
     * @notice Sets a parameter in the Nevermined configuration
     * @dev Only an account with GOVERNOR_ROLE can call this function
     * @dev Emits NeverminedConfigChange event on parameter update
     * @dev Parameters are generic key-value pairs that can store any configuration data
     *
     * @param _paramName The name/key of the parameter to set (as bytes32)
     * @param _value The value to set for the parameter (as arbitrary bytes)
     */
    function setParameter(bytes32 _paramName, bytes memory _value) external;

    /**
     * @notice Retrieves a parameter from the Nevermined configuration
     * @dev Returns the complete parameter entry including value, status and timestamp
     *
     * @param _paramName The name/key of the parameter to retrieve (as bytes32)
     * @return value The parameter's raw bytes value
     * @return isActive Whether the parameter is currently active
     * @return lastUpdated Timestamp of when the parameter was last updated
     */
    function getParameter(bytes32 _paramName)
        external
        view
        returns (bytes memory value, bool isActive, uint256 lastUpdated);

    /**
     * @notice Disables a parameter in the Nevermined configuration
     * @dev Only an account with GOVERNOR_ROLE can call this function
     * @dev Emits NeverminedConfigChange event on parameter update
     * @dev Does nothing if the parameter is already inactive
     *
     * @param _paramName The name/key of the parameter to disable (as bytes32)
     */
    function disableParameter(bytes32 _paramName) external;

    /**
     * @notice Checks if a parameter exists in the Nevermined configuration
     * @dev Returns true if the parameter exists, false otherwise
     *
     * @param _paramName The name/key of the parameter to check (as bytes32)
     * @return bool True if the parameter exists, false otherwise
     */
    function parameterExists(bytes32 _paramName) external view returns (bool);

    /**
     * @notice Emitted when a fee controller is allowed or disallowed for a creator
     * @param feeControllerAddresses Array of fee controller addresses
     * @param creator Array of creator addresses
     * @param allowed Array of boolean values indicating if the fee controller is allowed for the creator
     */
    event FeeControllerAllowedUpdated(
        IFeeController[] indexed feeControllerAddresses, address[][] creator, bool[][] allowed
    );

    /**
     * @notice Sets the default fee controller for the Nevermined protocol
     * @param _defaultFeeController The address of the default fee controller contract
     */
    function setDefaultFeeController(IFeeController _defaultFeeController) external;

    /**
     * @notice Gets the default fee controller contract
     * @return The address of the default fee controller contract
     */
    function getDefaultFeeController() external view returns (IFeeController);

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
    ) external;

    /**
     * @notice Gets whether a fee controller is allowed for a creator
     * @param _feeController The fee controller to check
     * @param _creator The creator address to check
     * @return bool True if the fee controller is allowed for the creator
     */
    function isFeeControllerAllowed(IFeeController _feeController, address _creator) external view returns (bool);
}
