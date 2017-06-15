FROM alpine:3.5

# Alpine packages
RUN apk --no-cache \
    add \
        curl \
        bash \
        ca-certificates

# The Consul binary
ENV CONSUL_VERSION=0.7.3
RUN export CONSUL_CHECKSUM=901a3796b645c3ce3853d5160080217a10ad8d9bd8356d0b73fcd6bc078b7f82 \
    && export archive=consul_${CONSUL_VERSION}_linux_amd64.zip \
    && curl -Lso /tmp/${archive} https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${archive} \
    && echo "${CONSUL_CHECKSUM}  /tmp/${archive}" | sha256sum -c \
    && cd /bin \
    && unzip /tmp/${archive} \
    && chmod +x /bin/consul \
    && rm /tmp/${archive}

# The Consul web UI
RUN export CONSUL_UI_CHECKSUM=52b1bb09b38eec522f6ecc0b9bf686745bbdc9d845be02bd37bf4b835b0a736e \
    && export archive=consul_${CONSUL_VERSION}_web_ui.zip \
    && curl -Lso /tmp/${archive} https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${archive} \
    && echo "${CONSUL_UI_CHECKSUM}  /tmp/${archive}" | sha256sum -c \
    && mkdir /ui \
    && cd /ui \
    && unzip /tmp/${archive} \
    && rm /tmp/${archive}

# Add Containerpilot and set its configuration
ENV CONTAINERPILOT_VER 3.0.0
ENV CONTAINERPILOT /etc/containerpilot.json5

RUN export CONTAINERPILOT_CHECKSUM=6da4a4ab3dd92d8fd009cdb81a4d4002a90c8b7c \
    && curl -Lso /tmp/containerpilot.tar.gz \
         "https://github.com/joyent/containerpilot/releases/download/${CONTAINERPILOT_VER}/containerpilot-${CONTAINERPILOT_VER}.tar.gz" \
    && echo "${CONTAINERPILOT_CHECKSUM}  /tmp/containerpilot.tar.gz" | sha1sum -c \
    && tar zxf /tmp/containerpilot.tar.gz -C /usr/local/bin \
    && rm /tmp/containerpilot.tar.gz

# configuration files and bootstrap scripts
COPY etc/containerpilot.json5 etc/
COPY etc/consul.json etc/consul/
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
