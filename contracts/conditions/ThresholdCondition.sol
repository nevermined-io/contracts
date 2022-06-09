pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';

/**
 * @title Threshold Condition
 * @author Nevermined
 *
 * @dev Implementation of the Threshold Condition
 *
 *      Threshold condition acts as a filter for a set of input condition(s) in which sends 
 *      a signal whether to complete the flow execution or abort it. This type of conditions 
 *      works as intermediary conditions where they wire SEA conditions in order to support  
 *      more complex scenarios.
 */
contract ThresholdCondition is Condition {
    
    bytes32 constant public CONDITION_TYPE = keccak256('ThresholdCondition');

    /**
     * @notice initialize init the 
     *       contract with the following parameters
     * @dev this function is called only once during the contract
     *       initialization.
     * @param _owner contract's owner account address
     * @param _conditionStoreManagerAddress condition store manager address
     */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress
    )
        external
        initializer()
    {
        require(
            _conditionStoreManagerAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param inputConditions array of input conditions IDs
    * @param threshold the required number of fulfilled input conditions
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32[] memory inputConditions, 
        uint256 threshold    
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                inputConditions, 
                threshold
            )
        );
    }
    
   /**
    * @notice fulfill threshold condition
    * @dev the fulfill method check whether input conditions are
    *       fulfilled or not.
    * @param _agreementId agreement identifier
    * @param _inputConditions array of input conditions IDs
    * @param threshold the required number of fulfilled input conditions
    * @return condition state (Fulfilled/Aborted)
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32[] calldata _inputConditions,
        uint256 threshold
    )
        external
        returns (ConditionStoreLibrary.ConditionState)
    {
        require(
            _inputConditions.length >= 2 &&
            threshold <= _inputConditions.length,
            'Invalid input conditions length'
        );
        
        require(
            canFulfill(_inputConditions, threshold),
            'Invalid threshold fulfilment'
        );
        
        return super.fulfill(
            generateId(
                _agreementId, 
                hashValues(
                    _inputConditions, 
                    threshold
                )
            ),
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
    }
    
   /**
    * @notice canFulfill check if condition can be fulfilled
    * @param _inputConditions array of input conditions IDs
    * @param threshold the required number of fulfilled input conditions
    * @return _fulfill true if can fulfill 
    */
    function canFulfill(
        bytes32[] memory _inputConditions,
        uint256 threshold
    )
        private
        view
        returns(bool _fulfill)
    {
        uint256 counter = 0;
        _fulfill = false;
        ConditionStoreLibrary.ConditionState inputConditionState;
        ConditionStoreLibrary.ConditionState Fulfilled; // solhint-disable-line
        Fulfilled = ConditionStoreLibrary.ConditionState.Fulfilled;
        
        for(uint i = 0; i < _inputConditions.length; i++)
        { 
            (,inputConditionState,,,) = conditionStoreManager.
            getCondition(_inputConditions[i]);
            
            if(inputConditionState == Fulfilled)
                counter ++;
            if (counter >= threshold)
            {
                _fulfill = true;
                break;
            }
        }
    }
    
}
