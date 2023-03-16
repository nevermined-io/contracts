pragma solidity ^0.8.0;

import './NFT721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract NFT721SubscriptionUpgradeable is NFT721Upgradeable {

    struct MintedTokens {
        uint256 tokenId;
        uint256 expirationBlock;
        uint256 mintBlock;
    }

    mapping(address => MintedTokens[]) internal _tokens;    
    
    /**
     * @dev This mint function allows to define when the NFT expires. 
     * The minter should calculate this block number depending on the network velocity
     * 
     * @dev TransferNFT721Condition needs to have the `NVM_OPERATOR_ROLE`
     */
    function mint(address to, uint256 tokenId, uint256 expirationBlock) public {
        super.mint(to, tokenId);
  
        _tokens[to].push( MintedTokens(tokenId, expirationBlock, block.number));
    }
    
    /**
     * @dev See {IERC721-balanceOf}.
     */    
    function balanceOf(address owner) public view override returns (uint256) {
        uint256 _balance;
        for (uint index = 0; index < _tokens[owner].length; index++) {
            if (_tokens[owner][index].expirationBlock == 0 || _tokens[owner][index].expirationBlock > block.number)
                _balance += 1;
        }

        return _balance;
    }

    function whenWasMinted(address owner) public view returns (uint256[] memory) {
        uint256[] memory _whenMinted = new uint256[](_tokens[owner].length);
        for (uint index = 0; index < _tokens[owner].length; index++) {
            _whenMinted[index] = _tokens[owner][index].mintBlock;
        }
        return _whenMinted;
    }
}
