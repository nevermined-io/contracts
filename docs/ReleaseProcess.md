---
sidebar_position: 4
---

# Release Process

## Build a new version

Nevermined contracts follow the semantic versioning pattern. To release a new version it's necessary:

- Make sure the versions is correctly updated in the: `package.json`
- Create a tag:

  ```bash
  git tag v2.0.0
  ```

- Push the tag:

  ```bash
  git push origin v2.0.0
  ```

## Interact with networks

### Roles

> :warning: wallets.json file is needed if using a MultiSig Wallet for the deployment. Currently none of the Nevermined contract deployments is using Multisig wallets.

We define six roles (check code configuration in [wallets.js](../scripts/deploy/wallets.js)):

- `deployer`: represented as `accounts[8]`
- `upgrader`: represented as `accounts[8]`
- `governor`: represented as `accounts[9]`
- `ownerWallet`: represented as the `owner` from `wallets.json` or `accounts[8]`
- `upgraderWallet`: represented as the `upgrader` from `wallets.json` or `accounts[8]`
- `governorWallet`: represented as the `governor` from `wallets.json` or `accounts[9]`

### Flags

- `--testnet` Deploys the `Dispenser`, the `NeverminedToken` and the contracts from `contracts.json`
- `--with-token` Deploys the `NeverminedToken` and the contracts from `contracts.json`

### Nevermined Configuration

The set of Nevermined contracts can be deployed in different networks and interact with several use cases.
Each of these different scenarios could require different configurations so to facilitate that Nevermined provides an
on-chain configuration mechanism allowing the governance (via DAO or similar) of a Nevermined deployment.
To see all the available possibilities please see the `INeverminedConfig` interface.

During the deployment of Nevermined all of these parameters can be specified allowing a bespoke environment configuration.
This can be done via the definition of the following environment variables:

- `NVM_MARKETPLACE_FEE`. It refers to the fee charged by Nevermined for using the Service Agreements. It uses an integer number representing a 4 decimal number. It means 145000 means 14.50% fee. The value must be beteen 0 and 10000 (100%). See `marketplaceFee` variable.
- `NVM_RECEIVER_FEE`. It refers to the address that will receive the fee charged by Nevermined per transaction. See `feeReceiver` variable

#### Deployer

Can be any account. It is used for deploying the initial proxy contracts and the logic contracts.

#### Upgrader

Has to be an `owner` of the `upgrader` multi sig wallet. It is used for issuing upgrade requests against the `upgrader` multi sig wallet.

#### UpgraderWallet

One instance of the multi sig wallet, defined as `upgrader`. This wallet will be assigned as zos admin and is required to do upgrades.

#### OwnerWallet

One instance of the multi sig wallet, defined as `owner`. This wallet will be assigned as the `owner` of all the contracts. It can be used to call specific functions in the contracts ie. change the configuration.

### Deploy & Upgrade

Deployment configurations are on `hardhat.config.js`.

- run `yarn clean` to clean the work dir.
- run `yarn compile` to compile the contracts.

> :warning: The following steps shows how to perform contracts deployment for new deployments (check `[Upgrades.md](./Upgrades.md)` for upgrading details)

- Export the `NETWORK` (check in the `hardhat.config.js` for the supported networks) and contract's tag `TAG`:

```bash
export NETWORK=mumbai
export TAG=common
```

- it will be useful to set `export DEPLOY_ERROR_EXIT=true`, then the deploy sript will exit if any error occurs in contract calls. Then the deploy can be retried easily.
- for a clean deployment remove all the artifacts existing with the network you are deploying: `rm -f artifacts/*.$NETWORK.json`
- run `export MNEMONIC=<deployment's mnemonic>`. You will find them in the password manager.

Here a full example:

```bash
MNEMONIC="my 24 words mnemonic"
DEPLOYER=0xe08A1dAe983BC701D05E492DB80e0144f8f4b909
UPGRADER=0xe08A1dAe983BC701D05E492DB80e0144f8f4b909
GOVERNOR=0xbcE5A3468386C64507D30136685A99cFD5603135

NVM_MARKETPLACE_FEE=010000

NVM_RECEIVER_FEE=0x309039F6A4e876bE0a3FCA8c1e32292358D7f07c
OPENGSN_FORWARDER=0x4d4581c01A457925410cd3877d17b2fd4553b2C5

NETWORK=mumbai
TAG=public
```

To make meta-transactions work, `OPENGSN_FORWARDER` should be set to the correct
forwarder address for the network. The OpenGSN v2 contract addresses should be used.

