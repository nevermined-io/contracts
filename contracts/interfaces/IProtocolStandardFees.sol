// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {IFeeController} from './IFeeController.sol';
import {IAccessManager} from '@openzeppelin/contracts/access/manager/IAccessManager.sol';

interface IProtocolStandardFees is IFeeController {
    error InvalidFeeRate();

    function initialize(IAccessManager _authority) external;
    function updateFeeRates(uint256 _cryptoFeeRate, uint256 _fiatFeeRate) external;
    function getFeeRates() external view returns (uint256 cryptoFeeRate, uint256 fiatFeeRate, uint256 feeDenominator);
}
