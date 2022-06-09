pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import './Condition.sol';
import './ConditionStoreLibrary.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
/**
 * @title Sign Condition
 * @author Nevermined
 *
 * @dev Implementation of the Sign Condition
 */
contract SignCondition is Condition {

    bytes32 constant public CONDITION_TYPE = keccak256('SignCondition');

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
    * @param _message the message to be signed
    * @param _publicKey the public key of the signing address
    * @return bytes32 hash of all these values 
    */
    function hashValues(bytes32 _message, address _publicKey)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_message, _publicKey));
    }

   /**
    * @notice fulfill validate the signed message and fulfill the condition
    * @param _agreementId SEA agreement identifier
    * @param _message the message to be signed
    * @param _publicKey the public key of the signing address
    * @param _signature signature of the signed message using the public key
    * @return condition state
    */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _message,
        address _publicKey,
        bytes memory _signature
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        require(
            ECDSAUpgradeable.recover(_message, _signature) == _publicKey,
            'Could not recover signature'
        );
        return super.fulfill(
            generateId(_agreementId, hashValues(_message, _publicKey)),
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
    }
}
