pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../registry/DIDRegistry.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
import '../conditions/ComputeExecutionCondition.sol';

/**
 * @title Escrow Compute Template
 * @author Nevermined
 *
 * @dev Implementation of a Compute Execution Agreement Template
 *
 *      EscrowComputeExecutionTemplate is use case specific template.
 *      Anyone (consumer/provider/publisher) can use this template in order
 *      to setup an on-chain SEA. The template is a composite of three basic
 *      conditions. Once the agreement is created, the consumer will lock an amount
 *      of tokens (as listed in the DID document - off-chain metadata) to the 
 *      the lock reward contract which in turn will fire an event. ON the other hand 
 *      the provider is listening to all the emitted events, the provider 
 *      will catch the event and grant permissions to trigger a computation granting
 *      the execution via the ComputeExecutionCondition contract. 
 *      The consumer now is able to trigger that computation
 *      by asking the off-chain gateway to start the execution of a compute workflow.
 *      Finally, the provider can call the escrow reward condition in order 
 *      to release the payment. Every condition has a time window (time lock and 
 *      time out). This implies that if the provider didn't grant the execution to 
 *      the consumer within this time window, the consumer 
 *      can ask for refund.
 */
contract EscrowComputeExecutionTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    ComputeExecutionCondition internal computeExecutionCondition;
    LockPaymentCondition internal lockPaymentCondition;
    EscrowPaymentCondition internal escrowPayment;

   /**
    * @notice initialize init the 
    *       contract with the following parameters.
    * @dev this function is called only once during the contract
    *       initialization. It initializes the ownable feature, and 
    *       set push the required condition types including 
    *       service executor condition, lock reward and escrow reward conditions.
    * @param _owner contract's owner account address
    * @param _agreementStoreManagerAddress agreement store manager contract address
    * @param _didRegistryAddress DID registry contract address
    * @param _computeExecutionConditionAddress service executor condition contract address
    * @param _lockPaymentConditionAddress lock reward condition contract address
    * @param _escrowPaymentAddress escrow reward contract address
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _didRegistryAddress,
        address _computeExecutionConditionAddress,
        address _lockPaymentConditionAddress,
        address payable _escrowPaymentAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0) &&
            _computeExecutionConditionAddress != address(0) &&
            _lockPaymentConditionAddress != address(0) &&
            _escrowPaymentAddress != address(0),
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

        computeExecutionCondition = ComputeExecutionCondition(
            _computeExecutionConditionAddress
        );

        lockPaymentCondition = LockPaymentCondition(
            _lockPaymentConditionAddress
        );

        escrowPayment = EscrowPaymentCondition(
            _escrowPaymentAddress
        );

        conditionTypes.push(address(computeExecutionCondition));
        conditionTypes.push(address(lockPaymentCondition));
        conditionTypes.push(address(escrowPayment));
    }

    function name() public pure returns (string memory) {
        return 'EscrowComputeExecutionTemplate';
    }
}
