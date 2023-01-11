pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../NFTBase.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';


/**
 *
 * @dev Implementation of the basic standard multi-token.
 */
contract NFT721Upgradeable is ERC721Upgradeable, NFTBase {
    
    uint256 private _nftContractCap;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    using StringsUpgradeable for uint256;

    CountersUpgradeable.Counter private _counterMinted;

    // solhint-disable-next-line
    function initializeWithName(
        string memory name, 
        string memory symbol
    ) 
    public 
    virtual 
    initializer 
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, _msgSender());
    }
    
    // solhint-disable-next-line
    function initializeWithAttributes(
        address owner,
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap
    )
    public
    virtual
    initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained(name, symbol);
        __Ownable_init_unchained();
        
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, _msgSender());
        setContractMetadataUri(uri);
        _nftContractCap = cap;

        if (owner != _msgSender()) transferOwnership(owner);
    }    
    
    // solhint-disable-next-line
    function initialize()
    public
    virtual
    initializer
    {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC721_init_unchained('Nevermined ERC721', 'NVM721');
        __Ownable_init_unchained();
        AccessControlUpgradeable.__AccessControl_init();
        AccessControlUpgradeable._setupRole(NVM_OPERATOR_ROLE, _msgSender());
    }

    function createClone(
        string memory name,
        string memory symbol,
        string memory uri,
        uint256 cap
    )
    external
    virtual
    returns (address)
    {
        address implementation = StorageSlotUpgradeable.getAddressSlot(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc).value;
        if (implementation == address(0)) {
            implementation = address(this);
        }        
        address cloneAddress = ClonesUpgradeable.clone(implementation);
        NFT721Upgradeable(cloneAddress).initializeWithAttributes(_msgSender(), name, symbol, uri, cap);
        emit NFTCloned(cloneAddress, implementation, 721);
        return cloneAddress;
    }
    
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
        return super.isApprovedForAll(account, operator) || isOperator(operator);
    }
    
    function mint(
        address to,
        uint256 tokenId
    )
    public
    virtual
    {
        require(isOperator(_msgSender()), 'only nft operator can mint');
        require(_nftContractCap == 0 || _counterMinted.current() < _nftContractCap,
            'ERC721: Cap exceed'
        );
        _counterMinted.increment();
        _mint(to, tokenId);
    }

    function mint(
        uint256 tokenId
    )
    public
    virtual
    {
        return mint(_msgSender(), tokenId);
    }    
    
    function getHowManyMinted()
    public
    view
    returns (uint256)
    {
        return _counterMinted.current();
    }
    
    /**
    * @dev Burning tokens does not decrement the counter of tokens minted!
    *      This is by design.
    */
    function burn(
        uint256 tokenId
    ) 
    public 
    {
        require(
            isOperator(_msgSender()) || // Or the DIDRegistry is burning the NFT 
            balanceOf(_msgSender()) > 0, // Or the _msgSender() is owner and have balance
            'ERC721: caller is not owner or not have balance'
        );        
        _burn(tokenId);
    }

    function _baseURI() 
    internal 
    view 
    override
    virtual
    returns (string memory) 
    {
        return contractURI();
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
        require(isOperator(_msgSender()), 'only nft operator');
        _setNFTMetadata(tokenId, nftURI);
    }

    function tokenURI(
        uint256 tokenId
    ) 
    public 
    view 
    virtual 
    override (ERC721Upgradeable)
    returns (string memory) 
    {
        string memory baseURI = _baseURI();
        if (_exists(tokenId))
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toHexString())) : '';
        else
            return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI)) : '';        
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
        require(isOperator(_msgSender()), 'only nft operator');
        _setTokenRoyalty(tokenId, receiver, royaltyAmount);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) 
    public 
    view 
    virtual 
    override(ERC721Upgradeable, AccessControlUpgradeable, IERC165Upgradeable) 
    returns (bool) 
    {
        return AccessControlUpgradeable.supportsInterface(interfaceId)
        || ERC721Upgradeable.supportsInterface(interfaceId)
        || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }
    
    function _msgSender() internal override(NFTBase,ContextUpgradeable) virtual view returns (address ret) {
        return Common._msgSender();
    }
    function _msgData() internal override(NFTBase,ContextUpgradeable) virtual view returns (bytes calldata ret) {
        return Common._msgData();
    }
    
    /**
    * @dev It protects NFT transfers to force going through service agreements and enforce royalties
    */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256, /* firstTokenId */
        uint256 batchSize
    ) 
    internal 
    virtual 
    override 
    {
        require(
            from == address(0) || // We exclude mints
            to == address(0) || // We exclude burns
            isOperator(_msgSender()) // Only NFT Contract Operators (Nevermined condition contracts)
        , 'only proxy'
        );
        super._beforeTokenTransfer(from, to, 0, batchSize);
    }
    
}
