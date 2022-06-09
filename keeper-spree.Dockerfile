FROM openethereum/openethereum:v3.3.2 as openethereum

COPY networks/spree/config /home/openethereum/config
COPY networks/spree/authorities/validator0.json /home/openethereum/.local/keys/spree/validator.json
COPY networks/spree/keys /home/openethereum/.local/keys/spree
COPY networks/spree/authorities/validator0.pwd /home/openethereum/validator.pwd



FROM node:14-alpine as deploy

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

COPY --from=openethereum /home/openethereum /home/openethereum

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn
RUN sh ./scripts/build-circuit.sh

ENV MNEMONIC="taxi music thumb unique chat sand crew more leg another off lamp"
ENV DEPLOY_CONTRACTS=true
ENV LOCAL_CONTRACTS=true
ENV REUSE_DATABASE=false
ENV NETWORK_NAME=spree
ENV KEEPER_RPC_HOST=localhost
ENV KEEPER_RPC_PORT=8545

RUN  /nevermined-contracts/scripts/keeper_deploy_dockerfile.sh

FROM openethereum/openethereum:v3.3.2
LABEL maintainer="Nevermined <root@nevermined.io>"

COPY scripts/keeper_entrypoint_nodeploy.sh /

COPY --from=deploy /nevermined-contracts/artifacts2 /artifacts
COPY --from=deploy /nevermined-contracts/circuits2 /circuits
COPY --from=deploy /home/openethereum /home/openethereum

ENTRYPOINT ["/keeper_entrypoint_nodeploy.sh"]
