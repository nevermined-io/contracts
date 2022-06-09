pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../conditions/NFTs/INFTLock.sol';
import '../conditions/rewards/INFTEscrow.sol';
import '../registry/DIDRegistry.sol';
import '../conditions/AccessProofCondition.sol';


/**
 * @title Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of NFT Sales Template
 *
 *      The NFT Sales template supports an scenario where a NFT owner
 *      can sell that asset to a new Owner.
 *      Anyone (consumer/provider/publisher) can use this template in order
 *      to setup an agreement allowing a NFT owner to transfer the asset ownership
 *      after some payment. 
 *      The template is a composite of 3 basic conditions: 
 *      - Lock Payment Condition
 *      - Transfer NFT Condition
 *      - Escrow Reward Condition
 * 
 *      This scenario takes into account royalties for original creators in the secondary market.
 *      Once the agreement is created, the consumer after payment can request the transfer of the NFT
 *      from the current owner for a specific DID. 
 */
contract NFTAccessSwapTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    INFTLock internal lockPaymentCondition;
    INFTEscrow internal rewardCondition;
    AccessProofCondition internal accessCondition;

    // Force to have different bytecode from other templates
    function id() public pure returns (uint) {
        return 0;
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
    * @param _lockPaymentConditionAddress lock reward condition contract address
    * @param _escrowPaymentAddress escrow reward condition contract address    
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _lockPaymentConditionAddress,
        address payable _escrowPaymentAddress,
        address _accessCondition
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _lockPaymentConditionAddress != address(0) &&
            _escrowPaymentAddress != address(0) &&
            _accessCondition != address(0),
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

        lockPaymentCondition = INFTLock(
            _lockPaymentConditionAddress
        );
        
        rewardCondition = INFTEscrow(
            _escrowPaymentAddress
        );

        accessCondition = AccessProofCondition(
            _accessCondition
        );

        conditionTypes.push(address(lockPaymentCondition));
        conditionTypes.push(address(rewardCondition));
        conditionTypes.push(address(accessCondition));
    }

}
