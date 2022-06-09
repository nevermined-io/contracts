pragma solidity ^0.8.0;
// Copyright 2021 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../interfaces/IDynamicPricing.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

/**
 * @title Interface that can implement different contracts implementing some kind of 
 * dynamic pricing functionality.
 * @author Nevermined
 */

abstract contract AbstractAuction is 
    IDynamicPricing, Initializable, OwnableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant AUCTION_MANAGER_ROLE = keccak256('AUCTIONS_MANAGER');
    bytes32 public constant NVM_AGREEMENT_ROLE = keccak256('NVM_SERVICE_AGREEMENTS_CONTRACT');
    
    struct Auction {
        // Asset associated to the auction
        bytes32 did;
        // State of the auction
        DynamicPricingState state;
        // Who created the auction
        address creator;
        // When was created
        uint256 blockNumberCreated;
        // Price floor
        uint256 floor;
        // When this auction starts
        uint256 starts;
        // When this auction ends
        uint256 ends;
        // Auction price
        uint256 price;
        // Token address used for the price. If address(0) means native token
        address tokenAddress;        
        // Who is the winner of the auction
        address whoCanClaim;
        // IPFS hash
        string hash;
    }
//    
//    struct UserBids {
//        mapping(address => uint256) userBids;
//    }

    // auctionId -> Auction
    mapping(bytes32 => Auction) internal auctions;
    // auctionId -> (userAddress -> amounts)
    mapping(bytes32 => mapping(address => uint256)) internal auctionBids;
    
    
    event AuctionCreated(
        bytes32 indexed auctionId,
        bytes32 indexed did,
        address indexed creator,
        uint256 blockNumberCreated,
        uint256 floor,
        uint256 starts,
        uint256 ends,
        address tokenAddress
    );

    event AuctionChangedState(
        bytes32 indexed auctionId,
        address indexed who,
        DynamicPricingState previousState,
        DynamicPricingState newState
    );    
    
    event AuctionBidReceived(
        bytes32 indexed auctionId,
        address indexed bidder,
        address tokenAddress,
        uint256 amount
    );

    event AuctionWithdrawal(
        bytes32 indexed auctionId,
        address indexed receiver,
        address tokenAddress,
        uint256 amount
    );
    
    receive() external payable {
    }    
    
    function abortAuction(
        bytes32 _auctionId
    )
    external
    virtual
    onlyCreatorOrAdmin(_auctionId)
    onlyBeforeStarts(_auctionId)
    onlyNotAborted(_auctionId)
    {
        emit AuctionChangedState(
            _auctionId,
            msg.sender,
            auctions[_auctionId].state,
            DynamicPricingState.Aborted
        );
        auctions[_auctionId].state = DynamicPricingState.Aborted;
    }
    
    function withdraw(
        bytes32 _auctionId,
        address _withdrawAddress
    )
    external
    virtual
    returns(bool)
    {

        if (auctions[_auctionId].state == DynamicPricingState.InProgress)   {
            require(block.number > auctions[_auctionId].ends, 'AbstractAuction: Auction not finished yet');
            auctions[_auctionId].state = DynamicPricingState.Finished;
            emit AuctionChangedState(
                _auctionId,
                msg.sender,
                DynamicPricingState.InProgress,
                DynamicPricingState.Finished
            );
        }

        address withdrawalAddress;
        uint256 withdrawalAmount;

        if (auctions[_auctionId].state == DynamicPricingState.Aborted) {
            // The action was aborted so participants should be able to get a refund
            if (_withdrawAddress != address(0))
                withdrawalAddress = _withdrawAddress;
            else
                withdrawalAddress = msg.sender;
            withdrawalAmount = auctionBids[_auctionId][msg.sender];
 
        }   else    {
            
            // The auction finished correctly
            if (msg.sender == auctions[_auctionId].creator)   { // The creator of the auction cant withdraw
                return false;
            } else if (msg.sender == auctions[_auctionId].whoCanClaim)    { // The winner of the auction cant withdraw
                return false;
            } else if (hasRole(NVM_AGREEMENT_ROLE, msg.sender)) { // Approved proxy or contract can withdraw for locking into service agreements
                if (_withdrawAddress != address(0))
                    withdrawalAddress = _withdrawAddress;
                else
                    withdrawalAddress = msg.sender;
                withdrawalAmount = auctionBids[_auctionId][auctions[_auctionId].whoCanClaim];
                auctionBids[_auctionId][auctions[_auctionId].whoCanClaim] = 0;
            } else if (auctionBids[_auctionId][msg.sender] > 0)    { // A participant not winning can withdraw
                if (_withdrawAddress != address(0))
                    withdrawalAddress = _withdrawAddress;
                else
                    withdrawalAddress = msg.sender;
                withdrawalAmount = auctionBids[_auctionId][msg.sender];
                auctionBids[_auctionId][msg.sender] = 0;
            }
        }

        require(withdrawalAmount > 0, 'AbstractAuction: Zero amount');
        
        if (auctions[_auctionId].tokenAddress == address(0))  { // ETH Withdrawal
            // solhint-disable-next-line
            (bool sent,) = withdrawalAddress.call{value: withdrawalAmount}('');
            require(sent, 'AbstractAuction: Failed to send Ether');
            
        }   else { // ERC20 Withdrawal
            IERC20Upgradeable token = ERC20Upgradeable(auctions[_auctionId].tokenAddress);
            token.safeApprove(withdrawalAddress, withdrawalAmount);
            token.safeTransfer(withdrawalAddress, withdrawalAmount);
        }
        
        emit AuctionWithdrawal(
            _auctionId, 
            withdrawalAddress,
            auctions[_auctionId].tokenAddress, 
            withdrawalAmount
        );
        return true;
    }
    
    function getPricingType()
    external
    pure
    virtual
    returns(bytes32)
    {
        return keccak256('AbstractAuction');
    }

    function getPrice(
        bytes32 _auctionId
    )
    external
    view
    returns(uint256)
    {
        return auctions[_auctionId].price;
    }

    function getTokenAddress(
        bytes32 _auctionId
    )
    external
    view
    returns(address)
    {
        return auctions[_auctionId].tokenAddress;
    }    
    
    function getStatus(
        bytes32 _auctionId
    )
    external
    view
    returns(
        DynamicPricingState state, 
        uint256 price, 
        address whoCanClaim
    )
    {
        state = auctions[_auctionId].state;
        price = auctions[_auctionId].price;
        whoCanClaim = auctions[_auctionId].whoCanClaim;
    }

    function canBePurchased(
        bytes32 _auctionId
    )
    external
    virtual
    view
    returns(bool)
    {
        return auctions[_auctionId].state == DynamicPricingState.Finished;
    }

    function addNVMAgreementRole(address account) public onlyOwner {
        AccessControlUpgradeable._setupRole(NVM_AGREEMENT_ROLE, account);
    }

    modifier onlyCreator(bytes32 _auctionId) {
        require(msg.sender == auctions[_auctionId].creator, 'AbstractAuction: Only creator');
        _;
    }

    modifier onlyCreatorOrAdmin(bytes32 _auctionId) {
        require(
            msg.sender == auctions[_auctionId].creator || hasRole(AUCTION_MANAGER_ROLE, msg.sender), 
            'AbstractAuction: Only creator or admin');
        _;
    }    
    
    modifier onlyNotCreator(bytes32 _auctionId) {
        require(msg.sender != auctions[_auctionId].creator, 'AbstractAuction: Not creator');
        _;
    }
    
    modifier onlyAfterStart(bytes32 _auctionId) {
        require(block.number > auctions[_auctionId].starts, 'AbstractAuction: Only after starts');
        _;
    }

    modifier onlyBeforeStarts(bytes32 _auctionId) {
        require(block.number < auctions[_auctionId].starts, 'AbstractAuction: Only before starts');
        _;
    }    
    
    modifier onlyBeforeEnd(bytes32 _auctionId) {
        require(block.number < auctions[_auctionId].ends, 'AbstractAuction: Only before ends');
        _;
    }

    modifier onlyNotAbortedOrFinished(bytes32 _auctionId) {
        require(auctions[_auctionId].state != DynamicPricingState.Aborted &&
            auctions[_auctionId].state != DynamicPricingState.Finished, 'AbstractAuction: Only not aborted or finished');
        _;
    }

    modifier onlyAbortedOrFinished(bytes32 _auctionId) {
        require(auctions[_auctionId].state == DynamicPricingState.Aborted ||
            auctions[_auctionId].state == DynamicPricingState.Finished, 'AbstractAuction: Only aborted or finished');
        _;
    }

    modifier onlyNotAborted(bytes32 _auctionId) {
        require(auctions[_auctionId].state != DynamicPricingState.Aborted , 'AbstractAuction: Only not aborted');
        _;
    }

    modifier onlyFinishedOrAborted(bytes32 _auctionId) {
        require(
            auctions[_auctionId].state == DynamicPricingState.Aborted ||
            auctions[_auctionId].state == DynamicPricingState.Finished
            , 'AbstractAuction: Only finished or aborted');
        _;
    }    
    
}
