FROM alpine

# directories
RUN mkdir -p /ssl /out

# storage for signed certs
RUN touch /ssl/certindex

# current cert serial number
RUN echo "000a" > /ssl/serial

RUN apk --no-cache add openssl curl

# root certificate
RUN openssl req -newkey rsa:2048 -days 3650 -x509 -nodes \
  -out /ssl/ca.crt \
  -keyout /ssl/privkey.pem \
  -subj "/C=/ST=/L=/O=/CN=consul"

# ca config from http://russellsimpkins.blogspot.com/2015/10/consul-adding-tls-using-self-signed.html
# NOTE: authorityKeyIdentifier=keyid:always has been changed to authorityKeyIdentifier=keyid
# NOTE: _policy requirements other than commonName have been made optional
RUN echo $'                                                                                         \n\
[ ca ]                                                                                              \n\
default_ca = autopilotpattern                                                                       \n\
                                                                                                    \n\
[ crl_ext ]                                                                                         \n\
# issuerAltName=issuer:copy  #this would copy the issuer name to altname                            \n\
authorityKeyIdentifier=keyid                                                                        \n\
                                                                                                    \n\
[ autopilotpattern ]                                                                                \n\
new_certs_dir = /tmp                                                                                \n\
unique_subject = no                                                                                 \n\
certificate = /ssl/ca.crt                                                                         \n\
database = /ssl/certindex                                                                           \n\
private_key = /ssl/privkey.pem                                                                      \n\
serial = /ssl/serial                                                                                \n\
default_days = 365                                                                                  \n\
default_md = sha1                                                                                   \n\
policy = autopilotpattern_policy                                                                    \n\
x509_extensions = autopilotpattern_extensions                                                       \n\
                                                                                                    \n\
[ autopilotpattern_policy ]                                                                         \n\
commonName = supplied                                                                               \n\
stateOrProvinceName = optional                                                                      \n\
countryName = optional                                                                              \n\
emailAddress = optional                                                                             \n\
organizationName = optional                                                                         \n\
organizationalUnitName = optional                                                                   \n\
                                                                                                    \n\
[ autopilotpattern_extensions ]                                                                     \n\
basicConstraints = CA:false                                                                         \n\
subjectKeyIdentifier = hash                                                                         \n\
authorityKeyIdentifier = keyid                                                                      \n\
keyUsage = digitalSignature,keyEncipherment                                                         \n\
extendedKeyUsage = serverAuth,clientAuth                                                            \n\
crlDistributionPoints = URI:http://path.to.crl/autopilotpattern.crl                                 \n\
' > /ssl/autopilotpattern.conf

RUN echo $'#!/bin/sh                                                                                                      \n\
[ $# != 2 ] && { echo "Usage: ./gen_cert.sh <consul-dc> <hostname>" ; exit 1 ; }                                          \n\
[ -d /out/$1 ] && { echo "Error: destination directory /out/$1 already exists!" ; exit 2 ; }                              \n\
                                                                                                                          \n\
mkdir /out/$1                                                                                                             \n\
                                                                                                                          \n\
openssl req -newkey rsa:1024 -nodes -out /out/$1/$1.csr -keyout /out/$1/$1.key -subj "/C=/ST=/L=/O=/CN=$2"                \n\
                                                                                                                          \n\
openssl ca -batch -config /ssl/autopilotpattern.conf -notext -in /out/$1/$1.csr -out /out/$1/$1.crt                       \n\
                                                                                                                          \n\
cp /ssl/ca.crt /out/$1/ca.crt                                                                                         \n\
echo $2 > /out/$1/hostname                                                                                                \n\
# verify "X509v3 Extended Key Usage" includes "TLS Web Server Authentication, TLS Web Client Authentication"              \n\
# openssl x509 -noout -text -in /out/server.crt                                                                           \n\
' > /ssl/gen_cert.sh && chmod +x /ssl/gen_cert.sh


# The Consul binary, used for generating a shared secret for encrypting gossip
ENV CONSUL_VERSION=1.0.0
RUN export CONSUL_CHECKSUM=585782e1fb25a2096e1776e2da206866b1d9e1f10b71317e682e03125f22f479 \
    && export archive=consul_${CONSUL_VERSION}_linux_amd64.zip \
    && curl -Lso /tmp/${archive} https://releases.hashicorp.com/consul/${CONSUL_VERSION}/${archive} \
    && echo "${CONSUL_CHECKSUM}  /tmp/${archive}" | sha256sum -c \
    && cd /bin \
    && unzip /tmp/${archive} \
    && chmod +x /bin/consul \
    && rm /tmp/${archive}

ENTRYPOINT ["/ssl/gen_cert.sh"]
