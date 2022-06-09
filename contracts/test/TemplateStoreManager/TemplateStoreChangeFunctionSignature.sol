pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../templates/TemplateStoreManager.sol';

contract TemplateStoreChangeFunctionSignature is TemplateStoreManager {
    using TemplateStoreLibrary for TemplateStoreLibrary.TemplateList;

    function proposeTemplate(address _id, address _sender)
        external
        returns (uint size)
    {
        require(
            _id == _sender,
            'Invalid sender address'
        );
        return templateList.propose(_id);
    }
}
