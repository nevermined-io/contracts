[![banner](https://raw.githubusercontent.com/nevermined-io/assets/main/images/logo/banner_logo.png)](https://nevermined.io)

# Nevermined Smart Contracts

> 💧 Smart Contracts implementation of Nevermined in Solidity
> [nevermined.io](https://nevermined.io)


[![Docker Build Status](https://img.shields.io/docker/cloud/build/neverminedio/contracts.svg)](https://hub.docker.com/r/neverminedio/contracts/)
![Build](https://github.com/nevermined-io/contracts/workflows/Build/badge.svg)
![NPM Package](https://github.com/nevermined-io/contracts/workflows/NPM%20Release/badge.svg)
![Pypi Package](https://github.com/nevermined-io/contracts/workflows/Pypi%20Release/badge.svg)
![Maven Package](https://github.com/nevermined-io/contracts/workflows/Maven%20Release/badge.svg)


Table of Contents
=================

   * [Nevermined Smart Contracts](#nevermined-smart-contracts)
      * [Table of Contents](#table-of-contents)
      * [Get Started](#get-started)
         * [Docker](#docker)
         * [Local development](#local-development)
      * [Testing](#testing)
         * [Code Linting](#code-linting)
      * [Networks](#networks)
         * [Testnets](#testnets)
            * [Integration Testnet](#integration-testnet)
            * [Staging Testnet](#staging-testnet)
         * [Mainnets](#mainnets)
         * [Production Mainnet](#production-mainnet)
      * [Packages](#packages)
      * [Documentation](#documentation)
      * [Prior Art](#prior-art)
      * [Attribution](#attribution)
      * [License](#license)


---

## Get Started

For local development of `nevermined-contracts` you can either use Docker, or setup the development environment on your machine.

### Docker

The simplest way to get started with is using the [Nevermined Tools](https://github.com/nevermined-io/tools),
a docker compose application to run all the Nevermined stack.

### Local development

As a pre-requisite, you need:

- Node.js
- yarn

Note: For MacOS, make sure to have `node@10` installed.

Clone the project and install all dependencies:

```bash
git clone git@github.com:nevermined-io/contracts.git
cd nevermined-contracts/
```

Install dependencies:
```bash
yarn
```

Compile the solidity contracts:
```bash
yarn compile
```

In a new terminal, launch an Ethereum RPC client, e.g. [ganache-cli](https://github.com/trufflesuite/ganache-cli):

```bash
npx ganache-cli@~6.9.1 > ganache-cli.log &
```

Switch back to your other terminal and deploy the contracts:

```bash
yarn test:fast
```

For redeployment run this instead
```bash
yarn clean
yarn compile
yarn test:fast
```

Upgrade contracts [**optional**]:
```bash
yarn upgrade
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

### Testnets

The contract addresses deployed on Nevermined `Alfajores` Test Network:

#### Alfajores Testnet

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| AccessCondition                   | v1.0.0 | `0x81b5764e3A79b195bfe6887B18e232b17e22d356` |
| AccessTemplate                    | v1.0.0 | `0x1fF6fBf77cc417674462A356905C033cc5a5dc97` |
| AgreementStoreManager             | v1.0.0 | `0x5Ab356eCeF4f1041Eefb13A66118b0ddCeD9E544` |
| ComputeExecutionCondition         | v1.0.0 | `0x9F0f6AA800199323D8894f03ac4dA8Eea62Fe882` |
| ConditionStoreManager             | v1.0.0 | `0x7d30e7462351d3287DF51280f4954585a5BaF952` |
| DIDRegistry                       | v1.0.0 | `0xb5E59f4BaCDC5cBb5ace97e37DD4b34A718Befbe` |
| DIDRegistryLibrary                | v1.0.0 | `0xf3b4547dD0f2475400121C7595c18172b40B50F0` |
| DIDSalesTemplate                  | v1.0.0 | `0x50D5c496e35b9A8f2aE42a6430e198DdB644Db53` |
| Dispenser                         | v1.0.0 | `0x611A767a6aD5EFfF3F9824CFa83d5BCdD1b0eE29` |
| EpochLibrary                      | v1.0.0 | `0xfFfa1141156fEE5ad3E0a1cA7f7D0aD1454FE7e8` |
| EscrowComputeExecutionTemplate    | v1.0.0 | `0xe183896ecF5864c25cfEedCF66a6D09259D89408` |
| EscrowPaymentCondition            | v1.0.0 | `0xaC79aC52b944B0b3058A12d8E29141E58A15c668` |
| HashLockCondition                 | v1.0.0 | `0xF2d2885343076e7B5BA5344F4603c15C412Db6eB` |
| LockPaymentCondition              | v1.0.0 | `0x8721df21E964d8ff10a69C60eef6Da46B003e67A` |
| NFTAccessCondition                | v1.0.0 | `0xed33f04A3a4Afdb263359f9D45fd235709Ce4577` |
| NFTAccessTemplate                 | v1.0.0 | `0xA6342881e0A93485e8819e5BeDfb062be25c451f` |
| NFTHolderCondition                | v1.0.0 | `0x209D112C4D1a0dfD10E2A900049ba46C03d8E139` |
| NFTLockCondition                  | v1.0.0 | `0x59FD917C0D8eE2D861828bFdc460f6c47A5214B5` |
| NFTSalesTemplate                  | v1.0.0 | `0xb55fF4Ed2001D006AC687793938ED68eD55BE96F` |
| NeverminedToken                   | v1.0.0 | `0x697881320067572788FC29e16ae6d635970C3bc5` |
| SignCondition                     | v1.0.0 | `0xf94D02a89ceB8f0013292782902937D3a2F8C25B` |
| TemplateStoreManager              | v1.0.0 | `0x14787AC28C7B6dCC4B856abd4E7Dee555B0170ab` |
| ThresholdCondition                | v1.0.0 | `0x47589D3f675037F4Ff174ceb40577743bCFd622d` |
| TransferDIDOwnershipCondition     | v1.0.0 | `0x52d2D0529EEDECE81aD381b21d860D54F55Da1dc` |
| TransferNFTCondition              | v1.0.0 | `0x6479Bc5ff22C66ac50641460dE90CD52d0118274` |
| WhitelistingCondition             | v1.0.0 | `0xAD1DD4D63aA874f677FD8Eafc227bEd81DD93834` |


#### Bakalva Testnet

The contract addresses deployed on Nevermined `Baklava` Test Network:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| AccessCondition                   | v1.0.0 | `0x7ff61090814B4159105B88d057a3e0cc1058ae44` |
| AccessTemplate                    | v1.0.0 | `0x39fa249ea6519f2076f304F6906c10C1F59B2F3e` |
| AgreementStoreManager             | v1.0.0 | `0x02Dd2D50f077C7060E4c3ac9f6487ae83b18Aa18` |
| ComputeExecutionCondition         | v1.0.0 | `0x411e198cf1F1274F69C8d9FF50C2A5eef95423B0` |
| ConditionStoreManager             | v1.0.0 | `0x028ff50FA80c0c131596A4925baca939E35A6164` |
| DIDRegistry                       | v1.0.0 | `0xd1Fa86a203902F763D6f710f5B088e5662961c0f` |
| DIDRegistryLibrary                | v1.0.0 | `0x93468169aB043284E53fb005Db176c8f3ea1b3AE` |
| DIDSalesTemplate                  | v1.0.0 | `0x862f483F35B136313786D67c0794E82deeBc850a` |
| Dispenser                         | v1.0.0 | `0xED520AeF97ca2afc2f477Aab031D9E68BDe722b9` |
| EpochLibrary                      | v1.0.0 | `0x42623Afd182D3752e2505DaD90563d85B539DD9B` |
| EscrowComputeExecutionTemplate    | v1.0.0 | `0xfB5eA07D3071cC75bb22585ceD009a443ed82c6F` |
| EscrowPaymentCondition            | v1.0.0 | `0x0C5cCd10a908909CF744a898Adfc299bB330E818` |
| HashLockCondition                 | v1.0.0 | `0xe565a776996c69E61636907E1159e407E3c8186d` |
| LockPaymentCondition              | v1.0.0 | `0x7CAE82F83D01695FE0A31099a5804bdC160b5b36` |
| NFTAccessCondition                | v1.0.0 | `0x49b8BAa9Cd224ea5c4488838b0454154cFb60850` |
| NFTAccessTemplate                 | v1.0.0 | `0x3B2b32cD386DeEcc3a5c9238320577A2432B03C1` |
| NFTHolderCondition                | v1.0.0 | `0xa963AcB9d5775DaA6B0189108b0044f83550641b` |
| NFTLockCondition                  | v1.0.0 | `0xD39e3Eb7A5427ec4BbAf761193ad79F6fCfA3256` |
| NFTSalesTemplate                  | v1.0.0 | `0xEe41F61E440FC2c92Bc7b0a902C5BcCd222F0233` |
| NeverminedToken                   | v1.0.0 | `0xEC1032f3cfc8a05c6eB20F69ACc716fA766AEE17` |
| SignCondition                     | v1.0.0 | `0xb96818dE64C492f4B66B3500F1Ee2b0929C39f6E` |
| TemplateStoreManager              | v1.0.0 | `0x4c161ea5784492650993d0BfeB24ff0Ac2bf8437` |
| ThresholdCondition                | v1.0.0 | `0x08D93dFe867f4a20830f1570df05d7af278c5236` |
| TransferDIDOwnershipCondition     | v1.0.0 | `0xdb6b856F7BEBba870053ba58F6e3eE48448173d3` |
| TransferNFTCondition              | v1.0.0 | `0x2de1C38030A4BB0AB4e60E600B3baa98b73400D9` |
| WhitelistingCondition             | v1.0.0 | `0x6D8D5FBD139d81dA245C3c215E0a50444434d11D` |


#### Rinkeby Testnet

The contract addresses deployed on Nevermined `Rinkeby` Test Network:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| AccessCondition                   | v1.0.0-rc6 | `0xfBa38fa846E5c38845AA87Eb43Ed571Df6f71938` |
| AccessTemplate                    | v1.0.0-rc6 | `0x5DFd35399B64bD8457b3667Ba79D83A31Bc08D28` |
| AgreementStoreManager             | v1.0.0-rc6 | `0x2d8BCaDdf251384C28644155bB853fd200f2Ff2B` |
| ComputeExecutionCondition         | v1.0.0-rc6 | `0xa99b7B332CFd88b127513A1f55BD13c5d7de4C16` |
| ConditionStoreManager             | v1.0.0-rc6 | `0xa42e0C25Ef78e7DC1676384fecE2e54B291a99fc` |
| DIDRegistry                       | v1.0.0-rc6 | `0x38fc69a8b1A347677D713420Fc9E8EaCcBE3C3C2` |
| DIDRegistryLibrary                | v1.0.0-rc6 | `0x48639b9712C847b3dd5b8a751719B59aB62c2C9F` |
| DIDSalesTemplate                  | v1.0.0-rc6 | `0xfBe606e48ca0DD942a1D055DcfD58Fdf507b6725` |
| Dispenser                         | v1.0.0-rc6 | `0x7218c9880e139258E6c90C124cde058A6A2dF896` |
| EpochLibrary                      | v1.0.0-rc6 | `0xf92465Ec1BEfc3dE58bBfbA2F2d5A72aaAfb06C2` |
| EscrowComputeExecutionTemplate    | v1.0.0-rc6 | `0x943C561Be307749f65B8A884A3388B6439dCeeec` |
| EscrowPaymentCondition            | v1.0.0-rc6 | `0x3C4C38F5cdBF706a8f6355a60Fbcfd92d58Aad8a` |
| HashLockCondition                 | v1.0.0-rc6 | `0x19c50775D9B93D6C1b9C0b2Ac9651F9a8281CaFD` |
| LockPaymentCondition              | v1.0.0-rc6 | `0xC57e97bC1602FF9F970B4C94884178134b4CD9De` |
| NFTAccessCondition                | v1.0.0-rc6 | `0xFC46F8B2272D1aFbFae4d35357D618F10f7ba11F` |
| NFTAccessTemplate                 | v1.0.0-rc6 | `0x761A7cC5def5C2413141B3Ae0652937A0aB95609` |
| NFTHolderCondition                | v1.0.0-rc6 | `0x1B62A9418eb908535251dfD15ac252505EB81567` |
| NFTLockCondition                  | v1.0.0-rc6 | `0x4d3a045ECec1EA3D9Ee063af7127177958f5cfc6` |
| NFTSalesTemplate                  | v1.0.0-rc6 | `0x88B96A210e8f6f27BA59f0CAF7F39cA2653B647F` |
| NeverminedToken                   | v1.0.0-rc6 | `0x623f78d38C72BbC034B0425aEa5238EB8d1D2d0D` |
| SignCondition                     | v1.0.0-rc6 | `0xDF2854d1116220C6C9397b592761f8b20D44471a` |
| TemplateStoreManager              | v1.0.0-rc6 | `0x21d13f36c65Bb51764d05b81d2cB2fbabCbc9E8d` |
| ThresholdCondition                | v1.0.0-rc6 | `0x2e33C50DBfc7Ee2cf12E118CE09F65c24ed02583` |
| TransferDIDOwnershipCondition     | v1.0.0-rc6 | `0xb84cCBb63e37DE7c0AD0eBd9694C5781df8354Df` |
| TransferNFTCondition              | v1.0.0-rc6 | `0x205bC979BC5aF48f7925005b6E1a5E0280bde823` |
| WhitelistingCondition             | v1.0.0-rc6 | `0xE5C62FF3f5fCC3dE062a5002f538a7027c3D355c` |


#### Mumbai (Polygon) Testnet

The contract addresses deployed on `Mymbai` Polygon Test Network:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| AccessCondition                   | v1.0.0-rc6 | `0x41D6c7De453Ae1b3BCa53668a65cd7DCEF5A9D49` |
| AccessTemplate                    | v1.0.0-rc6 | `0x7289b77E935dF615fE88f709f5E4DCBE785C9b3f` |
| AgreementStoreManager             | v1.0.0-rc6 | `0x9775311039d8a191ba1B1CC5a958C4FA187Fc6bC` |
| ComputeExecutionCondition         | v1.0.0-rc6 | `0x870EF7Df184099C9a84668E81B2a1132999ad807` |
| ConditionStoreManager             | v1.0.0-rc6 | `0xF5DC40c5A4401315deA3f7B25c578c1f1BBF27Cf` |
| DIDRegistry                       | v1.0.0-rc6 | `0xeAF9fD8c08A2c1ff40E4c66f49858A8A2737a817` |
| DIDRegistryLibrary                | v1.0.0-rc6 | `0x81B6B1745Ba204A2203787cCf6B7eD1157241A1a` |
| DIDSalesTemplate                  | v1.0.0-rc6 | `0x30AB0D02AB2CDd562E601725E4C25FD21f7FFe44` |
| Dispenser                         | v1.0.0-rc6 | `0xf13A10F68b1eF67Be18cdf303BE1EBF439bfE358` |
| EpochLibrary                      | v1.0.0-rc6 | `0x4D6FBFEF2b561E4C10b00a188d758E0490248730` |
| EscrowComputeExecutionTemplate    | v1.0.0-rc6 | `0xc9dA769E2aCc216db3f74846613B5c080d0C37Bd` |
| EscrowPaymentCondition            | v1.0.0-rc6 | `0x94BB362319238d3ceFeDF7f9E3fa178dD96253c2` |
| HashLockCondition                 | v1.0.0-rc6 | `0x55c91Fb3011aB0446fAae46e53244EBF2a8975C2` |
| LockPaymentCondition              | v1.0.0-rc6 | `0xc417A5CE4d65931f9433D54e134c831D1D78ad9A` |
| NFTAccessCondition                | v1.0.0-rc6 | `0x3EaFe36E98539672DD06578f8EE66aD2eE6ABC41` |
| NFTAccessTemplate                 | v1.0.0-rc6 | `0xf2ab741100F734090cdB19890305e5E96929bff4` |
| NFTHolderCondition                | v1.0.0-rc6 | `0x7822d38A9e1EEe6d0B98035115A9ec2E7F130ed1` |
| NFTLockCondition                  | v1.0.0-rc6 | `0x5794B837677AEd8e12ee194707fF1a7e55998B16` |
| NFTSalesTemplate                  | v1.0.0-rc6 | `0x7Dee2F5522565c463CceF89b511729BF6b702dA3` |
| NeverminedToken                   | v1.0.0-rc6 | `0xa763B0747A7772914AfEA681c31Af55c806B254E` |
| SignCondition                     | v1.0.0-rc6 | `0x9DedBd2903789b60745B6fa7dE5FB60EF9DdEaF2` |
| TemplateStoreManager              | v1.0.0-rc6 | `0x43fac08524e6836DC760313911ea32dFccee6fF0` |
| ThresholdCondition                | v1.0.0-rc6 | `0x707f6E0450dD507d5d43158974B73D2C63ABA0Cb` |
| TransferDIDOwnershipCondition     | v1.0.0-rc6 | `0x53D68ED4E865bD508E16379139869aFeE85b34f5` |
| TransferNFTCondition              | v1.0.0-rc6 | `0x77Ae9161Ca4B2b84CCB3E321854e029FEe01D7FE` |
| WhitelistingCondition             | v1.0.0-rc6 | `0xE4c350292860153e478e10849A5f3C6d9790Ebf3` |


#### Integration Testnet

The contract addresses deployed on Nevermined `Integration` Test Network:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| -                                 | -       | -                                            |


#### Staging Testnet

The contract addresses deployed on Nevermined `Staging` Test Network:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| -                                 | -       | -                                            |


### Mainnets

### Production Mainnet

The contract addresses deployed on `Production` Mainnet:

| Contract                          | Version | Address                                      |
|-----------------------------------|---------|----------------------------------------------|
| -                                 | -       | -                                            |


## Packages

To facilitate the integration of `nevermined-contracts` there are `Python`, `JavaScript` and `Java` packages ready to be integrated. Those libraries include the Smart Contract ABI's.
Using these packages helps to avoid compiling the Smart Contracts and copying the ABI's manually to your project. In that way the integration is cleaner and easier.
The packages provided currently are:

* JavaScript `NPM` package - As part of the [@nevermined-io npm organization](https://www.npmjs.com/settings/nevermined-io/packages),
  the [npm nevermined-contracts package](https://www.npmjs.com/package/@nevermined-io/contracts) provides the ABI's
  to be imported from your `JavaScript` code.
* Python `Pypi` package - The [Pypi nevermined-contracts package](https://pypi.org/project/nevermined-contracts/) provides
  the same ABI's to be used from `Python`.
* Java `Maven` package - The [Maven nevermined-contracts package](https://search.maven.org/artifact/io.keyko/nevermined-contracts)
  provides the same ABI's to be used from `Java`.

The packages contains all the content from the `doc/` and `artifacts/` folders.

In `JavaScript` they can be used like this:

Install the `nevermined-contracts` `npm` package.

```bash
npm install @nevermined-io/contracts
```

Load the ABI of the `NeverminedToken` contract on the `staging` network:

```javascript
const NeverminedToken = require('@nevermined-io/contracts/artifacts/NeverminedToken.staging.json')
```

The structure of the `artifacts` is:

```json
{
  "abi": "...",
  "bytecode": "0x60806040523...",
  "address": "0x45DE141F8Efc355F1451a102FB6225F1EDd2921d",
  "version": "v0.9.1"
}
```

## Documentation

* [Contracts Documentation](doc/contracts/README.md)
* [Release process](doc/RELEASE_PROCESS.md)
* [Packaging of libraries](doc/PACKAGING.md)
* [Upgrading of contracts](doc/UPGRADES.md)
* [Template lifecycle](doc/TEMPLATE_LIFE_CYCLE.md)

## Prior Art

This project builds on top of the work done in open source projects:
- [zeppelinos/zos](https://github.com/zeppelinos/zos)
- [OpenZeppelin/openzeppelin-eth](https://github.com/OpenZeppelin/openzeppelin-eth)

## Attribution

This project is based in the Ocean Protocol [Keeper Contracts](https://github.com/oceanprotocol/keeper-contracts).
It keeps the same Apache v2 License and adds some improvements. See [NOTICE file](NOTICE).

## License

```
Copyright 2020 Keyko GmbH
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
