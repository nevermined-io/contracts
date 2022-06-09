pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Condition.sol';
import './INFTHolder.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';

/**
 * @title NFT ERC721 Holder Condition
 * Allows to fulfill a condition to users holding some amount of NFTs for a specific DID
 * @author Nevermined
 *
 * @dev Implementation of the Nft Holder Condition
 */
contract NFT721HolderCondition is Condition, INFTHolder {

    bytes32 private constant CONDITION_TYPE = keccak256('NFT721HolderCondition');

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
            _conditionStoreManagerAddress != address(0) && _owner != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
    }

    function hashValues(
        bytes32 _did,
        address _holderAddress,
        uint256 _amount,
        address _contractAddress
    )
        public
        override
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _holderAddress, _amount, _contractAddress));
    }
    
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _holderAddress,
        uint256 _amount,
        address _contractAddress
    )
        external
        override
        returns (ConditionStoreLibrary.ConditionState)
    {
        IERC721Upgradeable erc721 = IERC721Upgradeable(_contractAddress);
        
        require(
            _amount == 0 || (_amount == 1 && erc721.ownerOf(uint256(_did)) == _holderAddress),
            'The holder doesnt have enough NFT balance for the did given'
        );

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _holderAddress, _amount, _contractAddress)
        );
        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _did, 
            _holderAddress,
            _id,
            _amount
        );
        return state;
    }
}
