FROM alpine:3.3

# Alpine packages
RUN apk --no-cache \
    add \
        curl \
        bash \
        ca-certificates

# The Consul binary
ENV CONSUL_VERSION=0.6.4
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

# Add Containerpilot and set its configuration
ENV CONTAINERPILOT_VERSION 2.3.0
ENV CONTAINERPILOT file:///etc/containerpilot.json

RUN export CONTAINERPILOT_CHECKSUM=ec9dbedaca9f4a7a50762f50768cbc42879c7208 \
    && curl -Lso /tmp/containerpilot.tar.gz \
         "https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VERSION}/containerpilot-${CONTAINERPILOT_VERSION}.tar.gz" \
    && echo "${CONTAINERPILOT_CHECKSUM}  /tmp/containerpilot.tar.gz" | sha1sum -c \
    && tar zxf /tmp/containerpilot.tar.gz -C /usr/local/bin \
    && rm /tmp/containerpilot.tar.gz

# Consul config
COPY etc/containerpilot.json etc/
COPY etc/consul.json etc/consul/

# copy bootstrap scripts
COPY bin/* /usr/local/bin/

# Put Consul data on a separate volume to avoid filesystem performance issues
# with Docker image layers. Not necessary on Triton, but...
VOLUME ["/data"]

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 8300 8301 8301/udp 8302 8302/udp 8400 8500 53 53/udp

#ENV GOMAXPROCS 2
ENV SHELL /bin/bash
