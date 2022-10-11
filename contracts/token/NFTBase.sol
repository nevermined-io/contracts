pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../Common.sol';
import '@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol';

/**
 *
 * @dev Implementation of the Royalties EIP-2981 base contract
 * See https://eips.ethereum.org/EIPS/eip-2981
 */
abstract contract NFTBase is IERC2981Upgradeable, OwnableUpgradeable, AccessControlUpgradeable, Common {

    // Mapping from account to proxy approvals
    mapping (address => bool) internal _proxyApprovals;

    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');    
    
    struct RoyaltyInfo {
        address receiver;
        uint256 royaltyAmount;
    }
    
    struct NFTMetadata {
        string nftURI;
    }
    
    // Mapping of Royalties per tokenId (DID)
    mapping(uint256 => RoyaltyInfo) internal _royalties;
    // Mapping of NFT Metadata object per tokenId (DID)
    mapping(uint256 => NFTMetadata) internal _metadata;
    // Mapping of expiration block number per user (subscription NFT holder)
    mapping(address => uint256) internal _expiration;

    // Used as a URL where is stored the Metadata describing the NFT contract
    string private _contractMetadataUri;

    address public nvmConfig;

    /**
     * @dev getNvmConfigAddress get the address of the NeverminedConfig contract
     * @return NeverminedConfig contract address
     */
    function getNvmConfigAddress()
    public
    override
    view
    returns (address)
    {
        return nvmConfig;
    }

    function setNvmConfigAddress(address _addr)
    external
    onlyOwner
    {
        nvmConfig = _addr;
    }

    /** 
     * Event for recording proxy approvals.
     */
    event ProxyApproval(address sender, address operator, bool approved);
    
    function setProxyApproval(
        address operator, 
        bool approved
    ) 
    public 
    onlyOwner 
    virtual 
    {
        _proxyApprovals[operator] = approved;
        emit ProxyApproval(_msgSender(), operator, approved);
    }

    function _setNFTMetadata(
        uint256 tokenId,
        string memory tokenURI
    )
    internal
    {
        _metadata[tokenId] = NFTMetadata(tokenURI);
    }

    function _setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint256 royaltyAmount
    )
    internal
    {
        require(royaltyAmount <= 1000000, 'ERC2981Royalties: Too high');
        _royalties[tokenId] = RoyaltyInfo(receiver, royaltyAmount);
    }    
    
    /**
     * @inheritdoc	IERC2981Upgradeable
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 value
    )
    external
    view
    override
    returns (address receiver, uint256 royaltyAmount)
    {
        RoyaltyInfo memory royalties = _royalties[tokenId];
        receiver = royalties.receiver;
        royaltyAmount = (value * royalties.royaltyAmount) / 100;
    }

    /**
    * @dev Record the URI storing the Metadata describing the NFT Contract
    *      More information about the file format here: 
    *      https://docs.opensea.io/docs/contract-level-metadata
    * @param _uri the URI (https, ipfs, etc) to the metadata describing the NFT Contract    
    */    
    function setContractMetadataUri(
        string memory _uri
    )
    public
    onlyOwner
    virtual
    {
        _contractMetadataUri = _uri;
    }
    
    function contractURI()
    public
    view
    returns (string memory) {
        return _contractMetadataUri;
    }
}
