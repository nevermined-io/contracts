FROM node:16
LABEL maintainer="Nevermined <root@nevermined.io>"

RUN apt-get update -y && apt-get install -y musl psmisc

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn
RUN sh ./scripts/build-circuit.sh

RUN yarn clean
RUN yarn compile

ENTRYPOINT ["/nevermined-contracts/scripts/keeper.sh"]
