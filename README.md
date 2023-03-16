[![banner](https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png)](https://nevermined.io)

# Nevermined Smart Contracts

> 💧 Smart Contracts implementation of Nevermined in Solidity
> [nevermined.io](https://nevermined.io)

[![Docker Build Status](https://img.shields.io/docker/cloud/build/neverminedio/contracts.svg)](https://hub.docker.com/r/neverminedio/contracts/)
[![Build and Tests](https://github.com/nevermined-io/contracts/actions/workflows/build.yml/badge.svg)](https://github.com/nevermined-io/contracts/actions/workflows/build.yml)

## Table of Contents

- [Nevermined Smart Contracts](#nevermined-smart-contracts)
  - [Table of Contents](#table-of-contents)
  - [Get Started](#get-started)
    - [Docker](#docker)
    - [Local development](#local-development)
  - [Testing](#testing)
    - [Code Linting](#code-linting)
  - [Networks](#networks)
  - [Packages](#packages)
  - [Documentation](#documentation)
  - [Prior Art](#prior-art)
  - [Attribution](#attribution)
  - [License](#license)

---

## Get Started

For local development of `nevermined-contracts` you can either use Docker, or setup the development environment on your machine.

### Docker

The simplest way to get started with is using the [Nevermined Tools](https://github.com/nevermined-io/tools),
a docker compose application to run all the Nevermined stack.

### Public Network development

For deploying in a public network check [ReleaseProcess.md](./docs/ReleaseProcess.md) first.

### Local development

As a pre-requisite, you need:

* Node.js
* yarn

Clone the project and install all dependencies:

```bash
git clone git@github.com:nevermined-io/contracts.git
cd contracts/
```

Install dependencies:

```bash
yarn
```

Compile the solidity contracts:

```bash
yarn compile
```

In a new terminal, launch an Ethereum RPC client, e.g. hardhat:

```bash
npx hardhat node --port 18545
```

Switch back to your other terminal and deploy the contracts:

```bash
yarn deploy:external
```

For redeployment run this instead

```bash
yarn clean
yarn compile
yarn deploy:external
```

Upgrade contracts [**optional**]:

```bash
yarn upgrade:external
```

## Testing

Run tests with `yarn test`, e.g.:

```bash
yarn test test/unit/agreements/AgreementStoreManager.Test.js
```

### Code Linting

Linting is setup for `JavaScript` with [ESLint](https://eslint.org) & Solidity with [Ethlint](https://github.com/duaraghav8/Ethlint).

Code style is enforced through the CI test process, builds will fail if there're any linting errors.

```bash
yarn lint
```

## Networks

When Nevermined contracts are deployed into different networks, the ABIs referring to the specific
version deployed are copied into the [Artifacts repository](https://artifacts.nevermined.network/).

You can find more information about the this into the [Release Process documentation](docs/ReleaseProcess.md).

For contracts older to v3.x please see the [Legacy Artifacts Repository](https://artifacts.nevermined.rocks/).

## Documentation

* [Contracts Documentation](doc/contracts/README.md)
* [Release process](doc/RELEASE_PROCESS.md)
* [Packaging of libraries](doc/PACKAGING.md)
* [Upgrading of contracts](doc/UPGRADES.md)
* [Template lifecycle](doc/TEMPLATE_LIFE_CYCLE.md)

## Prior Art

This project builds on top of the work done in open source projects:

* [zeppelinos/zos](https://github.com/zeppelinos/zos)
* [OpenZeppelin/openzeppelin-eth](https://github.com/OpenZeppelin/openzeppelin-eth)

## Attribution

This project is based in the Ocean Protocol [Keeper Contracts](https://github.com/oceanprotocol/keeper-contracts).
It keeps the same Apache v2 License and adds some improvements. See [NOTICE file](NOTICE).

## License

```text
Copyright 2023 Nevermined AG
This product includes software developed at
BigchainDB GmbH and Ocean Protocol (https://www.oceanprotocol.com/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
