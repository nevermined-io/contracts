pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../conditions/ConditionStoreManager.sol';

contract ConditionStoreChangeFunctionSignature is ConditionStoreManager {

    function createCondition(
        bytes32 _id,
        address _typeRef,
        address _sender
    )
        public
    {
        // change function signature
        require(
            msg.sender == _sender,
            'Invalid _sender address change signature test should fail'
        );

        createCondition(
            _id,
            _typeRef,
            uint(0),
            uint(0)
        );
    }
}
