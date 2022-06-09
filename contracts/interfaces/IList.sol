pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


/**
 * @title List Interface
 * @author Nevermined
 */
interface IList {
    
    function has(
        bytes32 value
    ) 
        external 
        view
        returns(bool);
    
    function has(
        bytes32 value,
        bytes32 id
    )
        external
        view
        returns(bool);
}
