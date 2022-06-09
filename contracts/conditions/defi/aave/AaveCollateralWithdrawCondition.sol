pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../Condition.sol';
import '../../../registry/DIDRegistry.sol';
import './AaveCreditVault.sol';
import '../../../Common.sol';
import '../../../templates/AaveCreditTemplate.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';

/**
 * @title Aave Collateral Withdraw Condition
 * @author Nevermined
 *
 * @dev Implementation of the Collateral Withdraw Condition
 * This condition allows to credit delegator withdraw the collateral and fees
 * after the agreement expiration
 */
contract AaveCollateralWithdrawCondition is
    Condition,
    Common,
    ReentrancyGuardUpgradeable {

    AaveCreditVault internal aaveCreditVault;
    
    bytes32 public constant CONDITION_TYPE = keccak256('AaveCollateralWithdrawCondition');
    
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
     * @param _vaultAddress Address of the vault
     * @param _collateralAsset the address of the asset used as collateral (i.e DAI) 
     * @return bytes32 hash of all these values 
     */
    function hashValues(
        bytes32 _did,
        address _vaultAddress,
        address _collateralAsset

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
                    _collateralAsset
                )
        );
    }


    /**
     * @notice It allows the borrower to repay the loan
     * @param _agreementId the identifier of the agreement     
     * @param _did the DID of the asset
     * @param _vaultAddress Address of the vault     
     * @param _collateralAsset the address of the asset used as collateral (i.e DAI)
     * @return ConditionStoreLibrary.ConditionState the state of the condition (Fulfilled if everything went good) 
     */    
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _collateralAsset
    )
    external
    payable
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState)
    {
        // Withdraw the collateral from the Aave Lending pool contract and the agreement fees
        AaveCreditVault vault = AaveCreditVault(_vaultAddress);
        require(vault.isLender(msg.sender), 'Only lender');

        address lockConditionTypeRef;
        ConditionStoreLibrary.ConditionState repayConditionState;
        (lockConditionTypeRef,repayConditionState,,,) = conditionStoreManager
            .getCondition(vault.repayConditionId());

        require(
            repayConditionState == ConditionStoreLibrary.ConditionState.Fulfilled,
            'Repay Condition needs to be Fulfilled'
        );        
        
        vault.withdrawCollateral(_collateralAsset, vault.lender());
        
        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _vaultAddress, _collateralAsset)
        );
        
        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
        
        return state;
    }
}
