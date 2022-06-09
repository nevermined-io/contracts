pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../conditions/AccessCondition.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
import '../registry/DIDRegistry.sol';

/**
 * @title Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of Access Agreement Template
 *
 *      Access template is use case specific template.
 *      Anyone (consumer/provider/publisher) can use this template in order
 *      to setup an on-chain SEA. The template is a composite of three basic
 *      conditions. Once the agreement is created, the consumer will lock an amount
 *      of tokens (as listed in the DID document - off-chain metadata) to the 
 *      the lock reward contract which in turn will fire an event. ON the other hand 
 *      the provider is listening to all the emitted events, the provider 
 *      will catch the event and grant permissions to the consumer through 
 *      secret store contract, the consumer now is able to download the data set
 *      by asking the off-chain component of secret store to decrypt the DID and 
 *      encrypt it using the consumer's public key. Then the secret store will 
 *      provide an on-chain proof that the consumer had access to the data set.
 *      Finally, the provider can call the escrow reward condition in order 
 *      to release the payment. Every condition has a time window (time lock and 
 *      time out). This implies that if the provider didn't grant the access to 
 *      the consumer through secret store within this time window, the consumer 
 *      can ask for refund.
 */
contract AccessTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    AccessCondition internal accessCondition;
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

        accessCondition = AccessCondition(
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
