pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../conditions/ConditionStoreManager.sol';


contract EpochLibraryProxy is ConditionStoreManager {

    function create(
        bytes32 _id,
        uint256 _timeLock,
        uint256 _timeOut
    )
        external
    {
        createEpoch(
            epochList,
            _id,
            _timeLock,
            _timeOut
        );
    }
}
