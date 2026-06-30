# Smart Contracts Security

## Roles and Responsibilities

<img src="images/Roles_1.png" alt="Roles and Responsibilities" width="800"/>
<img src="images/Roles_2.png" alt="Roles and Responsibilities" width="800"/>

## Solidity Compiler

The protocol uses the latest stable version of the Solidity compiler. The code is written in Solidity 0.8.x, which includes several improvements and security features over previous versions.

## Libraries

The protocol uses OpenZeppelin libraries for the implementation of the Smart Contracts. The main external functionalities integrated via OpenZeppeling libraries are:

- `AccessManager`: AccessManager is a central contract to store the permissions of a system. See <https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManager>
- `ReentrancyGuardTransientUpgradeable`: It is used to protect against reentrancy attacks. See <https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuardTransient>
- `ERC1155Upgradeable`: For the implementation of the ERC1155 standard. See <https://docs.openzeppelin.com/contracts/5.x/api/token/erc1155#ERC1155>
- `UUPSUpgradeable`: For the implementation of the UUPS upgradeable pattern. See <https://docs.openzeppelin.com/contracts/5.x/api/proxy#UUPSUpgradeable>

The contracts use **Foundry** for the implementation of the Smart Contracts.

## Event signature migrations

Events on `IAsset` are part of the protocol's public surface area — subgraphs and off-chain indexers subscribe to them by `topic0 = keccak256(<signature>)`. Adding or reordering fields changes `topic0` and silently breaks existing subscribers.

Current active migration:

- **`PlanRegistered`** — signature changed from `PlanRegistered(uint256,address)` to `PlanRegistered(uint256,address,bool)` in protocol#177 / #178 to surface the new `onchainMirror` flag alongside the plan id and creator. Neither storage layout nor plan ids change; only the event's `topic0` differs.

Downstream indexer owners must switch to the new `topic0` **before** the upgraded proxy implementation is promoted beyond staging, otherwise new plans are invisible to them. Submodule bumps in `nvm-monorepo` (and any other repo that tracks `packages/protocol`) should only happen after the indexer change is ready.

## Payment and escrow invariants

These invariants govern how value flows through `LockPaymentCondition`, `PaymentsVault`, and `DistributePaymentsCondition`. They constrain which tokens and pricing models the protocol accepts.

- **Exact-transfer ERC20s only.** `PaymentsVault.depositERC20` asserts the vault balance increased by exactly the requested amount (`ERC20DepositMismatch` otherwise), mirroring the existing EIP-3009 deposit check. Tokens that do not transfer the exact amount — fee-on-transfer tokens, and non-exact / rebasing (e.g. stETH/aToken-class) tokens whose balance drifts by a few wei — are therefore **not supported** as payment tokens. This is fail-closed: a non-conforming token reverts at deposit rather than silently under-funding the escrow.

- **External-price (`SMART_CONTRACT_PRICE`) settlement is bound to a write-once lock-time snapshot.** For plans priced by an external `INeverminedExternalPrice` contract, `LockPaymentCondition` calls `quote()` once and snapshots the per-purchase amounts into `AgreementsStore` (write-once, including an empty snapshot). `DistributePaymentsCondition` reuses that snapshot for both the success (distribute) and abort (refund) branches instead of re-quoting, so the amount distributed or refunded always equals the amount locked even if the external price source diverges after lock. Both branches **fail closed**: if the snapshot is missing or its length does not match the plan receivers, distribution reverts (`LockedAmountsReceiversLengthMismatch`) rather than withdrawing on a zero/misaligned array. No role-table change is involved — `setLockedAmounts` reuses the existing template/condition roles.

## Fiat settlement role

The `FiatSettlementCondition` records off-chain fiat payments (e.g. Stripe) on-chain. Its trust model has one invariant beyond the role gate:

- **The plan owner may not settle their own plan.** Settling requires `FIAT_SETTLEMENT_ROLE` **and** the settler must not be the plan owner — even an owner who holds the role is rejected (`SelfSettlementNotAllowed`). This guarantees recording a fiat payment as received always involves an independent settler, preventing a plan owner from self-attesting a payment to mint themselves credits. Operationally, if a `FIAT_SETTLEMENT_ROLE` holder is also a plan owner (e.g. a first-party plan), that plan must be settled by a distinct settler address. `FIAT_SETTLEMENT_ROLE` remains a single global role trusted to Nevermined infrastructure.

## Compilation

The code can be compiled using the following command:

```bash
pnpm build
```

## Testing

There are 2 types of tests:

1. **Unit Tests**: These tests are written in Solidity with Foundry and are located in the `test/foundry` folder. They cover the core functionalities of the contracts.
2. **Integration Tests**: These tests are written in TypeScript and are located in the `test/integration` folder. They cover the e2e integration of the flows provided by Nevermined protocol. Also show the integration of these flows from a client perspective.

The tests can be run using the following command:

```bash
# Unit tests
pnpm test

# Integration tests
pnpm test:integration
```

## Static Analysis

**TO BE ADDED**

## Target date of audit

Start at the beginning of June 2025

## Folders and contracts to audit

The main contracts to audit are located in the `contracts` folder. As a secondary objective we want to review the deployment scripts located in the `scripts` folder.
