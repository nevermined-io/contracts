pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';

contract TestERC721 is ERC721Upgradeable {

    function initialize() public initializer {
        __ERC721_init_unchained('Test', 'TEST');
    }

    function mint(uint256 id) public {
        _mint(msg.sender, id);
    }

}