#### Deploy and initialize the contracts

- To deploy and initialize all contracts run `yarn deploy:$NETWORK`

This step will create `cache/` and `deploy-cache.json` used to resume the deployment in case something fails.

#### Script for uploading the artifacts (abis/contracts) to Contract Repository

Once the contracts are deployed to a public network or a new contract version whose contract abis has to been uploaded, use `scripts/upload_artifacts_gs.sh` to upload
the contracts or artifacts to [nevermined repository](https://artifacts.nevermined.network/).

> :warning: Your environment has to be configured and authorized to use aws cli to upload files to `artifacts-nevermined-network` bucket.

For all this commands you need to **have access to artifacts-nevermined-rocks Google Cloud bucket**.

The script has the next variables:

- `branch` is the branch from where the workflow and artifacts will be used.
- `asset` can be `abis`/`contracts`. Use abis if you want to upload the contract ABIs that not contain deployment information. Contracts for uploading abis with deployment information to `network`.
- `network` refers to network name, based on filename/hardhat config. Not used if `abis` is selected.
- `tag` refers to deployment tag. Defaults to common. Not used if `abis` is selected.

This workflow uses the script `scripts/upload_artifacts_g3.sh` that can be used with the next syntax:

```bash
./scripts/upload_artifacts_gs.sh contracts $NETWORK $TAG
./scripts/upload_artifacts_gs.sh abis $NETWORK $TAG
./scripts/upload_artifacts_gs.sh circuits $NETWORK $TAG
```

- Commit the changes in `.openzeppelin/unknown-$NETWORK_ID.json.$TAG` file

## Deployment NFT Contracts

When a new version of the contracts, automatically the NFT common contracts are deployed too.
It's possible to deploy new instances having the ABIs and using the Nevermined CLI:

```bash

ncli nfts721 deploy build/contracts/token/erc721/NFT721SubscriptionUpgradeable.sol/NFT721SubscriptionUpgradeable.json --params "Nevermined NFT" --params "NVM"


```

## Verifying contracts code in different networks

Once the contracts are deployed and the ABIs are uploaded into the artifacts repository, it's time to verify the contracts code
in all the different networks where this has been deployed.

The script to do that is `scripts/contracts/verify-contracts.js` and requires the following parameters:

- `version` the version/tag of the contracts. For example `v2.1.0`
- `network` refers to network name, based on filename/hardhat config. For example `goerli`
- `tag` refers to deployment tag. For example `public`

An example of an execution is:

```bash
nodejs ./scripts/contracts/verify-contracts.js v3.1.0 mumbai public
```

## Document

### Contracts documentation

- Update the contracts documentation
- run `yarn doc:contracts`
- Commit the changes in `docs/contracts` folder

## Trigger CI

- Commit the missing changes to the feature branch.
- Tag the last commit with the new version number ie. `v0.2.5`
- Push the feature branch to GitHub.
- Make a pull request from the just-pushed branch to `develop` branch.
- Wait for all the tests to pass!
- Merge the pull request into the `develop` branch.

## Release and packages

The release itself is done by `github actions` based on the tagged commit.

It will deploy the following components:

- [npm](https://www.npmjs.com/package/@nevermined-io/contracts)
- [docker](https://hub.docker.com/r/neverminedio/contracts)

The npm, pypi and maven packages contain the contract artifacts for the contracts already deployed in different networks
(such as `Production`, `Rinkeby`, `Mumbai`, `Testing`, or `Spree`).
The docker image generated contains the contracts and script ready to be used to deploy the contracts to a network.
It is used for deploying the contracts in the local network `Spree` in [nevermined-io/tools](https://github.com/nevermined-io/tools)

Once the new version is tagged and released, you can edit the `Releases` section of GitHub with the information and
changes about the new version (in the future, these will come from the changelog):

## Audit

To check or document that all transactions have been approved in the multi sig wallet you can run `yarn audit:rinkeby`
to get a list of all the current transactions and their current status.

```text
 Wallet: 0x24EB26D4042a2AB576E7E39b87c3f33f276AeF92

 Transaction ID: 64
 Destination: 0xfA16d26e9F4fffC6e40963B281a0bB08C31ed40C
 Contract: EscrowAccessSecretStoreTemplate
 Data is `upgradeTo` call: true
 Confirmed from: 0x7A13E1aD23546c9b804aDFd13e9AcB184EfCAF58
 Executed: false
```
