FROM openethereum/openethereum:v3.2.6 as openethereum

COPY networks/spree/config /home/openethereum/config
COPY networks/spree/authorities/validator0.json /home/openethereum/.local/keys/spree/validator.json
COPY networks/spree/keys /home/openethereum/.local/keys/spree
COPY networks/spree/authorities/validator0.pwd /home/openethereum/validator.pwd



FROM node:10-alpine
LABEL maintainer="Keyko <root@keyko.io>"

RUN apk add --no-cache --update\
      bash\
      g++\
      gcc\
      git\
      krb5-dev\
      krb5-libs\
      krb5\
      make\
      python\
      curl

COPY --from=openethereum /home/openethereum /home/openethereum

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn

ENV MNEMONIC="taxi music thumb unique chat sand crew more leg another off lamp"
ENV DEPLOY_CONTRACTS=true
ENV LOCAL_CONTRACTS=true
ENV REUSE_DATABASE=false
ENV NETWORK_NAME=spree
ENV KEEPER_RPC_HOST=localhost
ENV KEEPER_RPC_PORT=8545

RUN /nevermined-contracts/scripts/keeper_deploy_dockerfile.sh

ENTRYPOINT ["/nevermined-contracts/scripts/keeper_entrypoint_nodeploy.sh"]
