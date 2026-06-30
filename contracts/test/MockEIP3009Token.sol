// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {ECDSA} from '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';

/**
 * @title MockEIP3009Token
 * @notice Test double that faithfully implements the EIP-3009 `receiveWithAuthorization` flow
 *         the same way Circle's USDC (FiatTokenV2) does.
 * @dev Used to exercise the gasless payment path in tests with REAL signature verification:
 *      EIP-712 domain separation, ecrecover-based signer recovery, single-use nonces, a
 *      validity time window, and the `to == msg.sender` guard that makes `receiveWithAuthorization`
 *      front-running safe. This is test infrastructure only — never deployed to production.
 */
contract MockEIP3009Token is ERC20, EIP712 {
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        'ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)'
    );

    /// @notice authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    error AuthorizationUsedOrCanceled(address authorizer, bytes32 nonce);
    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error CallerMustBePayee();
    error InvalidSignature();

    constructor(string memory name, string memory symbol) ERC20(name, symbol) EIP712(name, '1') {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Exposes the EIP-712 domain separator so tests/integrators can build digests.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Returns whether an authorization nonce has been used (or canceled) for an authorizer.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @notice EIP-3009 transfer authorized by signature, where only `to` (the payee) may submit it.
     * @dev The `to == msg.sender` guard prevents front-running and is what makes this variant safe
     *      for a contract recipient (e.g. the Nevermined PaymentsVault) to pull funds atomically.
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(to == msg.sender, CallerMustBePayee());
        _verifyAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
        _transfer(from, to, value);
    }

    /// @dev Shared checks: time window, nonce freshness, signer recovery. Marks the nonce used.
    function _verifyAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        require(block.timestamp > validAfter, AuthorizationNotYetValid());
        require(block.timestamp < validBefore, AuthorizationExpired());
        require(!_authorizationStates[from][nonce], AuthorizationUsedOrCanceled(from, nonce));

        bytes32 structHash =
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        require(signer == from, InvalidSignature());

        _authorizationStates[from][nonce] = true;
        emit AuthorizationUsed(from, nonce);
    }
}
