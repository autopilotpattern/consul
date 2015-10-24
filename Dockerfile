FROM alpine:3.2
MAINTAINER 	Casey Bisson <casey.bisson@gmail.com>

RUN apk --update add curl bash ca-certificates && \
    curl -Ls https://circle-artifacts.com/gh/andyshinn/alpine-pkg-glibc/6/artifacts/0/home/ubuntu/alpine-pkg-glibc/packages/x86_64/glibc-2.21-r2.apk > /tmp/glibc-2.21-r2.apk && \
    apk add --allow-untrusted /tmp/glibc-2.21-r2.apk && \
    rm -rf /tmp/glibc-2.21-r2.apk /var/cache/apk/*

ADD https://dl.bintray.com/mitchellh/consul/0.5.2_linux_amd64.zip /tmp/consul.zip
RUN cd /bin && \
    unzip /tmp/consul.zip && \
    chmod +x /bin/consul && \
    rm /tmp/consul.zip

ADD https://dl.bintray.com/mitchellh/consul/0.5.2_web_ui.zip /tmp/webui.zip
RUN mkdir /ui && \
    cd /ui && \
    unzip /tmp/webui.zip && \
    rm /tmp/webui.zip && \
    mv dist/* . && \
    rm -rf dist

COPY ./config /config/
ONBUILD ADD ./config /config/

COPY ./bin/triton-start /bin/triton-start

EXPOSE 8300 8301 8301/udp 8302 8302/udp 8400 8500 53 53/udp
VOLUME ["/data"]

ENV SHELL /bin/bash

ENTRYPOINT ["/bin/triton-start"]
CMD []
