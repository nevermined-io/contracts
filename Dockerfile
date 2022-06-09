FROM node:14-alpine
LABEL maintainer="Nevermined <root@nevermined.io>"

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

RUN yarn clean
RUN yarn compile

ENTRYPOINT ["/nevermined-contracts/scripts/keeper.sh"]
