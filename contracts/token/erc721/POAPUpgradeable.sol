pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './NFT721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';

contract POAPUpgradeable is NFT721Upgradeable, ERC721EnumerableUpgradeable {
    
    // Mapping of NFT Metadata object per tokenId (DID)
    mapping(uint256 => uint256) private _tokenEvent;    
    
    function mint(
        address to,
        uint256 tokenId,
        uint256 eventId
    )
    public
    virtual
    {
        super.mint(to, tokenId);
        _tokenEvent[tokenId] = eventId;
    }

    function mint(
        address to,
        uint256 eventId
    )
    public
    override
    virtual
    {
        uint256 tokenId = getHowManyMinted() + 1;
        mint(to, tokenId, eventId);
    }    

    function mint(
        address to
    )
    public
    virtual
    {
        mint(to, getHowManyMinted() + 1, 0);
    }    
    
    function mintBatch(
        address[] memory to,
        uint256[] memory tokenIds,
        uint256[] memory eventIds
    )
    public
    virtual
    {
        require(
            to.length == eventIds.length && to.length == tokenIds.length,
            'to and eventId arguments have wrong length'
        );
        for (uint256 i = 0; i < to.length; i++) {
            mint(to[i], tokenIds[i], eventIds[i]);
        }
    }

    function burnBatch(     
        uint256[] memory tokenIds
    )
    public
    virtual
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            burn(tokenIds[i]);
        }
    }

    function tokenEvent(
        uint256 tokenId
    )
    public
    view
    returns (uint256)
    {
        return _tokenEvent[tokenId];
    }

    function _burn(
        uint256 tokenId
    ) 
    internal 
    override(ERC721Upgradeable) {
        super._burn(tokenId);
    }    
    
    function tokenDetailsOfOwner(
        address owner
    )
    public
    view
    returns (uint256[] memory tokenIds, uint256[] memory eventIds)
    {
        uint256 ownedTokens = balanceOf(owner);
        uint256[] memory tokens = new uint256[](ownedTokens);
        uint256[] memory events = new uint256[](ownedTokens);

        for (uint256 i = 0; i < ownedTokens; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
            events[i] = tokenEvent(tokens[i]);
        }

        return (tokens, events);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    virtual
    override(NFT721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC721Upgradeable.supportsInterface(interfaceId)
        || ERC721EnumerableUpgradeable.supportsInterface(interfaceId)
        || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }

    function isApprovedForAll(
        address account,
        address operator
    )
    public
    view
    virtual
    override(NFT721Upgradeable, ERC721Upgradeable, IERC721Upgradeable)
    returns (bool)
    {
        return super.isApprovedForAll(account, operator);
    }

    function _baseURI()
    internal
    view
    override(NFT721Upgradeable, ERC721Upgradeable)
    returns (string memory)
    {
        return super._baseURI();
    }

    function tokenURI(
        uint256 tokenId
    )
    public
    view
    virtual
    override(NFT721Upgradeable, ERC721Upgradeable)
    returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 tokenId
    )
    internal
    override(NFT721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, firstTokenId, tokenId);
    } 
    
    function _msgSender() internal override(NFT721Upgradeable,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(NFT721Upgradeable,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }    
    
}
