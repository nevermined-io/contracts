// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
 * @title MockFeeOnTransferERC20
 * @notice ERC20 that burns a fixed percentage fee on every transfer (deflationary / fee-on-transfer),
 *         so the recipient receives less than the amount sent. Used to verify the PaymentsVault rejects
 *         tokens that deliver less than the recorded deposit amount.
 */
contract MockFeeOnTransferERC20 is ERC20 {
    /// @notice Transfer fee in basis points (1%)
    uint256 public constant FEE_BPS = 100;

    constructor() ERC20('Fee Token', 'FEE') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Applies the fee on regular transfers; mint/burn (zero address party) are fee-free.
    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * FEE_BPS) / 10_000;
        super._update(from, to, value - fee);
        super._update(from, address(0xdead), fee);
    }
}
