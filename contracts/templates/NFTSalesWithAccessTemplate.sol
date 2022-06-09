pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../conditions/LockPaymentCondition.sol';
import '../conditions/NFTs/TransferNFTCondition.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
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
contract NFTSalesWithAccessTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    LockPaymentCondition internal lockPaymentCondition;
    ITransferNFT internal transferCondition;
    EscrowPaymentCondition internal rewardCondition;
    AccessProofCondition internal accessCondition;


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
    * @param _transferConditionAddress transfer NFT condition contract address
    * @param _escrowPaymentAddress escrow reward condition contract address    
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _lockPaymentConditionAddress,
        address _transferConditionAddress,
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
            _transferConditionAddress != address(0) &&
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

        lockPaymentCondition = LockPaymentCondition(
            _lockPaymentConditionAddress
        );
        
        transferCondition = TransferNFTCondition(
            _transferConditionAddress
        );

        rewardCondition = EscrowPaymentCondition(
            _escrowPaymentAddress
        );

        accessCondition = AccessProofCondition(
            _accessCondition
        );

        conditionTypes.push(address(lockPaymentCondition));
        conditionTypes.push(address(transferCondition));
        conditionTypes.push(address(rewardCondition));
        conditionTypes.push(address(accessCondition));
    }
}
