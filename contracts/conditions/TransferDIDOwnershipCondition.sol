pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import '../registry/DIDRegistry.sol';

/**
 * @title Transfer DID Ownership Condition
 * @author Nevermined
 *
 * @dev Implementation of condition allowing to transfer the ownership
 *      between the original owner and a receiver
 *
 */
contract TransferDIDOwnershipCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('TransferDIDOwnershipCondition');

    DIDRegistry internal didRegistry;
    
    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        address indexed _receiver,
        bytes32 _conditionId
    );
    
   /**
    * @notice initialize init the contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address    
    * @param _didRegistryAddress DID Registry address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _didRegistryAddress
    )
        external
        initializer()
    {
        require(
            _conditionStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0),
            'Invalid address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
        
        didRegistry = DIDRegistry(
            _didRegistryAddress
        );        
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _receiver is the address of the granted user or the DID provider
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _receiver
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _receiver));
    }

   /**
    * @notice fulfill the transfer DID ownership condition
    * @dev only DID owner or DID provider can call this
    *       method. Fulfill method transfer full ownership permissions 
    *       to to _receiver address. 
    *       When true then fulfill the condition
    * @param _agreementId agreement identifier
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _receiver is the address of the granted user
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _receiver
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        // Only DID Owner can fulfill
        didRegistry.transferDIDOwnershipManaged(msg.sender, _did, _receiver);
        
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _receiver)
        );

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
        
        emit Fulfilled(
            _agreementId,
            _did,
            _receiver,
            _id
        );

        return state;
    }
    
}

