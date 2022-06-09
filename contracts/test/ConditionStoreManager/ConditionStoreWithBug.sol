pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../conditions/ConditionStoreManager.sol';

contract ConditionStoreWithBug is ConditionStoreManager {
    function getConditionState(bytes32 _id)
        public
        view
        override
        returns (ConditionStoreLibrary.ConditionState)
    {
        // adding Bug here: shouldn't return fulfilled
        if (conditionList.conditions[_id].state ==
           ConditionStoreLibrary.ConditionState.Uninitialized) {
            return ConditionStoreLibrary.ConditionState.Fulfilled;
        }

        return ConditionStoreLibrary.ConditionState.Fulfilled;
    }
}
