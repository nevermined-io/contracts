pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Common.sol';
import './Condition.sol';
import './ConditionStoreLibrary.sol';
import '../interfaces/IList.sol';
/**
 * @title Whitelisting Condition
 * @author Nevermined
 *
 * @dev Implementation of the Whitelisting Condition
 */
contract WhitelistingCondition is Condition, Common {

    bytes32 constant public CONDITION_TYPE = keccak256('WhitelistingCondition');

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
        initializer
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
    * @param _listAddress list contract address
    * @param _item item in the list
    * @return bytes32 hash of all these values 
    */
    function hashValues(address _listAddress, bytes32 _item)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_listAddress, _item));
    }

   /**
    * @notice fulfill check whether address is whitelisted
    * in order to fulfill the condition. This method will be 
    * called by any one in this whitelist. 
    * @param _agreementId SEA agreement identifier
    * @param _listAddress list contract address
    * @param _item item in the list
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        address _listAddress,
        bytes32 _item
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        require(
            _listAddress != address(0) &&
            isContract(_listAddress),
            'Invalid contract address'
        );
        
        IList list = IList(_listAddress);
        
        require(
            list.has(
                keccak256(abi.encode(msg.sender)),
                _item
            ),
            'Item does not exist'
        );
        
        return super.fulfill(
            generateId(_agreementId, hashValues(_listAddress, _item)),
            ConditionStoreLibrary.ConditionState.Fulfilled
        );            
    }
}
