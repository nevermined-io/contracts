pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import './NeverminedToken.sol';

/**
 * @title Ocean Protocol Dispenser Contract
 * @author Nevermined
 */
contract Dispenser is OwnableUpgradeable {

    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for uint;

    // limit period for request of tokens
    // mapping from address to last time of request
    mapping(address => uint256) internal tokenRequests;

    uint256 internal totalMintAmount;

    // max amount of tokens user can get for each request
    uint256 internal maxAmount;

    // max amount of tokens that can be minted using this dispenser in total
    uint256 internal maxMintAmount;

    // min amount of time to wait before request token again
    uint256 internal minPeriod;

    // same as 10**token.decimals()
    uint256 internal scale;

    NeverminedToken public token;

    event RequestFrequencyExceeded(
        address indexed requester,
        uint256 minPeriod
    );

    // Request amount limit exceeded
    event RequestLimitExceeded(
        address indexed requester,
        uint256 amount,
        uint256 maxAmount
    );

    modifier isValidAddress(address _address) {
        require(
            _address != address(0x0),
            'isValidAddress failed, Address is 0x0.'
        );
        _;
    }

    /**
     * @dev Dispenser Initializer
     * @param _tokenAddress The deployed contract address of an ERC20
     * @param _owner The owner of the Dispenser
     * Runs only on initial contract creation.
     */
    function initialize(
        address _tokenAddress,
        address _owner
    )
        external
        initializer
        isValidAddress(_tokenAddress)
    {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        // init total mint amount
        totalMintAmount = 0;
        // instantiate Token contract
        token = NeverminedToken(_tokenAddress);

        scale = 10 ** uint256(token.decimals());
        maxAmount = uint256(1000).mul(scale);
        minPeriod = 0;

        maxMintAmount = uint256(100000000).mul(scale);
    }

    /**
     * @dev user can request some tokens for testing
     * @param amount the amount of tokens to be requested
     * @return tokensTransferred Boolean indication of tokens are requested
     */
    function requestTokens(
        uint256 amount
    )
        external
        isValidAddress(msg.sender)
        returns (bool tokensTransferred)
    {
        uint256 amountWithDigits = amount.mul(scale);

        require(
            amountWithDigits + totalMintAmount < maxMintAmount,
            'Exceeded maxMintAmount'
        );

        // solhint-disable-next-line
        if (block.timestamp < tokenRequests[msg.sender] + minPeriod) {
            // Failed, requested to frequently
            emit RequestFrequencyExceeded(
                msg.sender,
                minPeriod
            );
            return false;
        }

        // amount should not exceed maxAmount
        if (amountWithDigits > maxAmount) {
            // Failed, requested to much tokens
            emit RequestLimitExceeded(
                msg.sender,
                amount,
                maxAmount
            );
            return false;
        } else {
            // solhint-disable-next-line
            tokenRequests[msg.sender] = block.timestamp;

            totalMintAmount = totalMintAmount.add(amountWithDigits);

            require(
                token.mint(msg.sender, amountWithDigits),
                'Token minting failed.'
            );

            return true;
        }
    }

    /**
     * @dev the Owner can set the min period for token requests
     * @param period the min amount of time before next request
     */
    function setMinPeriod(
        uint period
    )
        external
        onlyOwner
    {
        // set min period of time before next request (in seconds)
        minPeriod = period;
    }

    /**
     * @dev the Owner can set the max amount for token requests
     * @param amount the max amount of tokens that can be requested
     */
    function setMaxAmount(
        uint256 amount
    )
        external
        onlyOwner
    {
        // set max amount for each request
        maxAmount = amount.mul(scale);
    }

    /**
     * @dev the Owner can set the max amount for token requests
     * @param amount the max amount of tokens that can be requested
     */
    function setMaxMintAmount(
        uint amount
    )
        external
        onlyOwner
    {
        // set max amount for each request
        maxMintAmount = amount.mul(scale);
    }
}
