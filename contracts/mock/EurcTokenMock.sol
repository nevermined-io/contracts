// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {FiatTokenMock} from './FiatTokenMock.sol';

/**
 * @title EurcTokenMock
 * @notice Stand-in for Circle's EURC on a local anvil, injected at EURC's
 *         CANONICAL Base Sepolia address by the pre-baked chain image build.
 *
 * Identical to `FiatTokenMock` in every respect that matters mechanically — the
 * slot-9 balance layout, the 255-bit mask, 6 decimals (EURC and USDC share all
 * three) — and differs only in `name`/`symbol`, so a human reading a trace or a
 * block explorer is not told the token at EURC's address is USDC.
 *
 * ── Why this exists ─────────────────────────────────────────────────────────
 * The API hardcodes EURC per chain in `EURC_ADDRESSES`
 * (`apps/api/src/common/helpers/utils.ts`) and the EIP-7702 wallet migration
 * sweeps balances, so it calls `balanceOf` on EURC for **every** user. Before
 * this mock, the image carried EURC's real *proxy* runtime code with a zeroed
 * implementation slot: a delegatecall to `address(0)` returns success with empty
 * returndata, viem raises `returned no data ("0x")`, migration failed, and all
 * four `webapp-e2e` shards timed out waiting for `walletMode=eip7702`.
 *
 * Note that `external-fork` passes with that bug present — it never exercises
 * the sweep — so a green external suite does not vouch for this token.
 *
 * The 6-decimals claim is deliberate and not inherited by accident: it comes
 * from `FiatTokenMock.decimals()`, which is `pure` and non-virtual precisely
 * because a divergence here would silently mis-scale every EURC amount.
 */
contract EurcTokenMock is FiatTokenMock {
    function name() external pure override returns (string memory) {
        return 'Euro Coin';
    }

    function symbol() external pure override returns (string memory) {
        return 'EURC';
    }
}
