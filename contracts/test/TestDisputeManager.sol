pragma solidity 0.6.12;
// Copyright 2020 Keyko GmbH.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

contract TestDisputeManager {

    mapping (bytes32 => bool) public accept;

    function accepted(address provider, address buyer, bytes32 orig, bytes32 crypted) public view returns (bool) {
        return accept[keccak256(abi.encode(provider, buyer, orig, crypted))];
    }

    function setAccepted(bytes32 orig, bytes32 crypted, address provider, address buyer) public {
        accept[keccak256(abi.encode(provider, buyer, orig, crypted))] = true;
    }


}