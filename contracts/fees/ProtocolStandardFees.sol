// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IAsset} from '../interfaces/IAsset.sol';
import {IProtocolStandardFees} from '../interfaces/IProtocolStandardFees.sol';
import {AccessManagedUUPSUpgradeable} from '../proxy/AccessManagedUUPSUpgradeable.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

/**
 * @title ProtocolStandardFees
 * @author Nevermined AG
 * @notice Default fee controller that applies standard protocol fees based on price type
 */
contract ProtocolStandardFees is IProtocolStandardFees, AccessManagedUUPSUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("nevermined.protocolstandardfees.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PROTOCOL_STANDARD_FEES_STORAGE_LOCATION =
        0x0d784bb8b76bb03d4f7da8f1a5de7ac267beddd13f33d8a855f72ce8098dc700;

    /// @custom:storage-location erc7201:nevermined.protocolstandardfees.storage
    struct ProtocolStandardFeesStorage {
        uint256 cryptoFeeRate; // Fee rate for crypto payments (in basis points)
        uint256 fiatFeeRate; // Fee rate for fiat payments (in basis points)
        uint256 feeDenominator; // Denominator for fee calculations (e.g., 10000 for basis points)
    }

    event FeeRatesUpdated(uint256 cryptoFeeRate, uint256 fiatFeeRate);

    /**
     * @notice Initializes the contract with default fee rates
     * @param _authority Address of the AccessManager contract handling permissions
     */
    function initialize(IAccessManager _authority) external override initializer {
        ProtocolStandardFeesStorage storage $ = _getProtocolStandardFeesStorage();
        $.cryptoFeeRate = 100; // 1%
        $.fiatFeeRate = 200; // 2%
        $.feeDenominator = 10000; // Basis points
        __AccessManagedUUPSUpgradeable_init(address(_authority));
    }

    /**
     * @notice Updates the fee rates for crypto and fiat payments
     * @param _cryptoFeeRate New fee rate for crypto payments (in basis points)
     * @param _fiatFeeRate New fee rate for fiat payments (in basis points)
     * @dev Only callable by the governor
     */
    function updateFeeRates(uint256 _cryptoFeeRate, uint256 _fiatFeeRate) external override restricted {
        ProtocolStandardFeesStorage storage $ = _getProtocolStandardFeesStorage();
        require(_cryptoFeeRate <= $.feeDenominator && _fiatFeeRate <= $.feeDenominator, InvalidFeeRate());
        $.cryptoFeeRate = _cryptoFeeRate;
        $.fiatFeeRate = _fiatFeeRate;
        emit FeeRatesUpdated(_cryptoFeeRate, _fiatFeeRate);
    }

    /**
     * @notice Calculates the fee for a given plan based on its price type
     * @param totalAmount The total amount to calculate the fee for
     * @param priceConfig The price configuration of the plan
     * @return fee The calculated fee amount
     * @return feeRate The fee rate applied
     * @return feeDenominator The denominator used for fee calculation
     */
    function calculateFee(uint256 totalAmount, IAsset.PriceConfig calldata priceConfig, IAsset.CreditsConfig calldata)
        external
        view
        override
        returns (uint256 fee, uint256 feeRate, uint256 feeDenominator)
    {
        ProtocolStandardFeesStorage storage $ = _getProtocolStandardFeesStorage();

        if (priceConfig.isCrypto) {
            if (priceConfig.externalPriceAddress != address(0)) feeRate = 0;
            else feeRate = $.cryptoFeeRate;
        } else {
            feeRate = $.fiatFeeRate;
        }

        // Calculate fee amount
        return ((totalAmount * feeRate) / $.feeDenominator, feeRate, $.feeDenominator);
    }

    /**
     * @notice Gets the current fee rates
     * @return cryptoFeeRate Current fee rate for crypto payments
     * @return fiatFeeRate Current fee rate for fiat payments
     * @return feeDenominator Current fee denominator
     */
    function getFeeRates()
        external
        view
        override
        returns (uint256 cryptoFeeRate, uint256 fiatFeeRate, uint256 feeDenominator)
    {
        ProtocolStandardFeesStorage storage $ = _getProtocolStandardFeesStorage();
        return ($.cryptoFeeRate, $.fiatFeeRate, $.feeDenominator);
    }

    /**
     * @notice Accesses the contract's namespaced storage slot using ERC-7201
     * @return $ Reference to the contract's storage struct
     */
    function _getProtocolStandardFeesStorage() internal pure returns (ProtocolStandardFeesStorage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly ('memory-safe') {
            $.slot := PROTOCOL_STANDARD_FEES_STORAGE_LOCATION
        }
    }
}
