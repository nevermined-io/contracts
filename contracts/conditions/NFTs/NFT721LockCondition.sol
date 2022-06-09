pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Condition.sol';
import './INFTLock.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol';

/**
 * @title NFT (ERC-721) Lock Condition
 * @author Nevermined
 *
 * @dev Implementation of the NFT Lock Condition for ERC-721 based NFTs 
 */
contract NFT721LockCondition is Condition, INFTLock, ReentrancyGuardUpgradeable, IERC721ReceiverUpgradeable {
    
    bytes32 constant public CONDITION_TYPE = keccak256('NFT721LockCondition');
    
   /**
    * @notice initialize init the  contract with the following parameters
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
    * @param _did the DID of the asset with NFTs attached to lock    
    * @param _lockAddress the contract address where the NFT will be locked
    * @param _amount is the amount of the locked tokens
    * @param _nftContractAddress Is the address of the NFT (ERC-721) contract to use         
    * @return bytes32 hash of all these values
    */
    function hashValues(
        bytes32 _did,
        address _lockAddress,
        uint256 _amount,
        address _nftContractAddress
    )
        public
        override
        pure
        returns (bytes32)
    {
        return hashValuesMarked(_did, _lockAddress, _amount, address(0), _nftContractAddress);
    }

    function hashValuesMarked(
        bytes32 _did,
        address _lockAddress,
        uint256 _amount,
        address _receiver,
        address _nftContractAddress
    )
        public
        override
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _lockAddress, _amount, _receiver, _nftContractAddress));
    }

    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method lock a NFT into the `_lockAddress`. 
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _lockAddress the contract address where the NFT will be locked
     * @param _amount is the amount of the locked tokens (1)
     * @param _nftContractAddress Is the address of the NFT (ERC-721) contract to use     
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillMarked(
        bytes32 _agreementId,
        bytes32 _did,
        address _lockAddress,
        uint256 _amount,
        address _receiver,
        address _nftContractAddress
    )
        public
        override
        nonReentrant
        returns (ConditionStoreLibrary.ConditionState)
    {
        IERC721Upgradeable erc721 = IERC721Upgradeable(_nftContractAddress);

        require(
            _amount == 0 || (_amount == 1 && erc721.ownerOf(uint256(_did)) == msg.sender),
            'Sender does not have enough balance or is not the NFT owner.'
        );

        if (_amount == 1) {
            erc721.safeTransferFrom(msg.sender, _lockAddress, uint256(_did));
        }

        bytes32 _id = generateId(
            _agreementId,
            hashValuesMarked(_did, _lockAddress, _amount, _receiver, _nftContractAddress)
        );
        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _did,
            _lockAddress,
            _id,
            _amount,
            _receiver,
            _nftContractAddress
        );
        return state;
    }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _lockAddress,
        uint256 _amount,
        address _nftContractAddress
    )
        external
        override
        returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfillMarked(_agreementId, _did, _lockAddress, _amount, address(0), _nftContractAddress);
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }    
    
}
