FROM alpine:3.3
MAINTAINER Casey Bisson <casey.bisson@gmail.com>

ENV CONSUL_VERSION=0.6.4
ENV CONTAINERPILOT_VERSION=2.0.0

# Alpine packages
RUN apk --no-cache \
    add \
        curl \
        bash \
        ca-certificates

# The Consul binary
RUN curl -Lo /tmp/consul.zip https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip && \
    cd /bin && \
    unzip /tmp/consul.zip && \
    chmod +x /bin/consul && \
    rm /tmp/consul.zip

# The Consul web UI
RUN curl -Lo /tmp/webui.zip https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_web_ui.zip && \
    mkdir /ui && \
    cd /ui && \
    unzip /tmp/webui.zip && \
    rm /tmp/webui.zip

# get Containerpilot release
RUN mkdir -p /opt/containerpilot && \
    curl -Lo /tmp/containerpilot.tar.gz https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.tar.gz && \
    tar xzf /tmp/containerpilot.tar.gz -C /opt/containerpilot/ && \
    rm /tmp/containerpilot.tar.gz
COPY containerpilot.json /etc/

# Consul config
COPY ./config /config/
ONBUILD ADD ./config /config/

# copy bootstrap scripts
COPY ./bin/* /bin/

EXPOSE 8300 8301 8301/udp 8302 8302/udp 8400 8500 53 53/udp

# Put Consul data on a separate volume to avoid filesystem performance issues with Docker image layers
# Not necessary on Triton, but...
VOLUME ["/data"]

#ENV GOMAXPROCS 2
ENV SHELL /bin/bash
