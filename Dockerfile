FROM alpine:3.3
MAINTAINER 	Casey Bisson <casey.bisson@gmail.com>

ENV CONSUL_VERSION=0.6.4
ENV CONTAINERBUDDY_VERSION=1.3.0

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

# get Containerbuddy release
RUN mkdir -p /opt/containerbuddy && \
    curl -Lo /tmp/containerbuddy.tar.gz https://github.com/joyent/containerbuddy/releases/download/${CONTAINERBUDDY_VERSION}/containerbuddy-${CONTAINERBUDDY_VERSION}.tar.gz && \
    tar xzf /tmp/containerbuddy.tar.gz -C /opt/containerbuddy/ && \
    rm /tmp/containerbuddy.tar.gz
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
