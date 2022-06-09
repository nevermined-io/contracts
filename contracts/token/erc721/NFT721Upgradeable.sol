pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '../NFTBase.sol';


/**
 *
 * @dev Implementation of the basic standard multi-token.
 */
contract NFT721Upgradeable is ERC721Upgradeable, NFTBase {

    // solhint-disable-next-line
    function initialize() 
    public 
    virtual 
    initializer 
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained('', '');
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(MINTER_ROLE, msg.sender);
    }
    
    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(
        address account, 
        address operator
    ) 
    public 
    view 
    virtual 
    override 
    returns (bool) 
    {
        return super.isApprovedForAll(account, operator) || _proxyApprovals[operator];
    }
    
    function addMinter(
        address account
    ) 
    public 
    onlyOwner 
    {
        AccessControlUpgradeable._setupRole(MINTER_ROLE, account);
    }    
    
    function mint(
        address to, 
        uint256 id
    ) 
    public 
    virtual 
    {
        require(hasRole(MINTER_ROLE, msg.sender), 'only minter can mint');
        _mint(to, id);
    }

    function burn(
        uint256 id
    ) 
    public 
    {
        require(
            hasRole(MINTER_ROLE, msg.sender) || // Or the DIDRegistry is burning the NFT 
            balanceOf(msg.sender) > 0, // Or the msg.sender is owner and have balance
            'ERC721: caller is not owner or not have balance'
        );        
        _burn(id);
    }
    
    function tokenURI(
        uint256 tokenId
    ) 
    public 
    virtual 
    view 
    override 
    returns (string memory) 
    {
        return _metadata[tokenId].nftURI;
    }

    /**
    * @dev Record some NFT Metadata
    * @param tokenId the id of the asset with the royalties associated
    * @param nftURI the URI (https, ipfs, etc) to the metadata describing the NFT
    */
    function setNFTMetadata(
        uint256 tokenId,
        string memory nftURI
    )
    public
    {
        require(hasRole(MINTER_ROLE, msg.sender), 'only minter');
        _setNFTMetadata(tokenId, nftURI);
    }

    /**
    * @dev Record the asset royalties
    * @param tokenId the id of the asset with the royalties associated
    * @param receiver the receiver of the royalties (the original creator)
    * @param royaltyAmount percentage (no decimals, between 0 and 100)    
    */
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint256 royaltyAmount
    )
    public
    {
        require(hasRole(MINTER_ROLE, msg.sender), 'only minter');
        _setTokenRoyalty(tokenId, receiver, royaltyAmount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) 
    public 
    view 
    virtual 
    override(ERC721Upgradeable, IERC165Upgradeable) 
    returns (bool) 
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC721Upgradeable.supportsInterface(interfaceId)
        || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }

}
