pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import './NFT1155Upgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT1155SubscriptionUpgradeable is NFT1155Upgradeable {

    struct MintedTokens {
        uint256 amountMinted;
        uint256 expirationBlock;
        uint256 mintBlock;
    }

    mapping(bytes32 => MintedTokens[]) internal _tokens;
    // Mapping of expiration block number per user (subscription NFT holder)
    //mapping(bytes32 => uint256) internal _expirationBlock;

    // Mapping of expiration block number per user (subscription NFT holder)
    //mapping(bytes32 => uint256) internal _mintBlock;
    
    /**
     * @dev This mint function allows to define when the tokenId of the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     */
    function mint(address to, uint256 tokenId, uint256 amount, uint256 expirationBlock, bytes memory data) public {
        super.mint(to, tokenId, amount, data);
        bytes32 _key = keccak256(abi.encode(to, tokenId));

        _tokens[_key].push( MintedTokens(amount, expirationBlock, block.number));
        //_mintBlock[_key] = block.number;
    }
    
    /**
     * @dev See {NFT1155Upgradeableable-balanceOf}.
     */
    function balanceOf(address account, uint256 tokenId) public view virtual override returns (uint256) {
        bytes32 _key = keccak256(abi.encode(account, tokenId));
        uint256 _balance;
        for (uint index = 0; index < _tokens[_key].length; index++) {
            if (_tokens[_key][index].expirationBlock == 0 || _tokens[_key][index].expirationBlock > block.number)
                _balance += _tokens[_key][index].amountMinted;
        }
        
        return _balance;
    }
    
    function whenWasMinted(address owner, uint256 tokenId) public view returns (uint256[] memory) {
        bytes32 _key = keccak256(abi.encode(owner, tokenId));
        uint256[] memory _whenMinted = new uint256[](_tokens[_key].length);
        for (uint index = 0; index < _tokens[_key].length; index++) {
            _whenMinted[index] = _tokens[_key][index].mintBlock;
        }
        return _whenMinted;
    }    
}
