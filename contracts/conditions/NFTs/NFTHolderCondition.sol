pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Condition.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol';
import './INFTHolder.sol';

/**
 * @title Nft Holder Condition
 * Allows to fulfill a condition to users holding some amount of NFTs for a specific DID
 * @author Nevermined
 *
 * @dev Implementation of the Nft Holder Condition
 */
contract NFTHolderCondition is Condition, INFTHolder {

    ERC1155BurnableUpgradeable private erc1155;

    bytes32 private constant CONDITION_TYPE = keccak256('NFTHolderCondition');

   /**
    * @notice initialize init the 
    *       contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address
    * @param _ercAddress Nevermined ERC-1155 address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _ercAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _ercAddress != address(0) &&
            _conditionStoreManagerAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );
        erc1155 = ERC1155BurnableUpgradeable(_ercAddress);
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did the Decentralized Identifier of the asset
    * @param _holderAddress the address of the NFT holder
    * @param _amount is the amount NFTs that need to be hold by the holder
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _holderAddress,
        uint256 _amount
    )
        public
        view
        returns (bytes32)
    {
        return hashValues(_did, _holderAddress, _amount, address(erc1155));
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
    

    /**
     * @notice fulfill requires a validation that holder has enough
     *       NFTs for a specific DID
     * @param _agreementId SEA agreement identifier
     * @param _did the Decentralized Identifier of the asset    
     * @param _holderAddress the contract address where the reward is locked
     * @param _amount is the amount of NFT to be hold
     * @return condition state
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _holderAddress,
        uint256 _amount
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfill(_agreementId, _did, _holderAddress, _amount, address(erc1155));
    }
    
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _holderAddress,
        uint256 _amount,
        address _contractAddress
    )
        public
        override
        returns (ConditionStoreLibrary.ConditionState)
    {
        require(
            IERC1155Upgradeable(_contractAddress).balanceOf(_holderAddress, uint256(_did)) >= _amount,
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
