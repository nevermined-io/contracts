#!/bin/bash

ganache-cli --port 18545 &
sleep 5

export NO_PROXY=true

npx hardhat run ./scripts/deploy/deployContractsWrapper.js --network external

for i in artifacts/*.external.json; do
  echo $i
  myth a -a $(jq -r .address $i) --rpc localhost:18545 -o markdown --execution-timeout 30 -t 5 2>> mythril_report.txt
done
