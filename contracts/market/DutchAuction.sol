pragma solidity ^0.8.0;

import './AbstractAuction.sol';
// Copyright 2021 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


contract DutchAuction is AbstractAuction {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @notice initialize init the contract with the following parameters
     * @param _owner contract's owner account address
     */
    function initialize(
        address _owner
    )
    external
    initializer()
    {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        transferOwnership(_owner);

        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        AccessControlUpgradeable._setupRole(AUCTION_MANAGER_ROLE, msg.sender);
    }    
    
    /**
     * @notice It creates a new Auction given some setup parameters
     * @param _auctionId unique auction identifier
     * @param _did reference to the asset part of the auction
     * @param _startPrice start price (and max) for the auction
     * @param _starts block number when the auction starts
     * @param _ends block number of when the auction ends
     * @param _tokenAddress token address to use for the auction. If address(0) means native token
     * @param _hash ipfs hash referring to the auction metadata 
     */
    function create(
        bytes32 _auctionId,
        bytes32 _did,
        uint256 _startPrice,
        uint256 _starts,
        uint256 _ends,
        address _tokenAddress,
        string memory _hash
    )
    external
    virtual
    {
        require(_startPrice > 0, 'DutchAuction: Start price should be more than 0');
        require(_starts > block.number, 'DutchAuction: Can not start in the past');
        require(_ends > _starts, 'DutchAuction: Must last at least one block');

        require(
            auctions[_auctionId].creator == address(0x0),
            'DutchAuction: Already created'
        );

        auctions[_auctionId] = Auction({
            did: _did,
            state: DynamicPricingState.NotStarted,
            creator: msg.sender,
            blockNumberCreated: block.number,
            floor: _startPrice,
            starts: _starts,
            ends: _ends,
            price: 0,
            tokenAddress: _tokenAddress,
            whoCanClaim: address(0),
            hash: _hash
        });

        emit AuctionCreated(
            _auctionId,
            _did,
            msg.sender,
            block.number,
            _startPrice,
            _starts,
            _ends,
            _tokenAddress
        );
    }

    function placeNativeTokenBid(
        bytes32 _auctionId
    )
    external
    virtual
    payable
    nonReentrant
    onlyNotCreator(_auctionId)
    onlyNotAbortedOrFinished(_auctionId)
    onlyAfterStart(_auctionId)
    onlyBeforeEnd(_auctionId)
    {
        require(auctions[_auctionId].tokenAddress == address(0), 'DutchAuction: Only native token accepted');
        uint256 _bidAmount = msg.value;
        require(_bidAmount <= auctions[_auctionId].floor, 'DutchAuction: Only lower or equal than start price');
        require(_bidAmount > auctions[_auctionId].price, 'DutchAuction: Only higher bids');
        
        auctions[_auctionId].whoCanClaim = msg.sender;
        auctions[_auctionId].price = _bidAmount;
        auctionBids[_auctionId][msg.sender] = _bidAmount;
        auctions[_auctionId].state = DynamicPricingState.Finished;

        emit AuctionBidReceived(
            _auctionId,
            msg.sender,
            auctions[_auctionId].tokenAddress,
            _bidAmount
        );
        emit AuctionChangedState(
            _auctionId,
            msg.sender,
            DynamicPricingState.InProgress,
            DynamicPricingState.Finished
        );
        // solhint-disable-next-line
        (bool sent, ) = payable(address(this)).call{value: msg.value}('');
        require(sent, 'DutchAuction: Failed to send native token');

    }

    function placeERC20Bid(
        bytes32 _auctionId,
        uint256 _bidAmount
    )
    external
    virtual
    nonReentrant
    onlyNotCreator(_auctionId)
    onlyNotAbortedOrFinished(_auctionId)
    onlyAfterStart(_auctionId)
    onlyBeforeEnd(_auctionId)
    {
        require(auctions[_auctionId].tokenAddress != address(0), 'DutchAuction: Only ERC20');

        require(_bidAmount <= auctions[_auctionId].floor, 'DutchAuction: Only lower or equal than start price');
        require(_bidAmount > auctions[_auctionId].price, 'DutchAuction: Only higher bids');

        IERC20Upgradeable token = ERC20Upgradeable(auctions[_auctionId].tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _bidAmount);

        auctions[_auctionId].whoCanClaim = msg.sender;
        auctions[_auctionId].price = _bidAmount;
        auctionBids[_auctionId][msg.sender] = _bidAmount;
        auctions[_auctionId].state = DynamicPricingState.Finished;
        
        emit AuctionBidReceived(
            _auctionId,
            msg.sender,
            auctions[_auctionId].tokenAddress,
            _bidAmount
        );
        emit AuctionChangedState(
            _auctionId,
            msg.sender,
            DynamicPricingState.InProgress,
            DynamicPricingState.Finished
        );        
    }

    function withdraw(
        bytes32 _auctionId,
        address _withdrawAddress
    )
    external
    override
    onlyAbortedOrFinished(_auctionId)
    virtual
    returns(bool)
    {
//        require(onlyAbortedOrFinished(_auctionId), 'AbstractAuction: Only not aborted or finished');

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
            }
        }

        require(withdrawalAmount > 0, 'DutchAuction: Zero amount');

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
    override
    returns(bytes32)
    {
        return keccak256('DutchAuction');
    }
    
  
    
}
