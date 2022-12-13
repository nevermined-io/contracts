pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

interface Condition {
    // check that the condition is created validly
    function create(bytes memory params) external returns (bool);
    function isFulfilled(bytes memory params) external returns (bool);
    function getId(bytes memory params) external returns (bytes32);
    function fulfill(bytes32 id, bytes memory params) external;
}

contract OrCondition {
    function isFulfilled(bytes memory params) external returns (bool) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return Condition(cond1).isFulfilled(params1) || Condition(cond2).isFulfilled(params2);
    }
    function getId(bytes memory params) external returns (bytes32) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return keccak256(abi.encode(cond1, Condition(cond1).getId(params1), cond2, Condition(cond2).getId(params2)));
    }
    function fulfillA(bytes32 id, bytes memory params) external {
        bytes memory params1;
        bytes32 params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return keccak256(abi.encode(cond1, Condition(cond1).getId(params1), cond2, Condition(cond2).getId(params2)));

    }
}
