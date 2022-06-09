pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './BaseEscrowTemplate.sol';
import '../registry/DIDRegistry.sol';
import '../conditions/Condition.sol';


/**
 * @title Dynamic Access Template
 * @author Nevermined
 *
 * @dev Implementation of Agreement Template
 * This is a dynamic template that allows to setup flexible conditions depending 
 * on the use case.
 *
 */
contract DynamicAccessTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;

    TemplateConditions internal templateConfig;

    struct TemplateConditions {
        mapping(address => Condition) templateConditions;
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
    * @param _didRegistryAddress DID registry contract address
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _didRegistryAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0),
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
        
    }


    /**
     * @notice addTemplateCondition adds a new condition to the template
     * @param _conditionAddress condition contract address
     * @return length conditionTypes array size
     */
    function addTemplateCondition(address _conditionAddress)
    external
    onlyOwner
    returns (uint length)
    {
        require(
            _conditionAddress != address(0),
            'Invalid address'
        );
        conditionTypes.push(_conditionAddress);
        templateConfig.templateConditions[_conditionAddress] = Condition(_conditionAddress);
        return conditionTypes.length;
    }

    /**
     * @notice removeLastTemplateCondition removes last condition added to the template
     * @return conditionTypes existing in the array 
     */
    function removeLastTemplateCondition()
    external
    onlyOwner
    returns (address[] memory)
    {
        conditionTypes.pop();
        return conditionTypes;
    }
    
}
