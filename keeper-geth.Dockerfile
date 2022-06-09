FROM ethereum/client-go:latest as geth

FROM node:14-alpine as deploy

COPY --from=geth /usr/local/bin/geth /usr/local/bin/geth

RUN apk add --no-cache --update\
      bash\
      g++\
      gcc\
      git\
      krb5-dev\
      krb5-libs\
      krb5\
      make\
      python3\
      curl

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn
RUN sh ./scripts/build-circuit.sh

ENV MNEMONIC="taxi music thumb unique chat sand crew more leg another off lamp"
ENV DEPLOY_CONTRACTS=true
ENV LOCAL_CONTRACTS=true
ENV REUSE_DATABASE=false
ENV NETWORK_NAME=polygon-localnet
ENV KEEPER_RPC_HOST=localhost
ENV KEEPER_RPC_PORT=8545

RUN /nevermined-contracts/scripts/keeper_deploy_geth_dockerfile.sh

FROM ethereum/client-go:latest
LABEL maintainer="Nevermined <root@nevermined.io>"

COPY scripts/keeper_entrypoint_geth.sh /
COPY --from=deploy /artifacts /artifacts
COPY --from=deploy /circuits /circuits
COPY --from=deploy /chain-data /chain-data

ENTRYPOINT ["/keeper_entrypoint_geth.sh"]
