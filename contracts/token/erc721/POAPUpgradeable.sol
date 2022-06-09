pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import './NFT721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol';


contract POAPUpgradeable is NFT721Upgradeable, ERC721URIStorageUpgradeable, ERC721EnumerableUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    CountersUpgradeable.Counter private _tokenIdCounter;

    // Mapping of NFT Metadata object per tokenId (DID)
    mapping(uint256 => uint256) private _tokenEvent;

    // solhint-disable-next-line
    function initialize() 
    public 
    override 
    initializer 
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained('', '');
        __ERC721URIStorage_init_unchained();
        __ERC721Enumerable_init_unchained();
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(MINTER_ROLE, msg.sender);
    }
    
    function mint(
        address to, 
        string memory uri, 
        uint256 eventId
    ) 
    public 
    {
        require(hasRole(MINTER_ROLE, msg.sender), 'only minter can mint');
        uint256 tokenId = _tokenIdCounter.current();

        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        _tokenEvent[tokenId] = eventId;
    }

    function mint(
        address to,
        uint256 id
    )
    public
    override
    {
        mint(to, '', id);
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) 
    internal 
    override(ERC721Upgradeable, ERC721EnumerableUpgradeable) 
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(
        uint256 tokenId
    ) 
    internal 
    override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
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

    function tokenURI(
        uint256 tokenId
    ) 
    public 
    view 
    override(NFT721Upgradeable, ERC721Upgradeable, ERC721URIStorageUpgradeable) 
    returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
    
    function isApprovedForAll(
        address account, 
        address operator
    ) 
    public 
    view 
    override(NFT721Upgradeable, ERC721Upgradeable) 
    returns (bool) 
    {
        return super.isApprovedForAll(account, operator);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    virtual
    override(NFT721Upgradeable, ERC721Upgradeable, ERC721EnumerableUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
}
