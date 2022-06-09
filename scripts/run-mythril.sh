#!/bin/bash

ganache-cli --port 18545 &
sleep 5

export NO_PROXY=true

npx hardhat run ./scripts/deploy/truffle-wrapper/deployContractsWrapper.js --network external

for i in artifacts/*.external.json; do
  echo $i
  myth a -a $(jq -r .address $i) --rpc localhost:18545
done

