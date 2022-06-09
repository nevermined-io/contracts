pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../Condition.sol';


interface INFTAccess {

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _documentId,
        address indexed _grantee,
        bytes32 _conditionId
    );    
    
    /**
     * @notice hashValues generates the hash of condition inputs 
     *        with the following parameters
     * @param _documentId refers to the DID in which secret store will issue the decryption keys
     * @param _grantee is the address of the granted user or the DID provider
     * @param _contractAddress contract address holding the NFT (ERC-721) or the NFT Factory (ERC-1155)
     * @return bytes32 hash of all these values 
     */
    function hashValues(
        bytes32 _documentId, 
        address _grantee, 
        address _contractAddress
    ) 
    external 
    pure 
    returns (bytes32);

    /**
     * @notice fulfill NFT Access conditions
     * @dev only DID owner or DID provider can call this
     *       method. Fulfill method sets the permissions 
     *       for the granted consumer's address to true then
     *       fulfill the condition
     * @param _agreementId agreement identifier
     * @param _documentId refers to the DID in which secret store will issue the decryption keys
     * @param _grantee is the address of the granted user or the DID provider
     * @param _contractAddress contract address holding the NFT (ERC-721) or the NFT Factory (ERC-1155)     
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfill(
        bytes32 _agreementId, 
        bytes32 _documentId, 
        address _grantee, 
        address _contractAddress
    ) 
    external 
    returns (ConditionStoreLibrary.ConditionState);
        
}
