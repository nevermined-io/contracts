pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './Common.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

/**
 * @title Test Token Contract
 * @author Nevermined
 *
 * @dev Implementation of a Test Token.
 *      Test Token is an ERC20 token only for testing purposes
 */
contract NeverminedToken is
AccessControlUpgradeable,
CommonOwnable,
ERC20CappedUpgradeable {

    using SafeMathUpgradeable for uint256;

    address public nvmConfig;

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return nvmConfig;
    }

    function setNvmConfigAddress(address _addr)
    external
    onlyOwner
    {
        nvmConfig = _addr;
    }

    /**
    * @dev NeverminedToken Initializer
    *      Runs only on initial contract creation.
    * @param _owner refers to the owner of the contract
    * @param _initialMinter is the first token minter added
    */
    function initialize(
        address _owner,
        address payable _initialMinter
    )
    public
    initializer
    {
        uint256 cap = 1500000000;
        uint256 totalSupply = cap.mul(10 ** 18);

        ERC20Upgradeable.__ERC20_init('NeverminedToken', 'NVM');
        ERC20CappedUpgradeable.__ERC20Capped_init(totalSupply);
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // set initial minter, this has to be renounced after the setup!
        AccessControlUpgradeable._setupRole('minter', _initialMinter);
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - minted tokens must not cause the total supply to go over the cap.
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal
    override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function mint(address account, uint256 amount)
    external
    returns (bool)
    {
        require(
            AccessControlUpgradeable.hasRole('minter', _msgSender()),
            'Address not granted for minting tokens');
        super._mint(account, amount);
        return true;
    }

    function _msgSender() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(CommonOwnable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }

}
