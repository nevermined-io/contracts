/// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

/// @dev Role for upgrading all contracts
/// @dev uint64(uint256(keccak256(abi.encode('UPGRADE_ROLE'))));
uint64 constant UPGRADE_ROLE = uint64(16061234310146353691);

/// @dev Role for depositing credits
/// @dev uint64(uint256(keccak256(abi.encode('DEPOSITOR_ROLE'))));
uint64 constant DEPOSITOR_ROLE = uint64(14314970521567793544);

/// @dev Role for withdrawing credits
/// @dev uint64(uint256(keccak256(abi.encode('WITHDRAW_ROLE'))));
uint64 constant WITHDRAW_ROLE = uint64(8393396895733992431);

/// @dev Role for minting credits
/// @dev uint64(uint256(keccak256(abi.encode('CREDITS_MINTER_ROLE'))));
uint64 constant CREDITS_MINTER_ROLE = uint64(331619801143826648);

/// @dev Role that can change the parameters of the Nevermined Config contract
/// @dev Addresses with this role can modify configuration parameters but have
/// fewer privileges than owners
/// @dev uint64(uint256(keccak256(abi.encode('NVM_GOVERNOR'))));
uint64 constant GOVERNOR_ROLE = uint64(13709648602636273795);

/// @dev Role granted to Smart Contracts registered as Templates (they can execute the template)
/// @dev Used to restrict which contracts can function as agreement templates in the protocol
/// @dev uint64(uint256(keccak256(abi.encode('NVM_CONTRACT_TEMPLATE'))));
uint64 constant CONTRACT_TEMPLATE_ROLE = uint64(10197209388572726906);

/// @dev Role granted to Smart Contracts registered as NVM Conditions (they can fulfill conditions)
/// @dev Used to restrict which contracts can function as conditions within agreement templates
/// @dev uint64(uint256(keccak256(abi.encode('NVM_CONTRACT_CONDITION'))));
uint64 constant CONTRACT_CONDITION_ROLE = uint64(16570836817734027638);

/// @dev Role granted to Smart Contract that are allowed to call AgreementsStore.updateConditionStatus
/// @dev uint64(uint256(keccak256(abi.encode('UPDATE_CONDITION_STATUS'))));
uint64 constant UPDATE_CONDITION_STATUS_ROLE = uint64(14777935691551675925);

/// @dev This role is granted to the accounts doing the off-chain fiat settlement validation
/// @dev via the integration with an external provider (i.e Stripe). These accounts act as oracles
/// @dev that verify that a fiat payment has been successfully processed before marking
/// @dev the condition as fulfilled.
/// @dev uint64(uint256(keccak256(abi.encode('FIAT_SETTLEMENT_ROLE'))));
uint64 constant FIAT_SETTLEMENT_ROLE = uint64(3860893312041324254);

/// @dev Role for burning credits
/// @dev uint64(uint256(keccak256(abi.encode('CREDITS_BURNER_ROLE'))));
uint64 constant CREDITS_BURNER_ROLE = uint64(16934877136143260882);

/// @dev Role for transferring credits
/// @dev uint64(uint256(keccak256(abi.encode('CREDITS_TRANSFER_ROLE'))));
uint64 constant CREDITS_TRANSFER_ROLE = uint64(11914029060103770296);

/// @dev Role for backend nvm infrastructure management
/// @dev uint64(uint256(keccak256(abi.encode('NVM_INFRA_ADMIN'))));
uint64 constant NVM_INFRA_ADMIN_ROLE = uint64(7924818820658164977);

/// @dev Role for managing the IdentityRegistry contract
/// @dev uint64(uint256(keccak256(abi.encode('IDENTITY_REGISTRY_ROLE'))));
uint64 constant IDENTITY_REGISTRY_ROLE = uint64(5238499825143577583);

/// @dev Role for backend nvm infrastructure management
uint64 constant DUMMY_ROLE = uint64(1111111111111111112);
