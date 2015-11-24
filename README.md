# Triton trusted Consul

[Consul](http://www.consul.io/) in Docker, designed for availability and durability.

## Prep your environment

1. [Get a Joyent account](https://my.joyent.com/landing/signup/) and [add your SSH key](https://docs.joyent.com/public-cloud/getting-started).
1. Install and the [Docker Engine](https://docs.docker.com/installation/mac/) (including `docker` and `docker-compose`) on your laptop or other environment, along with the [Joyent CloudAPI CLI tools](https://apidocs.joyent.com/cloudapi/#getting-started) (including the `smartdc` and `json` tools).
1. [Configure your Docker CLI and Compose for use with Joyent](https://docs.joyent.com/public-cloud/api-access/docker):

```
curl -O https://raw.githubusercontent.com/joyent/sdc-docker/master/tools/sdc-docker-setup.sh && chmod +x sdc-docker-setup.sh
 ./sdc-docker-setup.sh -k us-east-1.api.joyent.com <ACCOUNT> ~/.ssh/<PRIVATE_KEY_FILE>
```

## Start a trusted Consul raft

1. [Clone](https://github.com/misterbisson/triton-consul) or [download](https://github.com/misterbisson/triton-consul/archive/master.zip) this repo
1. `cd` into the cloned or downloaded directory
1. Execute `bash start.sh` to start everything up
1. The Consul dashboard should automatically open in your browser, or follow the links output by the `start.sh` script

## Use this in your own composition

Detailed example to come....

## How it works

This demo first starts up a bootstrap node that starts the raft but expects 2 additional nodes before the raft is healthy. Once this node is up and its IP address is obtained, the rest of the nodes are started and joined to the bootstrap IP address (the value is passed in the `BOOTSTRAP_HOST` environment variable).

If a raft instance fails, the data is preserved among the other instances and the overall availability of the service is preserved because any single instance can authoritatively answer for all instances. Applications that depend on the Consul service should re-try failed requests until they get a response.

Any new raft instances need to be started with a bootstrap IP address, but after the initial cluster is created, the `BOOTSTRAP_HOST` IP address can be any host currently in the raft. This means there is no dependency on the first node after the cluster has been formed.

## Triton-specific availability advantages

Some details about how Docker containers work on Triton have specific bearing on the durability and availability of this service:

1. Docker containers are first-order objects on Triton. They run on bare metal, and their overall availability is similar or better than what you expect of a virtual machine in other environments.
1. Docker containers on Triton preserve their IP and any data on disk when they reboot.
1. Linked containers in Docker Compose on Triton are actually distributed across multiple unique physical nodes for maximum availability in the case of  node failures.

# Credit where it's due

This project builds on the fine examples set by [Jeff Lindsay](https://github.com/progrium)'s ([Glider Labs](https://github.com/gliderlabs)) [Consul in Docker](https://github.com/gliderlabs/docker-consul/tree/legacy) work. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [consul.io](https://www.consul.io).
