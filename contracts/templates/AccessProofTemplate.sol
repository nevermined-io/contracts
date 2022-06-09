pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../conditions/AccessProofCondition.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
import '../registry/DIDRegistry.sol';

/**
 * @title Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of Access Agreement Template
 *
 */
contract AccessProofTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    AccessProofCondition internal accessCondition;
    LockPaymentCondition internal lockCondition;
    EscrowPaymentCondition internal escrowReward;

   /**
    * @notice initialize init the 
    *       contract with the following parameters.
    * @dev this function is called only once during the contract
    *       initialization. It initializes the ownable feature, and 
    *       set push the required condition types including 
    *       access , lock payment and escrow payment conditions.
    * @param _owner contract's owner account address
    * @param _agreementStoreManagerAddress agreement store manager contract address
    * @param _didRegistryAddress DID registry contract address
    * @param _accessConditionAddress access condition address
    * @param _lockConditionAddress lock reward condition contract address
    * @param _escrowConditionAddress escrow reward contract address
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _didRegistryAddress,
        address _accessConditionAddress,
        address _lockConditionAddress,
        address payable _escrowConditionAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0) &&
            _accessConditionAddress != address(0) &&
            _lockConditionAddress != address(0) &&
            _escrowConditionAddress != address(0),
            'Invalid address'
        );

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );

        didRegistry = DIDRegistry(
            _didRegistryAddress
        );

        accessCondition = AccessProofCondition(
            _accessConditionAddress
        );

        lockCondition = LockPaymentCondition(
            _lockConditionAddress
        );

        escrowReward = EscrowPaymentCondition(
            _escrowConditionAddress
        );

        conditionTypes.push(address(accessCondition));
        conditionTypes.push(address(lockCondition));
        conditionTypes.push(address(escrowReward));
    }
}
