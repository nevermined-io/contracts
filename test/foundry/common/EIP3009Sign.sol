// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

import {MockEIP3009Token} from '../../../contracts/test/MockEIP3009Token.sol';

/// @notice Shared test helper for building EIP-3009 `ReceiveWithAuthorization` digests.
/// @dev Centralises the EIP-712 digest construction so the authorization tests do not each
///      re-implement (and risk diverging on) the typed-data hashing. Callers sign the returned
///      digest with `vm.sign`.
library EIP3009Sign {
    /// @notice Builds the EIP-712 digest a payer signs to authorize `token.receiveWithAuthorization`.
    /// @param token The EIP-3009 token whose domain separator and typehash are used.
    /// @param from The payer authorizing the transfer (the signer).
    /// @param to The payee that will receive the funds (must equal the caller of receiveWithAuthorization).
    /// @param value The amount being authorized.
    /// @param validAfter Unix timestamp; the authorization is invalid at or before this time.
    /// @param validBefore Unix timestamp; the authorization is invalid at or after this time.
    /// @param nonce Single-use authorization nonce.
    /// @return The EIP-712 digest to sign.
    function receiveDigest(
        MockEIP3009Token token,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(token.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(), from, to, value, validAfter, validBefore, nonce)
        );
        return keccak256(abi.encodePacked('\x19\x01', token.DOMAIN_SEPARATOR(), structHash));
    }
}
