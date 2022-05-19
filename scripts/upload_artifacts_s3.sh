#!/usr/bin/env bash

# Usage: ./upload_artifacts_s3.sh <asset> <network> [<tag>]
# <asset> can be abis/contracts/circuits. Use abis if you want to upload the contract ABIs that not contain deployment information. contracts for uploading abis with deployment information to <network>
# <network> refers to network name, based on filename/hardhat config
# <tag> refers to deployment tag. Defaults to common
# Example1: ./upload_artifacts_s3.sh abis
# Example2: ./upload_artifacts_s3.sh contracts mumbai awesome_tag
# Dependencies: awscli, zip, tar, jq. All in path. Run on Linux/macOS
# Dependencies: No spaces in folder/file names
# Dependencies: Contract names cannot start with -
# Dependencies: AWS profile with access to $BUCKET configured
ASSET=$1
NETWORK=$2
TAG=$3

if [[ "$ASSET" != "abis" && "$ASSET" != "contracts" && "$ASSET" != "circuits" ]]; then
  echo "ERROR: Asset not provided. Usage: ./upload_artifacts_s3.sh <asset> <network> [<tag>]. Asset must be abis, contracts or circuits"
  exit 1
fi
if [[ "$ASSET" == "contracts" && -z "$NETWORK" ]]; then
  echo "ERROR: Network not provided. Usage: ./upload_artifacts_s3.sh <asset> <network> [<tag>]"
  exit 1
fi
if [ -z "$TAG" ]; then
  TAG="common"
fi

SCRIPT_DIR=$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd)
CONTRACTS_DIR="$SCRIPT_DIR/../artifacts"
CIRCUITS_DIR="$SCRIPT_DIR/../circuits"
ABIS_DIR="$SCRIPT_DIR/../build/contracts"
BUCKET="artifacts-nevermined-rocks"
OUTPUT_FOLDER="/tmp"
DEPENDENCIES=(aws zip tar jq)
declare -A NETWORKS_MAP
NETWORKS_MAP=( ["mainnet"]="1" ["rinkeby"]="4" ["kovan"]="42" ["matic"]="137" ["mumbai"]="80001" ["celo-alfajores"]="44787" ["celo"]="42220" ["aurora"]="1313161554" ["aurora-testnet"]="1313161555" )

function check_dependencies {
  for dep in "${DEPENDENCIES[@]}"; do
    if ! [ -x "$(command -v $dep)" ]; then
      echo "ERROR: $dep command not found in PATH. Please install it" >&2
      exit 1
    fi
  done
}

function package_contracts {
  local filenames filenames_spaced version
  version=$(check_and_get_contract_version)
  filenames=$(get_network_contracts_no_path)
  filenames_spaced=$(echo "${filenames}" | tr '\n' ' ')
  
  cd "$CONTRACTS_DIR" >/dev/null 2>&1 || exit 1
  zip -9 "$OUTPUT_FOLDER/contracts_$version.zip" $filenames_spaced >/dev/null
  tar -czf "$OUTPUT_FOLDER/contracts_$version.tar.gz" $filenames_spaced
  cd - >/dev/null 2>&1 || exit 1
}

function package_circuits {
  local filenames filenames_spaced version
  version=$(check_and_get_abis_version)
  filenames=$(get_network_circuits_no_path)
  filenames_spaced=$(echo "${filenames}" | tr '\n' ' ')

  cd "$CIRCUITS_DIR" >/dev/null 2>&1 || exit 1
  zip -9 "$OUTPUT_FOLDER/circuits_$version.zip" $filenames_spaced >/dev/null
  tar -czf "$OUTPUT_FOLDER/circuits_$version.tar.gz" $filenames_spaced
  cd - >/dev/null 2>&1 || exit 1
}

function package_abis {
  local filenames filenames_spaced version
  version=$(check_and_get_abis_version)
  filenames=$(get_network_abis_no_root_path)
  filenames_spaced=$(echo "${filenames}" | tr '\n' ' ')
  
  cd "$ABIS_DIR" >/dev/null 2>&1 || exit 1
  zip -9 "$OUTPUT_FOLDER/abis_$version.zip" $filenames_spaced
  tar -czf "$OUTPUT_FOLDER/abis_$version.tar.gz" $filenames_spaced
  cd - >/dev/null 2>&1 || exit 1
}

function upload_contracts_s3 {
  local network_id version
  network_id=$(get_network_id_from_name)
  version=$(check_and_get_contract_version)
  aws s3 cp "$OUTPUT_FOLDER/contracts_$version.json" "s3://$BUCKET/$network_id/$TAG/"
  aws s3 cp "$OUTPUT_FOLDER/contracts_$version.zip" "s3://$BUCKET/$network_id/$TAG/"
  aws s3 cp "$OUTPUT_FOLDER/contracts_$version.tar.gz" "s3://$BUCKET/$network_id/$TAG/"
}

