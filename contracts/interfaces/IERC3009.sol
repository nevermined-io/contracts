// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/**
 * @title IERC3009
 * @author Nevermined AG
 * @notice Minimal interface for the EIP-3009 `receiveWithAuthorization` flow used by the
 *         Nevermined gasless payment path. EIP-3009 lets a token holder authorize a transfer
 *         with an off-chain signature; `receiveWithAuthorization` additionally requires the
 *         payee (`to`) to be the caller, which prevents front-running and lets a contract
 *         recipient (the PaymentsVault) pull the funds atomically.
 * @dev Implemented natively by Circle's USDC and EURC (FiatTokenV2+). Tokens that only expose
 *      EIP-2612 `permit` are not compatible with this path.
 */
interface IERC3009 {
    /**
     * @notice The buyer-supplied portion of an EIP-3009 authorization signature.
     * @dev The protocol fixes the remaining EIP-3009 fields itself for safety: `from` is the
     *      buyer, `to` is the PaymentsVault, `value` is the plan's fee-inclusive total, and
     *      `nonce` is bound to the agreementId. Only the validity window and signature are
     *      provided by the caller.
     * @param validAfter Unix timestamp; the authorization is invalid at or before this time.
     * @param validBefore Unix timestamp; the authorization is invalid at or after this time.
     * @param v ECDSA signature recovery byte.
     * @param r ECDSA signature r value.
     * @param s ECDSA signature s value.
     */
    struct ReceiveAuthorization {
        uint256 validAfter;
        uint256 validBefore;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Executes a transfer of `value` from `from` to `to` authorized by an EIP-3009 signature.
     * @dev MUST revert unless `to == msg.sender`. MUST verify the signature, the validity window,
     *      and that the nonce is unused, then mark the nonce as used.
     * @param from The token holder authorizing the transfer (the recovered signer).
     * @param to The payee; must equal the caller.
     * @param value The amount of tokens to transfer.
     * @param validAfter The authorization is invalid at or before this Unix timestamp.
     * @param validBefore The authorization is invalid at or after this Unix timestamp.
     * @param nonce Unique per-authorization nonce (single-use), chosen by the signer.
     * @param v ECDSA signature recovery byte.
     * @param r ECDSA signature r value.
     * @param s ECDSA signature s value.
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
