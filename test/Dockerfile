# NOTE: this Dockerfile needs to be run from one-level up so that
# we get the examples docker-compose.yml files. Use 'make build/tester'
# in the makefile at the root of this repo and everything will work

FROM alpine:3.6

RUN apk update \
    && apk add nodejs nodejs-npm python3 openssl bash curl docker
RUN npm install -g triton json

# the Compose package in the public releases doesn't work on Alpine
RUN pip3 install docker-compose==1.10.0

# install specific version of Docker and Compose client
COPY test/triton-docker-cli/triton-docker /usr/local/bin/triton-docker
RUN sed -i 's/1.9.0/1.10.0/' /usr/local/bin/triton-docker \
    && ln -s /usr/local/bin/triton-docker /usr/local/bin/triton-compose \
    && ln -s /usr/local/bin/triton-docker /usr/local/bin/triton-docker-install \
    && /usr/local/bin/triton-docker-install \
    && rm /usr/local/bin/triton-compose-helper \
    && ln -s /usr/bin/docker-compose /usr/local/bin/triton-compose-helper


# install test targets
COPY examples/compose/docker-compose.yml /src/local-compose.yml
COPY examples/triton/docker-compose.yml /src/docker-compose.yml

# install test code
COPY test/triton.sh /src/triton.sh
COPY test/compose.sh /src/compose.sh
COPY examples/triton/setup.sh /src/setup.sh
