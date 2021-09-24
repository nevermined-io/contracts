pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import {IERC20, ILendingPool, ILendingPoolAddressesProvider, IProtocolDataProvider, IStableDebtToken, IPriceOracleGetter} from "../../../interfaces/IAaveInterfaces.sol";
import {SafeERC20, SafeMath} from "../../../libraries/AaveLibrary.sol";
import "../../../interfaces/IWETHGateway.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract AaveCreditVault is
  ReentrancyGuardUpgradeable,
  IERC721ReceiverUpgradeable
{
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  ILendingPool private lendingPool;
  IProtocolDataProvider private dataProvider;
  IWETHGateway private weth;
  ILendingPoolAddressesProvider private addressProvider;
  IPriceOracleGetter private priceOracle;
  address private borrowedAsset;
  uint256 private borrowedAmount;
  uint256 private nvmFee;
  uint256 private agreementFee;
  uint256 private constant FEE_BASE = 10000;
  address private treasuryAddress;

  /**
   * Vault constructor, creates a unique vault for each agreement
   * @param _lendingPool Aave lending pool address
   * @param _dataProvider Aave data provider address
   * @param _weth WETH address
   * @param _nvmFee Nevermined fee that will apply to this agreeement
   * @param _agreementFee Agreement fee that lender will receive on agreement maturity
   */
  constructor(
    address _lendingPool,
    address _dataProvider,
    address _weth,
    uint256 _nvmFee,
    uint256 _agreementFee,
    address _treasuryAddress
  ) public {
    lendingPool = ILendingPool(_lendingPool);
    dataProvider = IProtocolDataProvider(_dataProvider);
    weth = IWETHGateway(_weth);
    addressProvider = lendingPool.getAddressesProvider();
    priceOracle = IPriceOracleGetter(addressProvider.getPriceOracle());
    nvmFee = _nvmFee;
    agreementFee = _agreementFee;
    treasuryAddress = _treasuryAddress;
  }

  /**
   * Deposit function. Receives the funds from the delegator and deposits the funds
   * in the Aave contracts
   * @param _collateralAsset collateral asset that will be deposit on Aave
   * @param _amount Amount of collateral to deposit
   */
  function deposit(address _collateralAsset, uint256 _amount)
    public
    payable
    nonReentrant
  {
    if (msg.value == 0) _transferERC20(_collateralAsset, _amount);
    else {
      weth.depositETH{value: msg.value}(address(lendingPool), address(this), 0);
    }
  }

  /**
   * Appproves delegatee to borrow funds from Aave on behalf of delegator
   * @param borrower delegatee that will borrow the funds
   * @param amount Amount of funds to delegate
   * @param asset Asset to delegate the borrow
   */
  function approveBorrower(
    address borrower,
    uint256 amount,
    address asset
  ) public {
    (, address stableDebtTokenAddress, ) = dataProvider
      .getReserveTokensAddresses(asset);
    IStableDebtToken(stableDebtTokenAddress).approveDelegation(
      borrower,
      amount
    );
  }

  /**
   * Return the actual delegated amount for the borrower in the specific asset
   * @param borrower The borrower of the funds (i.e. delgatee)
   * @param asset The asset they are allowed to borrow
   */
  function delegatedAmount(address borrower, address asset)
    public
    view
    returns (uint256)
  {
    (, address stableDebtTokenAddress, ) = dataProvider
      .getReserveTokensAddresses(asset);

    return
      IStableDebtToken(stableDebtTokenAddress).borrowAllowance(
        address(this),
        borrower
      );
  }

  /**
   * Borrower can call this function to borrow the delegated funds
   * @param _assetToBorrow The asset they are allowed to borrow
   * @param _amount Amount to borrow
   * @param _delgatee Address where the funds will be transfered
   */
  function borrow(
    address _assetToBorrow,
    uint256 _amount,
    address _delgatee
  ) public {
    borrowedAsset = _assetToBorrow;
    borrowedAmount = _amount;
    lendingPool.borrow(_assetToBorrow, _amount, 1, 0, address(this));
    IERC20(_assetToBorrow).transfer(_delgatee, _amount);
  }

  /**
   * Repay an uncollaterised loan
   * @param _asset The asset to be repaid
   */
  function repay(address _asset) public returns (uint256) {
    IERC20(_asset).approve(address(lendingPool), uint256(-1));
    lendingPool.repay(_asset, uint256(-1), 1, address(this));

    require(getActualCreditDebt() == 0, "Not enough amount to repay");
  }

  /**
   * Returns the borrowed amount from the delegatee on this agreement
   */
  function getBorrowedAmount() public view returns (uint256) {
    return borrowedAmount;
  }

  /**
   * Returns the priceof the asset in the Aave oracles
   * @param _asset The asset to get the actual price
   */
  function getAssetPrice(address _asset) public view returns (uint256) {
    return priceOracle.getAssetPrice(_asset);
  }


  /**
   * Returns the total debt of the credit in the Aave protocol expressed in token units
   */
  function getCreditAssetDebt() public view returns (uint256) {
    (, uint256 totalDebtETH, , , , ) = lendingPool.getUserAccountData(
      address(this)
    );
    uint256 price = priceOracle.getAssetPrice(borrowedAsset);
    (uint256 _decimals, , , , , , , , , ) = dataProvider
      .getReserveConfigurationData(borrowedAsset);

    return totalDebtETH.div(price).mul(10**_decimals);
  }

  /**
   * Returns the total debt of the credit in the Aave protocol expressed in ETH units
   */
  function getActualCreditDebt() public view returns (uint256) {
    (, uint256 totalDebtETH, , , , ) = lendingPool.getUserAccountData(
      address(this)
    );

    return totalDebtETH;
  }


  /**
   * Returns the total actual debt of the agreement credit + fees in token units
   */
  function getTotalActualDebt() public view returns (uint256) {
    uint256 creditDebt = getCreditAssetDebt();
    uint256 delegatorFee = borrowedAmount.div(FEE_BASE).mul(agreementFee);
    uint256 nvmFeeAmount = borrowedAmount.div(FEE_BASE).mul(nvmFee);

    return creditDebt.add(delegatorFee).add(nvmFeeAmount);
  }

  /**
   * Withdraw all of a collateral as the underlying asset, if no outstanding loans delegated
   * @param _asset The underlying asset to withdraw
   * @param _delegator Delegator address that deposited the collateral
   */
  function withdrawCollateral(address _asset, address _delegator) public {
    lendingPool.withdraw(_asset, uint256(-1), _delegator);
    uint256 delegatorFee = borrowedAmount.div(FEE_BASE).mul(agreementFee);
    IERC20(borrowedAsset).transfer(_delegator, delegatorFee);
    uint256 finalBalance = IERC20(borrowedAsset).balanceOf(address(this));
    IERC20(borrowedAsset).transfer(treasuryAddress, finalBalance);
  }


  /**
   * Transfers the ERC20 token deposited to the Aave contracts
   * @param _collateralAsset collateral asset that will be deposit on Aave
   * @param _amount Amount of collateral to deposit
   */
  function _transferERC20(address _collateralAsset, uint256 _amount) internal {
    IERC20Upgradeable token = ERC20Upgradeable(_collateralAsset);
    token.approve(address(lendingPool), _amount);
    lendingPool.deposit(_collateralAsset, _amount, address(this), 0);
  }

  /**
   * Always returns `IERC721Receiver.onERC721Received.selector`.
   */
  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) public virtual override returns (bytes4) {
    return this.onERC721Received.selector;
  }
}
