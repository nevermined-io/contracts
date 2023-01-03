#!/bin/bash

export BASE=v2.0.0
export BRANCH=$(git rev-parse --abbrev-ref HEAD)

export TESTNET=true

# rm -rf artifacts/*.external.json deploy-cache.json
rm -f .openzeppelin/unknown-31337.json
git checkout $BASE || exit 1
yarn
yarn compile

npx hardhat node --port 18545 > /dev/null 2>&1 &

sleep 10

yarn deploy:external || exit 1

git checkout $BRANCH
yarn
sh ./scripts/build-circuit.sh || exit 1

export FAIL=true

npx hardhat run ./scripts/deploy/upgradeContractsWrapper.js --network external || exit 1
npx hardhat run ./scripts/deploy/deployContractsWrapper.js --network external || exit 1
npx hardhat run ./scripts/deploy/upgradePlonkVerifier.js --network external || exit 1

npx hardhat test --network external test/int/agreement/{AccessAgreement,AccessProofAgreement,EscrowComputeExecutionAgreement,NFTAccessAgreement}.Test.js test/int/nft/*.js || exit 1
