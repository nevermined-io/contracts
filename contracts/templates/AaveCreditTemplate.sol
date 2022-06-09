pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../libraries/CloneFactory.sol';

import './BaseEscrowTemplate.sol';
import '../conditions/rewards/EscrowPaymentCondition.sol';
import '../registry/DIDRegistry.sol';
import '../conditions/NFTs/INFTLock.sol';
import '../conditions/NFTs/DistributeNFTCollateralCondition.sol';
import '../conditions/defi/aave/AaveCollateralDepositCondition.sol';
import '../conditions/defi/aave/AaveBorrowCondition.sol';
import '../conditions/defi/aave/AaveRepayCondition.sol';
import '../conditions/defi/aave/AaveCollateralWithdrawCondition.sol';
import '../conditions/defi/aave/AaveCreditVault.sol';

/**
 * @title Aaven Credit Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of the Aaven Credit Agreement Template
 *  0. Initialize the agreement
 *  1. LockNFT - Delegatee locks the NFT
 *  2. AaveCollateralDeposit - Delegator deposits the collateral into Aave. And approves the delegation flow
 *  3. AaveBorrowCondition - The Delegatee claim the credit amount from Aave
 *  4. AaveRepayCondition. Options:
 *      4.a Fulfilled state - The Delegatee pay back the loan (including fee) into Aave and gets back the NFT
 *      4.b Aborted state - The Delegatee doesn't pay the loan in time so the Delegator gets the NFT. The Delegator pays the loan to Aave
 *  5. TransferNFT. Options:
 *      5.a if AaveRepayCondition was fulfilled, it will allow transfer back to the Delegatee or Borrower
 *      5.b if AaveRepayCondition was aborted, it will allow transfer the NFT to the Delegator or Lender
 */
contract AaveCreditTemplate is BaseEscrowTemplate, CloneFactory {
    DIDRegistry internal didRegistry;

    INFTLock internal nftLockCondition;
    AaveCollateralDepositCondition internal depositCondition;
    AaveBorrowCondition internal borrowCondition;
    AaveRepayCondition internal repayCondition;
    DistributeNFTCollateralCondition internal transferCondition;
    AaveCollateralWithdrawCondition internal withdrawCondition;

    mapping(bytes32 => address) internal vaultAddress;
    uint256 private nvmFee;

    address public vaultLibrary;

    event VaultCreated(
        address indexed _vaultAddress,
        address indexed _creator,
        address _lender,
        address _borrower
    );
    
    /**
    * @notice initialize init the  contract with the following parameters.
    * @dev this function is called only once during the contract
    *       initialization. It initializes the ownable feature, and
    *       set push the required condition types including
    *       access , lock payment and escrow payment conditions.
    * @param _owner contract's owner account address
    * @param _agreementStoreManagerAddress agreement store manager contract address
    * @param _nftLockConditionAddress NFT Lock Condition contract address
    * @param _depositConditionAddress Aave collateral deposit Condition address
    * @param _borrowConditionAddress Aave borrow deposit Condition address
    * @param _repayConditionAddress Aave repay credit Condition address
    * @param _transferConditionAddress NFT Transfer Condition address
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _nftLockConditionAddress,
        address _depositConditionAddress,
        address _borrowConditionAddress,
        address _repayConditionAddress,
        address _withdrawCollateralAddress,
        address _transferConditionAddress,
        address _vaultLibrary
    )
    external
    initializer
    {
        require(
          _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _nftLockConditionAddress != address(0) &&
            _depositConditionAddress != address(0) &&
            _borrowConditionAddress != address(0) &&
            _repayConditionAddress != address(0) &&
            _transferConditionAddress != address(0) &&
            _withdrawCollateralAddress != address(0),
          'Invalid address'
        );
        
        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);
        
        agreementStoreManager = AgreementStoreManager(
          _agreementStoreManagerAddress
        );
        vaultLibrary = _vaultLibrary;
          
        didRegistry = DIDRegistry(agreementStoreManager.getDIDRegistryAddress());
        
        nftLockCondition = INFTLock(_nftLockConditionAddress);
        
        depositCondition = AaveCollateralDepositCondition(_depositConditionAddress);
        
        borrowCondition = AaveBorrowCondition(_borrowConditionAddress);
        
        repayCondition = AaveRepayCondition(_repayConditionAddress);
        
        withdrawCondition = AaveCollateralWithdrawCondition(_withdrawCollateralAddress);
        
        transferCondition = DistributeNFTCollateralCondition(_transferConditionAddress);
        
        conditionTypes.push(address(nftLockCondition));
        conditionTypes.push(address(depositCondition));
        conditionTypes.push(address(borrowCondition));
        conditionTypes.push(address(repayCondition));
        conditionTypes.push(address(withdrawCondition));
        conditionTypes.push(address(transferCondition));
        nvmFee = 2;
    }

    function createVaultAgreement(
        bytes32 _id,
        bytes32 _did,
        bytes32[] memory _conditionIds,
        uint256[] memory _timeLocks,
        uint256[] memory _timeOuts,
        address _vaultAddress
    )
    public
    {
        vaultAddress[keccak256(abi.encode(_id, msg.sender))] = address(_vaultAddress);

        super.createAgreement(
            _id,
            _did,
            _conditionIds,
            _timeLocks,
            _timeOuts,
            msg.sender // borrower
        );
    }
    
    function createAgreement(
        bytes32 _id,
        address _lendingPool,
        address _dataProvider,
        address _weth,
        uint256 _agreementFee,
        address _treasuryAddress,
        bytes32 _did,
        bytes32[] memory _conditionIds,
        uint256[] memory _timeLocks,
        uint256[] memory _timeOuts,
        address _lender
    ) 
    public 
    {
        AaveCreditVault _vault = AaveCreditVault(createClone(vaultLibrary));
        _vault.initialize(
            _lendingPool,
            _dataProvider,
            _weth,
            nvmFee,
            _agreementFee,
            _treasuryAddress,
            msg.sender, // borrower
            _lender,
            conditionTypes
        );
        vaultAddress[keccak256(abi.encode(_id, msg.sender))] = address(_vault);
        emit VaultCreated(address(_vault), msg.sender, _lender, msg.sender);

        super.createAgreement(
            _id,
            _did,
            _conditionIds,
            _timeLocks,
            _timeOuts,
            msg.sender // borrower
        );
    }

    function deployVault(
        address _lendingPool,
        address _dataProvider,
        address _weth,
        uint256 _agreementFee,
        address _treasuryAddress,
        address _borrower,
        address _lender
    )
    public
    returns (address)
    {
        AaveCreditVault _vault = AaveCreditVault(createClone(vaultLibrary));
        _vault.initialize(
            _lendingPool,
            _dataProvider,
            _weth,
            nvmFee,
            _agreementFee,
            _treasuryAddress,
            _borrower, // borrower
            _lender,
            conditionTypes
        );
        emit VaultCreated(address(_vault), msg.sender, _lender, _borrower);
        return address(_vault);
    }

    function getVaultForAgreement(
        bytes32 _agreementId
    )
    public
    view
    returns (address)
    {
        return vaultAddress[_agreementId];
    }

    /**
    * @notice Updates the nevermined fee for this type of agreement
    * @param _newFee New nevermined fee expressed in basis points
    */
    function updateNVMFee(
        uint256 _newFee
    )
    public onlyOwner
    {
        nvmFee = _newFee;
    }

    function changeCreditVaultLibrary(address _vaultLibrary) public onlyOwner {
        vaultLibrary = _vaultLibrary;
    }
}
