pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import '../../Condition.sol';
import '../../../registry/DIDRegistry.sol';
import './AaveCreditVault.sol';
import '../../../Common.sol';
import '../../../templates/AaveCreditTemplate.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';

/**
 * @title Aave Collateral Deposit Condition
 * @author Keyko
 *
 * @dev Implementation of the Aave Collateral Deposit Condition
 * This condition allows a Lender to deposit the collateral that 
 * into account the royalties to be paid to the original creators in a secondary market.
 */
contract AaveCollateralDepositCondition is Condition, Common, ReentrancyGuardUpgradeable {
    
    DIDRegistry internal didRegistry;
    AaveCreditVault internal aaveCreditVault;

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
     * @param _didRegistryAddress DID Registry address
     */
    function initialize(
        address _owner,
        address _conditionStoreManagerAddress,
        address _didRegistryAddress
    ) 
    external 
    initializer() 
    {
        
        require(
            _didRegistryAddress != address(0) &&
            _conditionStoreManagerAddress != address(0),
            'Invalid address'
        );
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        conditionStoreManager = ConditionStoreManager(
            _conditionStoreManagerAddress
        );

        didRegistry = DIDRegistry(_didRegistryAddress);
    }

    /**
     * @notice hashValues generates the hash of condition inputs 
     *        with the following parameters
     * @param _did the DID of the asset
     * @param _borrower the address of the borrower/delegatee
     * @param _collateralAsset the address of the ERC-20 that will be used as collateral (i.e WETH)     
     * @param _collateralAmount the amount of the ERC-20 that will be used as collateral (i.e 10 WETH)   
     * @param _delegatedAsset the address of the ERC-20 that will be delegated to the borrower (i.e DAI)
     * @param _delegatedAmount the amount of the ERC-20 that will be delegated to the borrower (i.e 500 DAI)
     * @return bytes32 hash of all these values 
     */    
    function hashValues(
        bytes32 _did,
        address _borrower,
        address _collateralAsset,
        uint256 _collateralAmount,
        address _delegatedAsset,
        uint256 _delegatedAmount
    ) 
    public 
    pure 
    returns (bytes32) {
        return
        keccak256(
            abi.encode(
                _did,
                _borrower,
                _collateralAsset,
                _delegatedAsset,
                _delegatedAmount,
                _collateralAmount
            )
        );
    }


    /**
     * @notice It fulfills the condition if the collateral can be deposited into the vault
     * @param _agreementId the identifier of the agreement     
     * @param _did the DID of the asset
     * @param _borrower the address of the borrower/delegatee
     * @param _collateralAsset the address of the ERC-20 that will be used as collateral (i.e WETH)     
     * @param _collateralAmount the amount of the ERC-20 that will be used as collateral (i.e 10 WETH)   
     * @param _delegatedAsset the address of the ERC-20 that will be delegated to the borrower (i.e DAI)
     * @param _delegatedAmount the amount of the ERC-20 that will be delegated to the borrower (i.e 500 DAI)
     * @return ConditionStoreLibrary.ConditionState the state of the condition (Fulfilled if everything went good) 
     */
    function fulfill(
        bytes32 _agreementId,
        bytes32 _did,
        address _vaultAddress,
        address _borrower,
        address _collateralAsset,
        address _delegatedAsset,
        uint256 _delegatedAmount,
        uint256 _collateralAmount
    ) 
    external 
    payable
    nonReentrant
    returns (ConditionStoreLibrary.ConditionState) {
        //Deposits the collateral in the Aave Lending pool contract

        AaveCreditVault vault = AaveCreditVault(_vaultAddress);

        if (msg.value == 0) {
            IERC20Upgradeable token = ERC20Upgradeable(_collateralAsset);
            token.transferFrom(
                msg.sender,
                address(vault),
                _collateralAmount
            );
        }

        vault.deposit{value: msg.value}(_collateralAsset, _collateralAmount);
        vault.approveBorrower(_borrower, _delegatedAmount, _delegatedAsset);

        bytes32 _id =
        generateId(
            _agreementId,
            hashValues(
                _did,
                _borrower,
                _collateralAsset,
                _collateralAmount,
                _delegatedAsset,
                _delegatedAmount
            )
        );

        ConditionStoreLibrary.ConditionState state =
            super.fulfill(_id, ConditionStoreLibrary.ConditionState.Fulfilled);

        return state;
    }
}
