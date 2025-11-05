# Nevermined Protocol Technical Documentation

## Project Description

### Introduction

Nevermined Smart Contracts form the core of the Nevermined protocol, enabling secure asset registration, access control, and payment management in a decentralized environment. The main asset supported by the protocol is the AI Agent, making the protocol oriented towards the monetization and access control of AI Agents.

This protocol facilitates the entire lifecycle of AI Agents, from registration and pricing to access management and payment processing. The protocol manages payment and access distribution via credits (ERC1155 NFTs). On top of this credit accounting, the protocol allows the authorization of access to AI Agent subscribers.

The protocol is designed to support different payment flows implemented via Template Smart Contracts. The templates execute a series of conditions sequentially, with each condition depending on the successful execution of the previous one. The templates are designed to be flexible and extensible, allowing for the addition of new payment flows in the future.

The protocol records three types of on-chain settlements. The payment and distribution of credits settlement happen during the purchase of a Payment Plan. The redemption of credits happens when the subscriber accesses the AI Agents associated with the plan:

1. Payment settlement: The payment is locked in a vault by the subscriber and, at the end of the flow, the funds are distributed to the payment plan receivers.
2. Distribution of credits: During the purchase of the plan, the credits are distributed to the subscriber.
3. Redemption of credits: The subscriber can redeem the credits to access the AI Agents associated with the plan.

### Target Users

The main users and stakeholders of the protocol are:

- **AI Builders**: They create **AI Agents** and register them in the protocol. They can set up pricing models, manage access rights, and receive payments.
- **AI Subscribers**: Users who want to access AI Agents. They can purchase credits (ERC1155 NFTs) to pay for access and interact with the AI Agents.

Because the protocol is designed to facilitate functions that can be executed programmatically, the target users (AI Builders creating and registering AI Agents and the AI Subscribers) can be represented by humans or by computers (AIs). With emerging AI technologies, we are seeing a shift towards more automated interactions, where AI agents can autonomously register, manage, and interact with other AI agents. This opens up new possibilities for decentralized applications and services that leverage the capabilities of AI.

In the first phase, the most natural way of interacting with the protocol will be from humans to agents (human-to-agent). In a second phase, we expect to see more automated interactions, where AI agents can autonomously register, manage, and interact with other AI agents (agent-to-agent).

### Features

The Nevermined protocol allows users to:

### Register AI Agents

AI Agents can be registered in the protocol with a unique identifier and a reference to some off-chain metadata (HTTP URL, IPFS CID, etc). This unique identifier (also known as DID or Decentralized Identifier) is used to identify the AI Agent in the protocol. Having the agent DID, which is stored on-chain, a target user can resolve the off-chain metadata describing the Agent.

When agents are registered, they are associated with the original creator (AI Builder), and the protocol allows management of the attributes of this agent. The protocol also allows setting up a pricing model for the agent via Pricing Plans.

For further information see `contracts/interfaces/IAsset.sol` - `struct DIDAgent`.

### Register Pricing Plans and associate them with AI Agents

Pricing Plans (also known as Plans) are used to define the access rights and payment conditions for AI Agents.

Pricing Plans are separate entities from the AI Agents. This allows the creation of different pricing plans for the same agent, or different agents with the same pricing plan. This enables great flexibility, where AI Builders can design different pricing models for their agents and subscribers can choose the most suitable plan for them.

The Pricing Plans have the following main attributes:

- **Plan ID**: A unique identifier for the plan.
- **Price Config**: The price configuration for the plan:
  - **Price Type**: The type of price (e.g., fixed price in crypto, fixed price in fiat, dynamic via a Smart Contract).
  - **Currency**: The currency of the plan (e.g., ETH, DAI, etc.).
  - **Distribution of Payments**: The distribution of payments to multiple receivers (e.g., 99 USDC to the AI Builder, 1% to the Protocol as a fee).
- **Credits Config**: The credits configuration for the plan:
  - **Credits Type**: Expirable (if credits are time-limited), Fixed Amount (if credits are not time-limited and the amount to redeem for usage is fixed), or dynamic (if the redemption of credits for access is flexible).
  - **Redemption Type**: Who can redeem the credits (only accounts having a specific Smart Contract Role, only the owner of the plan, or only an account with specific permissions granted by the plan owner).
  - **Credits Amount**: The amount of credits required for the plan.
  - **Credits Expiration**: The expiration date of the credits (e.g., 1 month, 1 year).
  - **Redemption Proof is required**: If true, for redeeming the credits the subscriber must provide a signature allowing a third party to redeem the credits on behalf of the subscriber.
  - **Duration in Seconds**: After the purchase of the plan and the credits associated, this states in how many seconds the credits will expire. This is only applicable for expirable Pricing Plans.

### Manage access to AI Agents via Pricing Plans

When AI Agents are registered and have one (or many) associated Pricing Plans, the protocol allows subscribers to purchase these plans. When a subscriber purchases a plan, the protocol associates the number of credits to the subscriber, with the characteristics defined in the plan purchased (duration, number of credits, etc).

