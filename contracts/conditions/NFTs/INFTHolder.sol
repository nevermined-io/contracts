pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../Condition.sol';


interface INFTHolder {

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        address indexed _address,
        bytes32 _conditionId,
        uint256 _amount
    );

    /**
     * @notice hashValues generates the hash of condition inputs 
     *        with the following parameters
     * @param _did the Decentralized Identifier of the asset
     * @param _holderAddress the address of the NFT holder
     * @param _amount is the amount NFTs that need to be hold by the holder
     * @param _contractAddress contract address holding the NFT (ERC-721) or the NFT Factory (ERC-1155)     
     * @return bytes32 hash of all these values 
     */
    function hashValues(
        bytes32 _did, 
        address _holderAddress, 
        uint256 _amount, 
        address _contractAddress
    )
    external
    pure
    returns (bytes32);

    /**
     * @notice fulfill requires a validation that holder has enough
     *       NFTs for a specific DID
     * @param _agreementId SEA agreement identifier
     * @param _did the Decentralized Identifier of the asset    
     * @param _holderAddress the contract address where the reward is locked
     * @param _amount is the amount of NFT to be hold
     * @param _contractAddress contract address holding the NFT (ERC-721) or the NFT Factory (ERC-1155)     
     * @return condition state
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _holderAddress,
        uint256 _amount,
        address _contractAddress
    )
    external
    returns (ConditionStoreLibrary.ConditionState);

}
