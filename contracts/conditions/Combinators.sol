pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.

// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

interface Condition {
    // check that the condition is created validly
    function create(bytes memory params) external returns (bool);
    function isFulfilled(bytes memory params) external returns (bool); // probably instead if fulfilled there should be status (can be aborted)
    function getId(bytes memory params) external returns (bytes32);
    function fulfill(bytes32 id, bytes memory params) external;
}

abstract contract CombinedCondition is Condition {
    function getId(bytes memory params) external returns (bytes32) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return keccak256(abi.encode(cond1, Condition(cond1).getId(params1), cond2, Condition(cond2).getId(params2)));
    }
    function fulfill(bytes32 id, bytes memory params) virtual external {
        bool choice;
        bytes memory paramsChoice;
        bytes32 id1;
        bytes32 id2;
        address cond1;
        address cond2;
        (cond1, id1, cond2, id2, choice, paramsChoice) = abi.decode(params, (address, bytes32, address, bytes32, bool, bytes));
        require(keccak256(abi.encode(cond1, id1, cond2, id2)) == id, '');
        if (!choice) {
            Condition(cond1).fulfill(id1, paramsChoice);
        } else {
            Condition(cond2).fulfill(id2, paramsChoice);
        }
    }
    function create(bytes memory params) external returns (bool) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return Condition(cond1).create(params1) && Condition(cond2).create(params2);
    }
}

contract OrCondition is CombinedCondition {
    function isFulfilled(bytes memory params) external returns (bool) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return Condition(cond1).isFulfilled(params1) || Condition(cond2).isFulfilled(params2);
    }
}

contract AndCondition is CombinedCondition {
    function isFulfilled(bytes memory params) external returns (bool) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return Condition(cond1).isFulfilled(params1) && Condition(cond2).isFulfilled(params2);
    }
}

contract CondCondition is CombinedCondition {
    function isFulfilled(bytes memory params) external returns (bool) {
        bytes memory params1;
        bytes memory params2;
        address cond1;
        address cond2;
        (cond1, params1, cond2, params2) = abi.decode(params, (address, bytes, address, bytes));
        return Condition(cond1).isFulfilled(params1) && Condition(cond2).isFulfilled(params2);
    }
    function fulfill(bytes32 id, bytes memory params) override external {
        bool choice;
        bytes memory paramsChoice;
        bytes32 id1;
        bytes32 id2;
        address cond1;
        address cond2;
        (cond1, id1, cond2, id2, choice, paramsChoice) = abi.decode(params, (address, bytes32, address, bytes32, bool, bytes));
        require(keccak256(abi.encode(cond1, id1, cond2, id2)) == id, 'params do not match id');
        if (!choice) {
            Condition(cond1).fulfill(id1, paramsChoice);
        } else {
            bytes memory params1;
            bytes memory params2;
            (params1, params2) = abi.decode(paramsChoice, (bytes,bytes));
            require(Condition(cond1).isFulfilled(params1), 'condition must be fulfilled first');
            Condition(cond2).fulfill(id2, params2);
        }
    }
}

contract TimeoutCondition is Condition {
    function isFulfilled(bytes memory params) external returns (bool) {
        bytes memory params1;
        address cond1;
        uint256 created;
        uint256 timeout;
        (cond1, params1, created, timeout) = abi.decode(params, (address, bytes, uint256, uint256));
        return Condition(cond1).isFulfilled(params1) || block.timestamp > timeout + created;
    }
    function create(bytes memory params) external returns (bool) {
        bytes memory params1;
        address cond1;
        uint256 created;
        uint256 timeout;
        (cond1, params1, created, timeout) = abi.decode(params, (address, bytes, uint256, uint256));
        return Condition(cond1).create(params1) && block.timestamp > created;
    }
    function fulfill(bytes32 id, bytes memory params) override external {
        bytes32 id1;
        address cond1;
        bytes memory params1;
        uint256 created;
        uint256 timeout;
        (cond1, id1, params1, created, timeout) = abi.decode(params, (address, bytes32, bytes, uint, uint));
        require(keccak256(abi.encode(cond1, id1, created, timeout)) == id, 'params do not match id');
        require(block.timestamp > timeout + created, 'timed out, cannot fulfill');
        Condition(cond1).fulfill(id1, params1);
    }
    function getId(bytes memory params) external returns (bytes32) {
        bytes memory params1;
        address cond1;
        uint256 created;
        uint256 timeout;
        (cond1, params1, created, timeout) = abi.decode(params, (address, bytes, uint256, uint256));
        return keccak256(abi.encode(cond1, Condition(cond1).getId(params1), created, timeout));
    }
}