Subscribers owning credits for a plan can use (and redeem) them to access the AI Agents associated with the plan. Every time an AI Agent is accessed (depending on the redemption criteria and integration with the AI Agent), the protocol checks if the subscriber has enough credits to access the agent. If the subscriber has enough credits, the protocol allows access to the agent and deducts the number of credits used from the subscriber's balance.

### Orchestrate payment via crypto and fiat

The Pricing Plans have a price type (fixed price in crypto, fixed price in fiat, dynamic via a Smart Contract). The protocol provides the execution of these payment flows via Smart Contract Templates that integrate conditions executed sequentially. Each condition depends on previous conditions being successfully executed first. The templates are designed to be flexible and extensible, allowing for the addition of new payment flows in the future:

- **FixedPaymentTemplate**: (See `contracts/agreements/FixedPaymentTemplate.sol`) This template allows processing fixed payments for payment plans in cryptocurrency. The template (via the integration of pluggable Smart Contract conditions) orchestrates the payment and distribution of credits and payments as a single transaction. The template flow is as follows:
  1. The subscriber locks the payment of the plan in cryptocurrency (ERC20 or Native token).
  2. The protocol checks if the payment is valid (e.g., the amount is correct, fees are included, the plan exists, etc.).
  3. The protocol locks the payment in a vault (PaymentsVault).
  4. The protocol distributes the credits to the subscriber with the characteristics defined in the payment plan (duration, number of credits, etc).
  5. The protocol unlocks the payment from the vault and distributes the payment to the receivers (e.g., 99 USDC to the AI Builder, 1% to the Protocol as a fee).

- **FiatPaymentTemplate**: (See `contracts/agreements/FiatPaymentTemplate.sol`). This template allows processing payments in fiat. The fiat payments happen off-chain via the integration of a payments provider (i.e., Stripe). The template allows a **trusted fiat settlement role** to fulfill the template when the fiat payment is done. The template flow is as follows:

1. An account with the `FIAT_SETTLEMENT_ROLE` role creates the agreement when there is a valid payment in fiat. (In evaluation to get some kind of proof of payment from the payment providers).
2. The protocol distributes the credits to the subscriber with the characteristics defined in the payment plan (duration, number of credits, etc).

### Management and distribution of payments to multiple receivers

In Nevermined when a payment plan (crypto flows) is defined, it includes 3 main attributes related to the payment:

- **token address**: The address of the token to be used for the payment (e.g., USDC, DAI, etc.). If the address is the zero address (0x0), the payment is done in the native token of the network (i.e., ETH).
- **amounts**: An array with the different amounts to be distributed.
- **receivers**: An array with the different addresses to be used for the distribution.

For the templates using crypto for payments (Currently only the FixedPaymentTemplate), the protocol allows locking and distributing payments to multiple receivers. This is done via:

- `LockPaymentCondition` condition (see `contracts/conditions/LockPaymentCondition.sol`) which allows making payments (ERC20 or Native token) for payment plans.
- The `DistributePaymentsCondition` condition (see `contracts/conditions/DistributePaymentsCondition.sol`) that allows the distribution of payments to multiple receivers. This condition only can be executed when the payment is locked successfully and credits are distributed.

### Manage the access rights via credits (ERC1155 NFTs)

Subscribers purchasing Payment Plans receive credits (ERC1155 NFTs) representing their ownership of a participation in a specific plan. In this case, the plan unique identifier (`planId`) works as the `tokenId` representing the plan in the NFT (ERC-1155) Smart Contract that accounts for the balance of the users on each plan.

There are 2 different NFT contracts used in the protocol (this could be extended in the future):

- `NFT1155Credits` (see `contracts/token/NFT1155Credits.sol`): This contract is used to account for the balance of non-expirable credits.
- `NFT1155ExpirableCredits` (see `contracts/token/NFT1155ExpirableCredits.sol`): This contract is used to account for the balance of expirable credits.

Querying the balance of a user on a specific plan is done via the `balanceOf` function of the ERC1155 contracts. The `tokenId` used in this case is the `planId` of the plan.

Checking the balance, the AI Agents can validate if subscribers (human or agents) have enough credits to access the AI Agents associated with the plan.

Depending on the plan configuration the credits can be redeemed in different ways. When the plan requires the delivery of a proof for redemption, the credits only can be redeemed when a client provides a valid signature allowing a third party to redeem the credits on behalf of the subscriber.

### Roles and Permissions

The protocol is intended to be fully decentralized, with as low as possible centralization points. Because the protocol governs off-chain interactions (AI Agents are typically off-chain software), each different flow supported by the protocol is designed to minimize centralized dependencies.

Access control to core functions is restricted to Templates and Condition Smart Contracts of the protocol. The full list of roles and permissions is defined in the `contracts/common/Roles.sol` contract.
