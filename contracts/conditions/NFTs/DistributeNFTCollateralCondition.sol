pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../Condition.sol';
import '../../registry/DIDRegistry.sol';
import '../defi/aave/AaveCreditVault.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';

/**
 * @title Distribute NFT Collateral Condition
 * @author Nevermined
 *
 * @dev Implementation of a condition allowing to transfer a NFT
 *      to an account or another depending on the final state of a lock condition
 */
contract DistributeNFTCollateralCondition is Condition, ReentrancyGuardUpgradeable {

    bytes32 private constant CONDITION_TYPE = keccak256('DistributeNFTCollateralCondition');

    AaveCreditVault internal aaveCreditVault;

    address private _lockConditionAddress;


    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        address indexed _receiver,
        bytes32 _conditionId,
        address _contract
    );    
    
   /**
    * @notice initialize init the contract with the following parameters
    * @dev this function is called only once during the contract
    *       initialization.
    * @param _owner contract's owner account address
    * @param _conditionStoreManagerAddress condition store manager address    
    * @param _lockNFTConditionAddress Lock NFT Condition address
    */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _lockNFTConditionAddress
    )
        external
        initializer
    {
        require(
            _owner != address(0) &&
            _conditionStoreManagerAddress != address(0) &&
            _lockNFTConditionAddress != address(0),
            'Invalid address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        _lockConditionAddress = _lockNFTConditionAddress;
    }

   /**
    * @notice hashValues generates the hash of condition inputs 
    *        with the following parameters
    * @param _did refers to the DID in which secret store will issue the decryption keys
    * @param _vaultAddress The contract address of the vault
    * @param _nftContractAddress NFT contract to use
    * @return bytes32 hash of all these values 
    */
    function hashValues(
        bytes32 _did,
        address _vaultAddress,     
        address _nftContractAddress
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                CONDITION_TYPE,
                _did, 
                _vaultAddress, 
                _nftContractAddress
            )
        );
    }

    /**
     * @notice fulfill the transfer NFT condition
     * @dev Fulfill method transfer a certain amount of NFTs 
     *       to the _nftReceiver address. 
     *       When true then fulfill the condition
     * @param _agreementId agreement identifier
     * @param _did refers to the DID in which secret store will issue the decryption keys
     * @param _vaultAddress The contract address of the vault
     * @param _nftContractAddress NFT contract to use
     * @return condition state (Fulfilled/Aborted)
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _nftContractAddress
    )
        public
        nonReentrant
        returns (ConditionStoreLibrary.ConditionState)
    {

        AaveCreditVault vault = AaveCreditVault(_vaultAddress);
        require(vault.isBorrower(msg.sender) || vault.isLender(msg.sender),
            'Invalid sender, only borrower or lender can request Nft transfer under this agreement.'
        );
        
        ConditionStoreLibrary.ConditionState repayConditionState;
        (,repayConditionState,,,) = conditionStoreManager
            .getCondition(vault.repayConditionId());

        IERC721Upgradeable token = IERC721Upgradeable(_nftContractAddress);
        require(
            (_vaultAddress == token.ownerOf(uint256(_did))),
            'The credit vault is not owner of this NFT or does not have sufficient balance.'
        );

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _vaultAddress, _nftContractAddress)
        );

        if (repayConditionState == ConditionStoreLibrary.ConditionState.Fulfilled) {
            vault.transferNFT(uint256(_did), vault.borrower());
            emit Fulfilled(_agreementId, _did, vault.borrower(), _id, _nftContractAddress);
        } else if (repayConditionState == ConditionStoreLibrary.ConditionState.Aborted) {
            vault.transferNFT(uint256(_did), vault.lender());
            emit Fulfilled(_agreementId, _did, vault.lender(), _id, _nftContractAddress);
        }   else {
            require(false, 'Still not fulfilled or aborted');
        }
        
        return super.fulfill(_id, ConditionStoreLibrary.ConditionState.Fulfilled);

    }    
    
}

