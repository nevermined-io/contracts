pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/TransferDIDOwnershipCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
import '../registry/DIDRegistry.sol';

/**
 * @title Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of DID Sales Template
 *
 *      The DID Sales template supports an scenario where an Asset owner
 *      can sell that asset to a new Owner.
 *      Anyone (consumer/provider/publisher) can use this template in order
 *      to setup an agreement allowing an Asset owner to get transfer the asset ownership
 *      after some payment. 
 *      The template is a composite of 3 basic conditions: 
 *      - Lock Payment Condition
 *      - Transfer DID Condition
 *      - Escrow Reward Condition
 * 
 *      This scenario takes into account royalties for original creators in the secondary market.
 *      Once the agreement is created, the consumer after payment can request the ownership transfer of an asset
 *      from the current owner for a specific DID. 
 */
contract DIDSalesTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    LockPaymentCondition internal lockPaymentCondition;
    TransferDIDOwnershipCondition internal transferCondition;
    EscrowPaymentCondition internal rewardCondition;

    // Force to have different bytecode from other templates
    function id() public pure returns (uint) {
        return 2;
    }

   /**
    * @notice initialize init the 
    *       contract with the following parameters.
    * @dev this function is called only once during the contract
    *       initialization. It initializes the ownable feature, and 
    *       set push the required condition types including 
    *       access secret store, lock reward and escrow reward conditions.
    * @param _owner contract's owner account address
    * @param _agreementStoreManagerAddress agreement store manager contract address
    * @param _lockConditionAddress lock reward condition contract address
    * @param _transferConditionAddress transfer ownership condition contract address
    * @param _escrowPaymentAddress escrow reward condition contract address    
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _lockConditionAddress,
        address _transferConditionAddress,
        address payable _escrowPaymentAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _lockConditionAddress != address(0) &&
            _transferConditionAddress != address(0) &&
            _escrowPaymentAddress != address(0),
            'Invalid address'
        );

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );

        didRegistry = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );

        lockPaymentCondition = LockPaymentCondition(
            _lockConditionAddress
        );
        
        transferCondition = TransferDIDOwnershipCondition(
            _transferConditionAddress
        );

        rewardCondition = EscrowPaymentCondition(
            _escrowPaymentAddress
        );

        conditionTypes.push(address(lockPaymentCondition));
        conditionTypes.push(address(transferCondition));
        conditionTypes.push(address(rewardCondition));
    }
}
