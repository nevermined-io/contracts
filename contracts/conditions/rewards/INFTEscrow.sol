pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './Reward.sol';
import '../../Common.sol';
import '../ConditionStoreLibrary.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

/**
 * @title NFT Escrow Payment Interface
 * @author Nevermined
 *
 * @dev Common interface for ERC-721 and ERC-1155
 *
 */
contract INFTEscrow {

    event Fulfilled(
        bytes32 indexed _agreementId,
        address indexed _tokenAddress,
        bytes32 _did,
        address _receivers,
        bytes32 _conditionId,
        uint256 _amounts
    );
    
}
