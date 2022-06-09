pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';

/**
 * @title Hash Lock Condition
 * @author Nevermined
 *
 * @dev Implementation of the Hash Lock Condition
 */
contract HashLockCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('HashLockCondition');

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
    * @param _preimage refers uint value of the hash pre-image.
    * @return bytes32 hash of all these values 
    */
    function hashValues(uint256 _preimage)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_preimage));
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _preimage refers string value of the hash pre-image.
    * @return bytes32 hash of all these values 
    */
    function hashValues(string memory _preimage)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_preimage));
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _preimage refers bytes32 value of the hash pre-image.
    * @return bytes32 hash of all these values 
    */
    function hashValues(bytes32 _preimage)
        public
        pure
        returns
        (bytes32)
    {
        return keccak256(abi.encode(_preimage));
    }

   /**
    * @notice fulfill the condition by calling check the 
    *       the hash and the pre-image uint value
    * @param _agreementId SEA agreement identifier
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        uint256 _preimage
    )
        external
        returns (ConditionStoreLibrary.ConditionState)
    {
        return _fulfill(generateId(_agreementId, hashValues(_preimage)));
    }

   /**
    * @notice fulfill the condition by calling check the 
    *       the hash and the pre-image string value
    * @param _agreementId SEA agreement identifier
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        string memory _preimage
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        return _fulfill(generateId(_agreementId, hashValues(_preimage)));
    }

   /**
    * @notice fulfill the condition by calling check the 
    *       the hash and the pre-image bytes32 value
    * @param _agreementId SEA agreement identifier
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _preimage
    )
        external
        returns (ConditionStoreLibrary.ConditionState)
    {
        return _fulfill(generateId(_agreementId, hashValues(_preimage)));
    }

   /**
    * @notice _fulfill calls super fulfil method
    * @param _generatedId SEA agreement identifier
    * @return condition state
    */
    function _fulfill(
        bytes32 _generatedId
    )
        private
        returns (ConditionStoreLibrary.ConditionState)
    {
        return super.fulfill(
            _generatedId,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
    }
}
