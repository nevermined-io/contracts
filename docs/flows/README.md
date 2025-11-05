# Nevermined Payment Flows

This directory contains documentation about the different payment flows supported by Nevermined.

The payment flows supported are:

* [Crypto Payment Flow](Crypto-Payment-Plan.md)
* [Fiat Payment Flow](Fiat-Payment-Plan.md)
* [Pay-as-you-go Payment Flow (Crypto)](Pay-as-you-go.md)
* [Subscription Payment Flow (Fiat)](Subscription-Payment-Plan.md)

After a user gets credits by purchasing a payment plan, they can use those credits to send requests to AI Agents. When a subscriber sends a request to an AI Agent, each request deducts the corresponding amount of credits from the user's balance.

The query and redemption of credits is described in the [AI Agent Requests and Redemption Flow](Requests-and-Redemption.md) document.

## Note about the flows and Smart Accounts

All the flows included in this folder include the NVM API as an actor as part of the architecture. This is because the NVM App uses Smart Accounts, which allow AI Agents and subscribers to interact with the NVM Protocol without needing to own a wallet or having to manage private keys.

The Nevermined Protocol is agnostic to the use of Smart Accounts, and the flows are designed to work seamlessly with or without them.
