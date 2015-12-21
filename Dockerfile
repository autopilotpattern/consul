FROM alpine:3.2
MAINTAINER 	Casey Bisson <casey.bisson@gmail.com>

# Alpine packages
# Note: glibc is required because the Consul binary we're using is built against it
RUN apk --update \
    add \
        curl \
        bash \
        ca-certificates && \
    curl -Ls https://circle-artifacts.com/gh/andyshinn/alpine-pkg-glibc/6/artifacts/0/home/ubuntu/alpine-pkg-glibc/packages/x86_64/glibc-2.21-r2.apk > /tmp/glibc-2.21-r2.apk && \
    apk add --allow-untrusted /tmp/glibc-2.21-r2.apk && \
    rm -rf /tmp/glibc-2.21-r2.apk /var/cache/apk/*

# The Consul binary
ADD https://releases.hashicorp.com/consul/0.6.0/consul_0.6.0_linux_amd64.zip /tmp/consul.zip
RUN cd /bin && \
    unzip /tmp/consul.zip && \
    chmod +x /bin/consul && \
    rm /tmp/consul.zip

# The Consul web UI
ADD https://releases.hashicorp.com/consul/0.6.0/consul_0.6.0_web_ui.zip /tmp/webui.zip
RUN mkdir /ui && \
    cd /ui && \
    unzip /tmp/webui.zip && \
    rm /tmp/webui.zip

# get Containerbuddy release
RUN export CB=containerbuddy-0.0.5-alpha &&\
    mkdir -p /opt/containerbuddy && \
    curl -Lo /tmp/${CB}.tar.gz \
    https://github.com/joyent/containerbuddy/releases/download/0.0.5/containerbuddy-0.0.5.tar.gz && \
    tar xzf /tmp/${CB}.tar.gz -C /tmp && \
    rm /tmp/${CB}.tar.gz && \
    mv /tmp/containerbuddy /opt/containerbuddy/
COPY containerbuddy.json /etc/

# Consul config
COPY ./config /config/
ONBUILD ADD ./config /config/

# copy bootstrap scripts
COPY ./bin/* /bin/

EXPOSE 8300 8301 8301/udp 8302 8302/udp 8400 8500 53 53/udp

# Put Consul data on a separate volume to avoid filesystem performance issues with Docker image layers
# Not necessary on Triton, but...
VOLUME ["/data"]

ENV GOMAXPROCS 2
ENV SHELL /bin/bash
