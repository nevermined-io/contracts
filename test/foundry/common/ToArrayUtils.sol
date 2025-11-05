// Copyright 2025 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0
pragma solidity ^0.8.30;

abstract contract ToArrayUtils {
    function toArray(bytes4 a) internal pure returns (bytes4[] memory array) {
        array = new bytes4[](1);
        array[0] = a;
    }

    function toArray(bytes4 a, bytes4 b) internal pure returns (bytes4[] memory array) {
        array = new bytes4[](2);
        array[0] = a;
        array[1] = b;
    }
}
