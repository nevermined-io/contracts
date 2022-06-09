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
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

/**
 * @title Aave Collateral Deposit Condition
 * @author Nevermined
 *
 * @dev Implementation of the Aave Collateral Deposit Condition
 * This condition allows a Lender to deposit the collateral that 
 * into account the royalties to be paid to the original creators in a secondary market.
 */
contract AaveCollateralDepositCondition is Condition, Common, ReentrancyGuardUpgradeable {
    
    AaveCreditVault internal aaveCreditVault;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant CONDITION_TYPE = keccak256('AaveCollateralDepositCondition');

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
     * @param _collateralAsset the address of the ERC-20 that will be used as collateral (i.e WETH)     
     * @param _collateralAmount the amount of the ERC-20 that will be used as collateral (i.e 10 WETH)   
     * @param _delegatedAsset the address of the ERC-20 that will be delegated to the borrower (i.e DAI)
     * @param _delegatedAmount the amount of the ERC-20 that will be delegated to the borrower (i.e 500 DAI)
     * @param _interestRateMode interest rate type stable 1, variable 2
     * @return bytes32 hash of all these values 
     */    
    function hashValues(
        bytes32 _did,
        address _vaultAddress,
        address _collateralAsset,
        uint256 _collateralAmount,
        address _delegatedAsset,
        uint256 _delegatedAmount,
        uint256 _interestRateMode
    ) 
    public 
    pure 
    returns (bytes32) {
        return
        keccak256(
            abi.encode(
                CONDITION_TYPE,
                _did,
                _vaultAddress,
                _collateralAsset,
                _collateralAmount,
                _delegatedAsset,
                _delegatedAmount,
                _interestRateMode
            )
        );
    }


    /**
     * @notice It fulfills the condition if the collateral can be deposited into the vault
     * @param _agreementId the identifier of the agreement     
     * @param _did the DID of the asset
     * @param _vaultAddress Address of the vault
     * @param _collateralAsset the address of the ERC-20 that will be used as collateral (i.e WETH)     
     * @param _collateralAmount the amount of the ERC-20 that will be used as collateral (i.e 10 WETH)   
     * @param _delegatedAsset the address of the ERC-20 that will be delegated to the borrower (i.e DAI)
     * @param _delegatedAmount the amount of the ERC-20 that will be delegated to the borrower (i.e 500 DAI)
     * @param _interestRateMode interest rate type stable 1, variable 2
     * @return ConditionStoreLibrary.ConditionState the state of the condition (Fulfilled if everything went good) 
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _collateralAsset,
        uint256 _collateralAmount,
        address _delegatedAsset,
        uint256 _delegatedAmount,
        uint256 _interestRateMode
    ) 
    external 
    payable
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState) {
        //Deposits the collateral in the Aave Lending pool contract

        AaveCreditVault vault = AaveCreditVault(_vaultAddress);
        require(
            vault.nftId() == uint256(_did),
            'The nft token locked in the vault does not match this did.'
        );
    
        if (msg.value == 0) {
            IERC20Upgradeable token = ERC20Upgradeable(_collateralAsset);
            token.safeTransferFrom(
                msg.sender,
                address(vault),
                _collateralAmount
            );
        }

        vault.deposit{value: msg.value}(_collateralAsset, _collateralAmount);
        vault.approveBorrower(vault.borrower(), _delegatedAmount, _delegatedAsset, _interestRateMode);

        bytes32 _id =
        generateId(
            _agreementId,
            hashValues(
                _did,
                _vaultAddress,
                _collateralAsset,
                _collateralAmount,
                _delegatedAsset,
                _delegatedAmount,
                _interestRateMode
            )
        );

        ConditionStoreLibrary.ConditionState state =
            super.fulfill(_id, ConditionStoreLibrary.ConditionState.Fulfilled);

        return state;
    }
}
