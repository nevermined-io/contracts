pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../../Common.sol';
import '../../Condition.sol';
import '../../../registry/DIDRegistry.sol';
import './AaveCreditVault.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

/**
 * @title Lock Payment Condition
 * @author Nevermined
 *
 * @dev Implementation of the Aave Repay Condition
 * This condition allows to a borrower to repay a credit as part of a credit template
 */
contract AaveRepayCondition is Condition, Common {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for ERC20Upgradeable;

    AaveCreditVault internal aaveCreditVault;
    
    bytes32 public constant CONDITION_TYPE = keccak256('AaveRepayCondition');
    
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
     * @param _assetToRepay the address of the asset to repay (i.e DAI)  
     * @param _amountToRepay Amount to repay        
     * @param _interestRateMode interest rate type stable 1, variable 2  
     * @return bytes32 hash of all these values 
     */    
    function hashValues(
        bytes32 _did,
        address _vaultAddress,
        address _assetToRepay,
        uint256 _amountToRepay,
        uint256 _interestRateMode
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
                _assetToRepay, 
                _amountToRepay, 
                _interestRateMode
            )
        );
    }

    /**
     * @notice It allows the borrower to repay the loan
     * @param _agreementId the identifier of the agreement     
     * @param _did the DID of the asset
     * @param _vaultAddress the address of vault locking the deposited collateral and the asset
     * @param _assetToRepay the address of the asset to repay (i.e DAI)
     * @param _amountToRepay Amount to repay                  
    * @param _interestRateMode interest rate type stable 1, variable 2  
     * @return ConditionStoreLibrary.ConditionState the state of the condition (Fulfilled if everything went good) 
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _assetToRepay,
        uint256 _amountToRepay,
        uint256 _interestRateMode
    ) 
    external 
    returns (ConditionStoreLibrary.ConditionState) 
    {
        ERC20Upgradeable token = ERC20Upgradeable(_assetToRepay);
        AaveCreditVault vault = AaveCreditVault(_vaultAddress);
        
        uint256 totalDebt = vault.getTotalActualDebt();
        uint256 initialBorrow = vault.getBorrowedAmount();
        require(initialBorrow == _amountToRepay, 'Amount to repay is not the same borrowed amount');

        bytes32 _id = generateId(
            _agreementId,
            hashValues(_did, _vaultAddress, _assetToRepay, _amountToRepay, _interestRateMode)
        );

        ConditionStoreLibrary.ConditionState state = super.fulfill(
            _id,
            ConditionStoreLibrary.ConditionState.Fulfilled
        );
        
        if (state == ConditionStoreLibrary.ConditionState.Fulfilled)    {
            token.safeTransferFrom(msg.sender, _vaultAddress, totalDebt);
            vault.repay(_assetToRepay, _interestRateMode, _id);
        } else if (state == ConditionStoreLibrary.ConditionState.Aborted)    {
            vault.setRepayConditionId(_id);
        }
        return state;
    }
}
