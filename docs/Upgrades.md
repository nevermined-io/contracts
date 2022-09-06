# Upgrade Process

This documents explains in detail how [nevermined-contracts](https://github.com/nevermined-io/contracts) should be
deployed using zeppelinOS and how the contracts can be upgraded. The latest section describes the test procedure.

## Quickstart

The first step to work with `zos` is to install dependencies then initialize the project. Then compile contracts and add contracts to the project.
Finally push the contracts into the network and create the  upgradable instances. Once the contracts are deployed they can be tested and upgraded.
Also we change the proxy administrator to a MultiSignature wallet to approve upgrades.
We are going to use the [Nevermined Contract Tools](https://github.com/nevermined-io/contract-tools) in order to perform
any future deployments/upgrades.

## Details

Here we provide more details into each step of the initial deploy and the approach of upgradeability and governance.

## Roles

> :warning: wallets.json file is needed if using a Gnosis MultiSig Wallet for the deployment. Currently none of the Nevermined contract deployments is using Gnosis Multisig wallets.

Before going into more details about the deployment. We should differentiate between different roles in the system which
govern the upgradeability in nevermined-contracts.

Roles are defined as follows (check code configuration in [wallets.js](../scripts/deploy/truffle-wrapper/wallets.js)):

```text
deployer: represented as accounts[8]
upgrader: represented as accounts[8]
governor: represented as accounts[9]
ownerWallet: represented as the owner from wallets.json or accounts[8]
upgraderWallet: represented as the upgrader from wallets.json or accounts[8]
governorWallet: represented as the governor from wallets.json or accounts[9]
```

- **Deployer**: Can be any account. It is used for deploying the initial `proxy contracts` and the `logic contracts`.

- **Upgrader**: Has to be an `owner` of the `upgrader` multi sig wallet. It is used for issuing upgrade requests against the upgrader multi sig wallet.

- **Governor**: Has to have the `GOVERNOR_ROLE` in the contracts. It is used for issuing upgrade config requests.
-
- **UpgraderWallet**: One instance of the multi sig wallet, defined as `upgrader`. This wallet will be assigned as zos admin and is required to do upgrades.

- **OwnerWallet**: One instance of the multi sig wallet, defined as `owner`. This wallet will be assigned as the owner of all the contracts. It can be used to call specific functions in the contracts ie. change the configuration.

- **GovernorWallet**: One instance of the multi sig wallet, defined as `governor`. This wallet will be assigned as zos admin and is required to do config updates in a Nevermined deployment.

## Deploy & Upgrade

`zos` does not support migrations, hence all the initial configuration should be performed with
[Nevermined Contract Tools](https://github.com/nevermined-io/contract-tools).
Contract constructors are ignored so the initial setup of the contract should be made in a
[`initialize`](https://docs.zeppelinos.org/docs/advanced.html#initializers-vs-constructors)
function that will be executed only once after the initial deployment.

### 1. Configuration

[Nevermined Contract Tools](https://github.com/nevermined-io/contract-tools) checks the `contracts.json` in order to
detect the current contracts that are going to be deployed:

```json
[
  "ConditionStoreManager",
  "TemplateStoreManager",
  "AgreementStoreManager",
  "SignCondition",
  "HashLockCondition",
  "LockRewardCondition",
  "NFTHolderCondition",
  "AccessCondition",
  "EscrowReward",
  "EscrowAccessSecretStoreTemplate",
  "NFTAccessTemplate",
  "DIDRegistry"
]
```

Moreover for each network, [Nevermined Contract Tools](https://github.com/nevermined-io/contract-tools) needs to detect
the roles and their addresses from a pre-defined wallets config file.
The following configuration should be an example for `wallets-<NETWORK_NAME>.json`:

```json
[
    {
        "name": "upgrader",
        "address": "0x24eb26d4042a2ab576e7e39b87c3f33f276aef92"
    },
    {
        "name": "owner",
        "address": "0xd02d68c62401472ce35ba3c7e505deae62db2b8b"
    },
    {
        "name": "governor",
        "address": "0xeeff68c62401472ce35ba3c7e505deae62db2b8b"
    }
]
```

### 2. Preparation

The following commands clean, install dependencies and compile the contracts:

```console
yarn clean #to clean the work dir
yarn #install dependencies
yarn compile #to compile the contracts
```

### 3. Deploy & Upgrade

The following steps shows how to perform contracts deployment and upgrade on `Mumbai` and `<Polygon>` networks.

#### Copy the files and artifacts

- Export the `NETWORK_ID` (check in https://chainlist.org/) and contract's tag `TAG`, and latest version deployed `VERSION` for this contract release:

```bash
export NETWORK_ID=80001 # Network_ID for mumbai
export NETWORK=mumbai
export TAG=common
export VERSION='2.0.0'
```

- Copy the .openzeppelin file for the `<NETWORK_ID>` and `<TAG>`(like `common` or `public`) deployment you want to upgrade:
  - `cp .openzeppelin/unknown-$NETWORK_ID.json.$TAG .openzeppelin/unknown-$NETWORK_ID.json`
- Unpack the latest version of the artifacts for the `<NETWORK_ID>` and `<TAG>` in `artifacts`:

```bash
wget -O artifacts.tar.gz "http://artifacts-nevermined-rocks.s3.amazonaws.com/$NETWORK_ID/$TAG/contracts_v$VERSION.tar.gz"
tar xvzf artifacts.tar.gz -C artifacts/
```

- run `export MNEMONIC=<deployment's mnemonic>`. You will find them in the password manager.

##### Upgrade already deployed contracts

- To upgrade the contracts run `yarn upgrade:$NETWORK`

##### Deploy and initialize any new contract not present in the old deployed version

- To deploy and initialize all contracts run `yarn deploy:$NETWORK`

This process will show multiple errors for the contracts that are being upgraded. You can ignore those messages.

##### Upgrade the plonk verifier contract to the new version

- To upgrade the plonk verifier contract to the new version run `npx hardhat run ./scripts/deploy/truffle-wrapper/upgradePlonkVerifier.js --network $NETWORK`

##### Upload the artifacts to the repository and persist any change in `openzeppelin/` file

- To upload the artifacts to the repository run `./scripts/upload_artifacts_s3.sh contracts $NETWORK $TAG`. You need to have access to S3.

- Copy the openzeppeling file base on tag: `cp -rp .openzeppelin/unknown-$NETWORK_ID.json .openzeppelin/unknown-$NETWORK_ID.json.$TAG`

- Commit all changes in `.openzeppelin/unknown-$NETWORK_ID.json.$TAG` file

### 4. Approve Upgrade(s) -no applicable for current deployments-

All upgrades of the contracts have to be approved by the `upgrader` wallet configured in the `wallets.json` file.

- go to <https://wallet.gnosis.pm>
- Load `upgrader` wallet
- Select an Ethereum Account that is an `owner` of the multi sig wallet, but not the one who issued the upgrade request. This can be done in the following ways:
  - Connect to a local Blockchain node that holds the private key.
  - Connect to MetaMask and select the owner account from the multi sig wallet.
  - Connect a hardware wallet like ledger or trezor.
- Select the transaction you want to confirm (the upgrade script will tell you which transactions have to be approved in which wallets)
- Click Confirm

### 5. Audit Contracts -no applicable for current deployments-

To check or document that all transactions have been approved in the multi sig wallet you can run `yarn audit:rinkeby` to get a list of all the current transactions and their current status.

```text
 Wallet: 0x24EB26D4042a2AB576E7E39b87c3f33f276AeF92

 Transaction ID: 64
 Destination: 0xfA16d26e9F4fffC6e40963B281a0bB08C31ed40C
 Contract: EscrowAccessSecretStoreTemplate
 Data is `upgradeTo` call: true
 Confirmed from: 0x7A13E1aD23546c9b804aDFd13e9AcB184EfCAF58
 Executed: false
```
