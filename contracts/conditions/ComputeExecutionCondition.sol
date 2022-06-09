pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0



import './Condition.sol';
import '../registry/DIDRegistry.sol';
import '../agreements/AgreementStoreManager.sol';

/**
 * @title Compute Execution Condition
 * @author Nevermined
 *
 * @dev Implementation of the Compute Execution Condition
 *      This condition is meant to be a signal in which triggers
 *      the execution of a compute service. The compute service is fully described
 *      in the associated DID document. The provider of the compute service will
 *      send this signal to its workers by fulfilling the condition where
 *      they are listening to the fulfilled event.
 */
contract ComputeExecutionCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('ComputeExecutionCondition');

    // DID --> Compute Consumer address --> triggered compute  ?
    mapping(bytes32 => mapping(address => bool)) private computeExecutionStatus;
    
    AgreementStoreManager private agreementStoreManager;
    
    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        address indexed _computeConsumer,
        bytes32 _conditionId
    );
    
    modifier onlyDIDOwnerOrProvider(
        bytes32 _did
    )
    {
        DIDRegistry didRegistry = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );
        
        require(
            didRegistry.isDIDProvider(_did, msg.sender) || 
            msg.sender == didRegistry.getDIDOwner(_did),
            'Invalid DID owner/provider'
        );
        _;
    }

   /**
    * @notice initialize init the 
    *       contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address
    * @param _agreementStoreManagerAddress agreement store manager address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _agreementStoreManagerAddress
    )
        external
        initializer()
    {
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did Decentralized Identifier (unique compute/asset resolver) describes the compute service
    * @param _computeConsumer is the consumer's address 
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _computeConsumer
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _computeConsumer));
    }

   /**
    * @notice fulfill compute execution condition
    * @dev only the compute provider can fulfill this condition. By fulfilling this 
    * condition the compute provider will trigger the execution of 
    * the offered job/compute. The compute service is described in a DID document.
    * @param _agreementId agreement identifier
    * @param _did Decentralized Identifier (unique compute/asset resolver) describes the compute service
    * @param _computeConsumer is the consumer's address 
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _computeConsumer
    )
        public
        onlyDIDOwnerOrProvider(_did)
        returns (ConditionStoreLibrary.ConditionState)
    {   
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _computeConsumer)
        );

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
        
        computeExecutionStatus[_did][_computeConsumer] = true;
        
        emit Fulfilled(
            _agreementId,
            _did,
            _computeConsumer,
            _id
        );
        return state;
    }
    
    /**
    * @notice wasComputeTriggered checks whether the compute is triggered or not.
    * @param _did Decentralized Identifier (unique compute/asset resolver) describes the compute service
    * @param _computeConsumer is the compute consumer's address
    * @return true if the compute is triggered 
    */
    function wasComputeTriggered(
        bytes32 _did,
        address _computeConsumer
    )
        public
        view
        returns (bool)
    {
        return computeExecutionStatus[_did][_computeConsumer];
    }
}
