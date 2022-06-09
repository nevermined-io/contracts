pragma solidity ^0.8.0;

import './AbstractAuction.sol';
// Copyright 2021 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


contract EnglishAuction is AbstractAuction {

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
     * @param _floor floor price
     * @param _starts block number when the auction starts
     * @param _ends block number of when the auction ends
     * @param _tokenAddress token address to use for the auction. If address(0) means native token
     * @param _hash ipfs hash referring to the auction metadata 
     */
    function create(
        bytes32 _auctionId,
        bytes32 _did,
        uint256 _floor,
        uint256 _starts,
        uint256 _ends,
        address _tokenAddress,
        string memory _hash
    )
    external
    virtual
    {
        require(_starts > block.number, 'EnglishAuction: Can not start in the past');
        require(_ends > _starts, 'EnglishAuction: Must last at least one block');

        require(
            auctions[_auctionId].creator == address(0x0),
            'EnglishAuction: Already created'
        );

        auctions[_auctionId] = Auction({
            did: _did,
            state: DynamicPricingState.NotStarted,
            creator: msg.sender,
            blockNumberCreated: block.number,
            floor: _floor,
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
            _floor,
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
    onlyNotAborted(_auctionId)    
    onlyAfterStart(_auctionId)
    onlyBeforeEnd(_auctionId)
    {
        require(auctions[_auctionId].tokenAddress == address(0), 'EnglishAuction: Only native token accepted');

        uint256 userBid = msg.value + auctionBids[_auctionId][msg.sender];

        require(userBid >= auctions[_auctionId].floor, 'EnglishAuction: Only higher or equal than floor');
        require(userBid > auctions[_auctionId].price, 'EnglishAuction: Only higher bids');
        
        auctions[_auctionId].whoCanClaim = msg.sender;
        auctions[_auctionId].price = userBid;
        auctionBids[_auctionId][msg.sender] = userBid;
        if (auctions[_auctionId].state != DynamicPricingState.InProgress)
            auctions[_auctionId].state = DynamicPricingState.InProgress;
        
        emit AuctionBidReceived(
            _auctionId,
            msg.sender,
            address(0),
            userBid
        );

        // solhint-disable-next-line
        (bool sent, ) = payable(address(this)).call{value: msg.value}('');
        require(sent, 'EnglishAuction: Failed to send native token');

    }

    function placeERC20Bid(
        bytes32 _auctionId,
        uint256 _bidAmount
    )
    external
    virtual
    nonReentrant
    onlyNotCreator(_auctionId)
    onlyNotAborted(_auctionId)
    onlyAfterStart(_auctionId)
    onlyBeforeEnd(_auctionId)
    {
        require(auctions[_auctionId].tokenAddress != address(0), 'EnglishAuction: Only ERC20');
        
        uint256 userBid = _bidAmount + auctionBids[_auctionId][msg.sender];

        require(userBid >= auctions[_auctionId].floor, 'EnglishAuction: Only higher or equal than floor');
        require(userBid > auctions[_auctionId].price, 'EnglishAuction: Only higher bids');

        IERC20Upgradeable token = ERC20Upgradeable(auctions[_auctionId].tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _bidAmount);

        auctions[_auctionId].whoCanClaim = msg.sender;
        auctions[_auctionId].price = userBid;
        auctionBids[_auctionId][msg.sender] = userBid;
        if (auctions[_auctionId].state != DynamicPricingState.InProgress)
            auctions[_auctionId].state = DynamicPricingState.InProgress;
        
        emit AuctionBidReceived(
            _auctionId,
            msg.sender,
            auctions[_auctionId].tokenAddress,
            userBid
        );
    }

    function getPricingType()
    external
    pure
    override
    returns(bytes32)
    {
        return keccak256('EnglishAuction');
    }
    
  
    
}
