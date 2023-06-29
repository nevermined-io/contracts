FROM node:16
LABEL maintainer="Nevermined <root@nevermined.io>"

RUN apt-get update -y && apt-get install -y musl psmisc

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn

EXPOSE 23451

ENTRYPOINT [ "/nevermined-contracts/server/entry.sh" ]
