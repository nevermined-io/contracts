pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Condition.sol';
import '../../registry/DIDRegistry.sol';
import './ITransferNFT.sol';
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title Transfer NFT Condition
 * @author Keyko
 *
 * @dev Implementation of condition allowing to transfer an NFT
 *      between the original owner and a receiver
 *
 */
contract TransferNFTCondition is Condition, ITransferNFT, AccessControlUpgradeable {

    bytes32 public constant CONDITION_TYPE = keccak256('TransferNFTCondition');

    bytes32 public constant MARKET_ROLE = keccak256("MARKETPLACE_ROLE");
    
    DIDRegistry private registry;

   /**
    * @notice initialize init the contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address    
    * @param _didRegistryAddress DID Registry address
    * @param _nftContractAddress Market address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _didRegistryAddress,
        address _nftContractAddress
    )
        external
        override
        initializer()
    {
        require(
            _conditionStoreManagerAddress != address(0) &&
            _didRegistryAddress != address(0),
            'Invalid address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        registry = DIDRegistry(
            _didRegistryAddress
        );
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        grantRole(MARKET_ROLE, _nftContractAddress);
    }

    function grantMarketRole(address _nftContractAddress)
    public 
    onlyOwner 
    {
        return grantRole(MARKET_ROLE, _nftContractAddress);
    }


    function revokeMarketRole(address _nftContractAddress)
    public
    onlyOwner 
    {
        return revokeRole(MARKET_ROLE, _nftContractAddress);
    }
    
   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the granted user or the DID provider
    * @param _nftAmount amount of NFTs to transfer
    * @param _lockCondition lock condition identifier
    * @return bytes32 hash of all these values
    */
    function hashValues(
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockCondition
    )
        public
        view
        returns (bytes32)
    {
        return hashValues(_did, _nftReceiver, _nftAmount, _lockCondition, address(registry));
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the granted user or the DID provider
    * @param _nftAmount amount of NFTs to transfer
    * @param _lockCondition lock condition identifier
    * @param _nftContractAddress NFT contract to use
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockCondition,
        address _nftContractAddress
    )
        public
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encode(_did, _nftReceiver, _nftAmount, _lockCondition, _nftContractAddress));
    }

    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition
    )
    public
    returns (ConditionStoreLibrary.ConditionState)
    {
        return fulfill(_agreementId, _did, _nftReceiver, _nftAmount, _lockPaymentCondition, address(registry));
    }

    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftContractAddress NFT contract to use
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition,
        address _nftContractAddress
    )
    public
    override
    returns (ConditionStoreLibrary.ConditionState)
    {

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress)
        );

        address lockConditionTypeRef;
        ConditionStoreLibrary.ConditionState lockConditionState;
        (lockConditionTypeRef,lockConditionState,,,,,,) = conditionStoreManager
        .getCondition(_lockPaymentCondition);

        require(
            lockConditionState == ConditionStoreLibrary.ConditionState.Fulfilled,
            'LockCondition needs to be Fulfilled'
        );
        
        IERC1155Upgradeable token = IERC1155Upgradeable(_nftContractAddress);

        token.safeTransferFrom(msg.sender, _nftReceiver, uint256(_did), _nftAmount, '');

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _did,
            _nftReceiver,
            _nftAmount,
            _id,
            _nftContractAddress
        );

        return state;
    }    
    
    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address in the DIDRegistry contract. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _nftReceiver is the address of the account to receive the NFT
     * @param _nftAmount amount of NFTs to transfer  
     * @param _lockPaymentCondition lock payment condition identifier
     * @param _nftHolder is the address of the account to receive the NFT
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfillForMarket(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftHolder,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _lockPaymentCondition
    )
    public
    
    returns (ConditionStoreLibrary.ConditionState)
    {
        require(hasRole(MARKET_ROLE, msg.sender), 'Invalid access role');
        
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _nftReceiver, _nftAmount, _lockPaymentCondition)
        );

        address lockConditionTypeRef;
        ConditionStoreLibrary.ConditionState lockConditionState;
        (lockConditionTypeRef,lockConditionState,,,,,,) = conditionStoreManager
        .getCondition(_lockPaymentCondition);

        require(
            lockConditionState == ConditionStoreLibrary.ConditionState.Fulfilled,
            'LockCondition needs to be Fulfilled'
        );
        
        require(
            registry.balanceOf(_nftHolder, uint256(_did)) >= _nftAmount,
            'Not enough balance'
        );

        registry.safeTransferFrom(_nftHolder, _nftReceiver, uint256(_did), _nftAmount, '');

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );

        emit Fulfilled(
            _agreementId,
            _did,
            _nftReceiver,
            _nftAmount,
            _id,
            address(registry)
        );

        return state;
    }    

    
   /*
    * @notice fulfill the transfer NFT condition
    * @dev only DID owner or DID provider can call this
    *       method. Fulfill method transfer a certain amount of NFTs 
    *       to the _receiver address. 
    *       When true then fulfill the condition
    * @param _agreementId agreement identifier
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _nftReceiver is the address of the account to receive the NFT
    * @param _nftAmount amount of NFTs to transfer  
    * @param _nftLockCondition lock payment condition identifier
    * @return condition state (Fulfilled/Aborted)
    */
    /*
    function fulfillWithNFTLock(
        bytes32 _agreementId,
        bytes32 _did,
        address _nftReceiver,
        uint256 _nftAmount,
        bytes32 _nftLockCondition
    )
        public
        returns (ConditionStoreLibrary.ConditionState)
    {
        
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _nftReceiver, _nftAmount, _nftLockCondition)
        );

        address lockConditionTypeRef;
        ConditionStoreLibrary.ConditionState lockConditionState;
        (lockConditionTypeRef,lockConditionState,,,,,,) = conditionStoreManager
            .getCondition(_nftLockCondition);

        require(
            lockConditionState == ConditionStoreLibrary.ConditionState.Fulfilled,
            'LockCondition needs to be Fulfilled'
        );
        bytes32 generatedLockConditionId = keccak256(
            abi.encode(
                _agreementId,
                lockConditionTypeRef,
                keccak256(
                    abi.encode(
                        _did,
                        _nftReceiver,
                        _nftAmount
                    )
                )
            )
        );
        
        require(
            generatedLockConditionId == _nftLockCondition,
            'LockCondition ID does not match'
        );

        require(
            registry.balanceOf(lockConditionTypeRef, uint256(_did)) >= _nftAmount,
            'Not enough balance'
        );        
        
        registry.safeTransferFrom(lockConditionTypeRef, _nftReceiver, uint256(_did), _nftAmount, '');

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
        
        emit Fulfilled(
            _agreementId,
            _did,
            _nftReceiver, 
            _nftAmount,
            _id
        );

        return state;
    }
*/    
}

