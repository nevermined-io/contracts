pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0



/**
 * @title Parity Secret Store Permission Interface
 * @author Nevermined
 */
interface ISecretStorePermission {

   /**
    * @notice grantPermission is called only by documentKeyId Owner or provider
    */
    function grantPermission(
        address user,
        bytes32 documentKeyId
    )
    external;
    
    /**
    * @notice renouncePermission is called only by documentKeyId Owner or provider
    */
    function renouncePermission(
        address user,
        bytes32 documentKeyId
    )
    external;
}
