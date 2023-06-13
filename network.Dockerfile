FROM node:16
LABEL maintainer="Nevermined <root@nevermined.io>"

RUN apt-get update -y && apt-get install -y musl psmisc

COPY . /nevermined-contracts
WORKDIR /nevermined-contracts

RUN yarn

EXPOSE 23451

ENTRYPOINT [ "/nevermined-contracts/server/entry.sh" ]

# docker run --rm -p 23451:23451 -v ~/never-contracts/artifacts:/root/.nevermined/nevermined-contracts/artifacts --add-host host.docker.internal:host-gateway --env WEB3_PROVIDER_URL=http://host.docker.internal:8545 -ti mrsmkl/frost