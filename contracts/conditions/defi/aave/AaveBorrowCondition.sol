pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../Condition.sol';
import '../../../registry/DIDRegistry.sol';
import '../../../Common.sol';
import './AaveCreditVault.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';

/**
 * @title Aave Borrow Credit Condition
 * @author Nevermined
 *
 * @dev Implementation of the Aave Borrow Credit Condition
 */
contract AaveBorrowCondition is Condition, Common {
    
    AaveCreditVault internal aaveCreditVault;

    bytes32 public constant CONDITION_TYPE = keccak256('AaveBorrowCondition');

    event Fulfilled(
        bytes32 indexed _agreementId,
        bytes32 indexed _did,
        bytes32 indexed _conditionId
    );

    /**
     * @notice initialize init the contract with the following parameters
     * @dev this function is called only once during the contract initialization.
     * @param _owner contract's owner account address
     * @param _conditionStoreManagerAddress condition store manager address
     */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress
    ) 
    external
    initializer
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
     * @param _did the DID of the asset
     * @param _vaultAddress the address of vault locking the deposited collateral and the asset
     * @param _assetToBorrow the address of the asset to borrow (i.e DAI)     
     * @param _amount the amount of the ERC-20 the assets to borrow (i.e 50 DAI)   
     * @param _interestRateMode interest rate type stable 1, variable 2  
     * @return bytes32 hash of all these values 
     */
    function hashValues(
        bytes32 _did,
        address _vaultAddress,
        address _assetToBorrow,
        uint256 _amount,
        uint256 _interestRateMode
    ) 
    public 
    pure 
    returns (bytes32) 
    {
        return
        keccak256(
            abi.encode(
                CONDITION_TYPE,
                _did,
                _vaultAddress,
                _assetToBorrow,
                _amount,
                _interestRateMode
            )
        );
    }

    /**
     * @notice It allows the borrower to borrow the asset deposited by the lender
     * @param _agreementId the identifier of the agreement     
     * @param _did the DID of the asset
     * @param _vaultAddress the address of vault locking the deposited collateral and the asset
     * @param _assetToBorrow the address of the asset to borrow (i.e DAI)     
     * @param _amount the amount of the ERC-20 the assets to borrow (i.e 50 DAI)   
     * @param _interestRateMode interest rate type stable 1, variable 2  
     * @return ConditionStoreLibrary.ConditionState the state of the condition (Fulfilled if everything went good) 
     */    
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _assetToBorrow,
        uint256 _amount,
        uint256 _interestRateMode
    ) 
    external 
    returns (ConditionStoreLibrary.ConditionState) 
    {
        AaveCreditVault vault = AaveCreditVault(_vaultAddress);
        require(vault.isBorrower(msg.sender), 'Only borrower');
        vault.borrow(_assetToBorrow, _amount, msg.sender, _interestRateMode);

        bytes32 _id =
        generateId(
            _agreementId,
            hashValues(_did, _vaultAddress, _assetToBorrow, _amount, _interestRateMode)
        );

        ConditionStoreLibrary.ConditionState state =
        super.fulfill(_id, ConditionStoreLibrary.ConditionState.Fulfilled);

        return state;
    }
}
