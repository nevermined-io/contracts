FROM node:16
LABEL maintainer="Keyko <root@keyko.io>"

RUN apt-get install\
      bash\
      g++\
      gcc\
      git\
      make\
      curl

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn

ENV MNEMONIC="taxi music thumb unique chat sand crew more leg another off lamp"
ENV DEPLOY_CONTRACTS=true
ENV LOCAL_CONTRACTS=true
ENV REUSE_DATABASE=false
ENV NETWORK_NAME=hardhat-localnet
ENV KEEPER_RPC_HOST=localhost
ENV KEEPER_RPC_PORT=8545

RUN /nevermined-contracts/scripts/keeper_deploy_ganache_dockerfile.sh

ENTRYPOINT ["/nevermined-contracts/scripts/keeper_entrypoint_hardhat.sh"]