function upload_circuits_s3 {
  local version
  version=$(check_and_get_abis_version)
  aws s3 cp "$OUTPUT_FOLDER/circuits_$version.zip" "s3://$BUCKET/circuits/"
  aws s3 cp "$OUTPUT_FOLDER/circuits_$version.tar.gz" "s3://$BUCKET/circuits/"
}

function upload_abis_s3 {
  local version
  version=$(check_and_get_abis_version)
  aws s3 cp "$OUTPUT_FOLDER/abis_$version.zip" "s3://$BUCKET/abis/"
  aws s3 cp "$OUTPUT_FOLDER/abis_$version.tar.gz" "s3://$BUCKET/abis/"
}

# Returns array with the filename of the contracts
function get_network_contracts {
  local filenames
  filenames=$(ls "$CONTRACTS_DIR"/*."$NETWORK".json)
  echo "$filenames"
}

# Returns array with the filename of the contracts
function get_network_contracts_no_path {
  local filenames
  cd "$CONTRACTS_DIR" >/dev/null 2>&1 || exit 1
  # 
  filenames=$(ls *."$NETWORK".json)
  cd - >/dev/null 2>&1 || exit 1
  echo "$filenames"
}

function get_network_abis_no_root_path {
  local filenames
  cd "$ABIS_DIR" >/dev/null 2>&1 || exit 1
  filenames=$(find . -name '*.json' | grep -v dbg.json | grep -v /test/)
  cd - >/dev/null 2>&1 || exit 1
  echo "$filenames"
}

function get_network_circuits_no_path {
  local filenames
  cd "$CIRCUITS_DIR" >/dev/null 2>&1 || exit 1
  filenames=$(find .)
  cd - >/dev/null 2>&1 || exit 1
  echo "$filenames"
}

# Compare that the version of all contracts is the same.
# TODO: Think if is better to skip if version does not match
function check_and_get_contract_version {
  local filenames filenamesarray
  filenames=$(get_network_contracts)
  filenamesarray=($filenames)
  local ref_version
  ref_version=$(jq -r .version "${filenamesarray[0]}")
  for artifact in "${filenamesarray[@]}"; do
    local version
    version=$(jq -r .version "${artifact}")
    if [[ "$version" != "$ref_version" ]]; then
      echo "ERROR: Artifact versions do not match. Artifact ${artifact} version ${version} is different to version ${ref_version} from ${filenamesarray[0]}"
      exit 1
    fi
  done
  echo "$ref_version"
}

function check_and_get_abis_version {
  local version
  version=$(jq -r .version "$SCRIPT_DIR/../package.json")
  echo "$version"
}

# Return numerical chainId given a network name (considering networks names from our hardhat config)
function get_network_id_from_name {
  local network_id
  network_id="${NETWORKS_MAP[$NETWORK]}"
  if [ -z "$network_id" ]; then
    echo "ERROR: NetworkID for network ${NETWORK} not found. Please review the mapping in the scripts"
    echo exit 1
  fi
  echo "$network_id"
}

function generate_registry_json {
  local filenames version filenamesarray address contract_name
  filenames=$(get_network_contracts_no_path)
  filenamesarray=($filenames)
  # declare -A CONTRACT_REGISTRY_MAP

  cd "$CONTRACTS_DIR" >/dev/null 2>&1 || exit 1
  for artifact in "${filenamesarray[@]}"; do
    address=$(jq -r .address "$artifact")
    contract_name=${artifact%%.*}
    # CONTRACT_REGISTRY_MAP["$contract_name"]="$address"
    # echo "$contract_name -> $address"
    echo "$contract_name"
    echo "$address"
  done |
  jq -n -R 'reduce inputs as $i ({}; . + { ($i): (input|(tonumber? // .)) })'
  cd - >/dev/null 2>&1 || exit 1
}

function generate_registry_json_file {
  local version
  version=$(check_and_get_contract_version)

  generate_registry_json > "$OUTPUT_FOLDER/contracts_$version.json"
}

function main {
  check_dependencies
  if [[ "$ASSET" == "abis" ]]; then
    main_abis
  elif [[ "$ASSET" == "contracts" ]]; then
    main_contracts
  elif [[ "$ASSET" == "circuits" ]]; then
    main_circuits
  fi
}

function main_abis {
  package_abis
  upload_abis_s3
}

function main_circuits {
  package_circuits
  upload_circuits_s3
}

function main_contracts {
  package_contracts
  generate_registry_json_file
  upload_contracts_s3
}

main

