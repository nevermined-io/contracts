// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

library TokenUtils {
    /// Error sending native token (i.e ETH)
    error FailedToSendNativeToken();

    /// The msg.value (`msgValue`) doesn't match the amount (`amount`)
    /// @param msgValue The value sent in the transaction
    /// @param amount The amount to be transferred
    error InvalidTransactionAmount(uint256 msgValue, uint256 amount);

    function calculateAmountSum(uint256[] memory _amounts) public pure returns (uint256) {
        uint256 _totalAmount;
        uint256 length = _amounts.length;
        for (uint256 i; i < length; i++) {
            _totalAmount += _amounts[i];
        }
        return _totalAmount;
    }
}
