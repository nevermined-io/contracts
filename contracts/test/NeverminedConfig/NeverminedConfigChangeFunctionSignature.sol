pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

import '../../governance/NeverminedConfig.sol';

contract NeverminedConfigChangeFunctionSignature is NeverminedConfig {
    
    // Allows to setup a marketplace fee >0 and feeReceiver = address(0)
    function setMarketplaceFees(
        uint256 _marketplaceFee,
        address _feeReceiver,
        uint256 _newParameter
    )
    external
    virtual
    onlyGovernor(msg.sender)
    {
        require(_newParameter > 0); // the change
        require(
            _marketplaceFee >=0 && _marketplaceFee <= 10000,
            'NeverminedConfig: Fee must be between 0 and 100 percent'
        );
        
        marketplaceFee = _marketplaceFee;
        feeReceiver = _feeReceiver;
    }
}
