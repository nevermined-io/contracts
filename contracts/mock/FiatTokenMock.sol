// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

/**
 * @title FiatTokenMock
 * @notice Stand-in for Circle's USDC (`FiatTokenV2_2`) on a local anvil, so CI
 *         and local development need no Base Sepolia fork.
 *
 * Placed at USDC's CANONICAL address via `anvil_setCode` when the pre-baked
 * anvil image is built. That address is hardcoded in three places
 * (`USDC_ADDRESSES` in the API, `SETTLEMENT_TOKENS_BY_NETWORK` in the webapp,
 * and the e2e `resolveSettlementToken` helper), so the token must appear there
 * rather than wherever a deployment happens to land.
 *
 * ── The storage layout is load-bearing ──────────────────────────────────────
 * `setErc20Balance` (core-kit `AnvilHelpers`) funds accounts by writing
 * `keccak256(abi.encode(holder, FIAT_TOKEN_BALANCE_SLOT))` directly, with
 * `FIAT_TOKEN_BALANCE_SLOT = 9` — the slot of `balanceAndBlacklistStates` in
 * FiatTokenV2_2. The balance mapping here MUST therefore occupy slot 9, or every
 * funding call writes to a slot nothing reads.
 *
 * That failure would be loud rather than silent — `setErc20Balance` reads
 * `balanceOf` back after writing and throws on mismatch — but it would fail
 * every test, so the layout is asserted in the image build too.
 *
 * A fixed `uint256[9]` gap is used rather than mirroring Circle's individual
 * fields: an array occupies exactly nine slots with no packing, whereas
 * re-declaring `address pauser; bool paused; …` invites the compiler to pack two
 * fields into one slot and silently shift the mapping to slot 8.
 *
 * `decimals`/`name`/`symbol` are compile-time constants, not storage, so the
 * contract is fully functional from `setCode` alone with no initialisation —
 * which is what lets it be injected at a canonical address.
 *
 * ── Why a mock rather than the real bytecode ────────────────────────────────
 * Circle's live tokens are proxies. Copying a proxy's runtime code without also
 * curating its implementation slot yields a contract that *has* code yet
 * delegatecalls `address(0)`, so every call succeeds returning empty data and
 * viem reports `returned no data ("0x")`. That is precisely what happened to
 * EURC, which reached CI as raw proxy bytecode with a zeroed implementation slot
 * and broke EIP-7702 wallet migration (the balance sweep calls `balanceOf` on
 * it). A self-contained mock cannot fail that way. See `EurcTokenMock`.
 */
contract FiatTokenMock {
    /// Slots 0-8. Reserved so `_balances` lands exactly on slot 9.
    uint256[9] private __fiatTokenV2_2_layout_gap;

    /// Slot 9 — mirrors `FiatTokenV2_2.balanceAndBlacklistStates`.
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev `virtual` so `EurcTokenMock` can re-label the same layout. Only the
    /// identity differs between the two; everything storage-related must not.
    function name() external pure virtual returns (string memory) {
        return 'USD Coin';
    }

    /// @dev See `name()`.
    function symbol() external pure virtual returns (string memory) {
        return 'USDC';
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    /**
     * @dev Always 0. Accounts are funded by direct slot-9 writes (core-kit's
     * `setErc20Balance` -> `anvil_setStorageAt`), never by minting, and
     * `_transfer` does not touch `_totalSupply` — so this reports 0 while
     * balances are non-zero. No consumer path reads it (`decimals`/`balanceOf`/
     * `transfer`/`approve`/`transferFrom` are the whole surface used), so this
     * is a documented property rather than a bug. If a test ever needs a real
     * supply, add `mint(to, value)` bumping both `_balances[to]` and
     * `_totalSupply`.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Mirrors Circle's `FiatTokenV2_2._balanceOf`, which is verbatim
     * `balanceAndBlacklistStates[_account] & ((1 << 255) - 1)` — a 255-bit
     * balance with the blacklist flag on bit 255 alone. Masking keeps a
     * cheat-code write that happens to set that flag from reading back as an
     * absurd balance.
     *
     * Do NOT narrow this to 159 bits. core-kit's `AnvilHelpers` comment claims
     * "the lower 159 bits hold the balance", but that describes neither Circle
     * nor core-kit: `setErc20Balance` writes `pad(toHex(amount), {size: 32})`,
     * i.e. the full raw word with no mask at all, exactly as Circle's
     * `_setBalance` does. 255 is therefore both faithful to the contract this
     * impersonates and strictly the more permissive of the two.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account] & ((1 << 255) - 1);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        // Treat max allowance as infinite, as USDC does.
        if (allowed != type(uint256).max) {
            require(allowed >= value, 'ERC20: insufficient allowance');
            _allowances[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), 'ERC20: transfer to the zero address');
        uint256 fromBalance = balanceOf(from);
        require(fromBalance >= value, 'ERC20: transfer amount exceeds balance');
        unchecked {
            _balances[from] = fromBalance - value;
            _balances[to] = balanceOf(to) + value;
        }
        emit Transfer(from, to, value);
    }
}
