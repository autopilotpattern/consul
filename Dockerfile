FROM alpine:3.6

# Alpine packages
RUN apk --no-cache \
    add \
        curl \
        bash \
        ca-certificates

# The Consul binary
ENV CONSUL_VERSION=1.0.0
RUN export CONSUL_CHECKSUM=585782e1fb25a2096e1776e2da206866b1d9e1f10b71317e682e03125f22f479 \
    && export archive=consul_${CONSUL_VERSION}_linux_amd64.zip \
    && curl -Lso /tmp/${archive} https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${archive} \
    && echo "${CONSUL_CHECKSUM}  /tmp/${archive}" | sha256sum -c \
    && cd /bin \
    && unzip /tmp/${archive} \
    && chmod +x /bin/consul \
    && rm /tmp/${archive}

# Add Containerpilot and set its configuration
ENV CONTAINERPILOT_VER=3.6.0
ENV CONTAINERPILOT=/etc/containerpilot.json5
RUN export CONTAINERPILOT_CHECKSUM=1248784ff475e6fda69ebf7a2136adbfb902f74b \
    && curl -Lso /tmp/containerpilot.tar.gz \
         "https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VER}/containerpilot-${CONTAINERPILOT_VER}.tar.gz" \
    && echo "${CONTAINERPILOT_CHECKSUM}  /tmp/containerpilot.tar.gz" | sha1sum -c \
    && tar zxf /tmp/containerpilot.tar.gz -C /usr/local/bin \
    && rm /tmp/containerpilot.tar.gz

# configuration files and bootstrap scripts
COPY etc/containerpilot.json5 /etc/
COPY etc/consul.hcl /etc/consul/
COPY bin/* /usr/local/bin/

# Put Consul data on a separate volume (via etc/consul.hcl) to avoid filesystem
# performance issues with Docker image layers. Not necessary on Triton, but...
VOLUME ["/data"]

# We don't need to expose these ports in order for other containers on Triton
# to reach this container in the default networking environment, but if we
# leave this here then we get the ports as well-known environment variables
# for purposes of linking.
EXPOSE 8300 8301 8301/udp 8302 8302/udp 8400 8500 53 53/udp

#ENV GOMAXPROCS 2
ENV SHELL /bin/bash
