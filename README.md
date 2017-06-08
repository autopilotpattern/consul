# Consul with the Autopilot Pattern

[Consul](http://www.consul.io/) in Docker, designed to be self-operating according to the autopilot pattern. This application demonstrates support for configuring the Consul raft so it can be used as a highly-available discovery catalog for other applications using the Autopilot pattern.

[![DockerPulls](https://img.shields.io/docker/pulls/autopilotpattern/consul.svg)](https://registry.hub.docker.com/u/autopilotpattern/consul/)
[![DockerStars](https://img.shields.io/docker/stars/autopilotpattern/consul.svg)](https://registry.hub.docker.com/u/autopilotpattern/consul/)

## Using Consul with ContainerPilot

This design starts up all Consul instances with the `-bootstrap-expect` flag. This option tells Consul how many nodes we expect and automatically bootstraps when that many servers are available. We still need to tell Consul how to find the other nodes, and this is where [Triton Container Name Service (CNS)](https://docs.joyent.com/public-cloud/network/cns) and [ContainerPilot](https://joyent.com/containerpilot) come into play.

The ContainerPilot configuration has a management script that is run on each health check interval. This management script runs `consul info` and gets the number of peers for this node. If the number of peers is not equal to 2 (there are 3 nodes in total but a node isn't its own peer), then the script will attempt to find another node via `consul join`. This command will use the Triton CNS name for the Consul service. Because each node is automatically added to the A Record for the CNS name when it starts, the nodes will all eventually find at least one other node and bootstrap the Consul raft.

When run locally for testing, we don't have access to Triton CNS. The `local-compose.yml` file uses the v2 Compose API, which automatically creates a user-defined network and allows us to use Docker DNS for the service.

## Run it!

1. [Get a Joyent account](https://my.joyent.com/landing/signup/) and [add your SSH key](https://docs.joyent.com/public-cloud/getting-started).
1. Install the [Docker Toolbox](https://docs.docker.com/installation/mac/) (including `docker` and `docker-compose`) on your laptop or other environment, as well as the [Joyent Triton CLI](https://www.joyent.com/blog/introducing-the-triton-command-line-tool) (`triton` replaces our old `sdc-*` CLI tools).

Check that everything is configured correctly by running `./setup.sh`. This will check that your environment is setup correctly and will create an `_env` file that includes injecting an environment variable for a service name for Consul in Triton CNS. We'll use this CNS name to bootstrap the cluster.

```bash
$ docker-compose up -d
Creating consul_consul_1

$ docker-compose scale consul=3
Creating and starting consul_consul_2 ...
Creating and starting consul_consul_3 ...

$ docker-compose ps
Name                        Command                 State       Ports
--------------------------------------------------------------------------------
consul_consul_1   /usr/local/bin/containerpilot...   Up   53/tcp, 53/udp,
                                                          8300/tcp, 8301/tcp,
                                                          8301/udp, 8302/tcp,
                                                          8302/udp, 8400/tcp,
                                                          0.0.0.0:8500->8500/tcp
consul_consul_2   /usr/local/bin/containerpilot...   Up   53/tcp, 53/udp,
                                                          8300/tcp, 8301/tcp,
                                                          8301/udp, 8302/tcp,
                                                          8302/udp, 8400/tcp,
                                                          0.0.0.0:8500->8500/tcp
consul_consul_3   /usr/local/bin/containerpilot...   Up   53/tcp, 53/udp,
                                                          8300/tcp, 8301/tcp,
                                                          8301/udp, 8302/tcp,
                                                          8302/udp, 8400/tcp,
                                                          0.0.0.0:8500->8500/tcp

$ docker exec -it consul_consul_3 consul info | grep num_peers
    num_peers = 2

```


## Using this in your own composition

The Consul service definition can be dropped into any Docker Compose file. Set the ContainerPilot configuration for each other service to use the `CONSUL` environment variable as its Consul target and populate this with the CNS name. On Triton, you should consider using a Consul agent in the application container as a `coprocess`, and point this agent to the `CONSUL` environment variable. The relevant section of the ContainerPilot configuration might look like this:

```json
{
  "consul": "localhost:8500",
  "coprocesses": [
    {
      "command": ["/usr/local/bin/consul", "agent",
                  "-data-dir=/data",
                  "-config-dir=/config",
                  "-rejoin",
                  "-retry-join", "{{ .CONSUL }}",
                  "-retry-max", "10",
                  "-retry-interval", "10s"],
      "restarts": "unlimited"
    }]
  }
}
```

A more detailed example of a ContainerPilot configuration that uses a Consul agent co-process can be found in [autopilotpattern/nginx](https://github.com/autopilotpattern/nginx).

## Triton-specific availability advantages

Some details about how Docker containers work on Triton have specific bearing on the durability and availability of this service:

1. Docker containers are first-order objects on Triton. They run on bare metal, and their overall availability is similar or better than what you expect of a virtual machine in other environments.
1. Docker containers on Triton preserve their IP and any data on disk when they reboot.
1. Linked containers in Docker Compose on Triton are distributed across multiple unique physical nodes for maximum availability in the case of  node failures.

## Consul encryption

Consul supports TLS encryption for RPC and symmetric pre-shared key encryption for its gossip protocol. Deploying these features requires managing these secrets, and a demonstration of how to do so can be found in the [Vault example](https://github.com/autopilotpattern/vault).

### Testing

The `tests/` directory includes integration tests for both the Triton and Compose example stacks described above. Build the test runner by making sure you've pulled down the submodule with `git submodule update --init` and then `make build/tester`.

Running `make test/triton` will run the tests in a container locally but targeting Triton Cloud. To run those tests you'll need a Triton Cloud account with your Triton command line profile set up. The test rig will use the value of the `TRITON_PROFILE` environment variable to determine what data center to target. The tests use your own credentials mounted from your Docker host (your laptop, for example), so if you have a passphrase on your ssh key you'll need to add `-it` to the arguments of the `test/triton` Make target.

## Credit where it's due

This project builds on the fine examples set by [Jeff Lindsay](https://github.com/progrium)'s ([Glider Labs](https://github.com/gliderlabs)) [Consul in Docker](https://github.com/gliderlabs/docker-consul/tree/legacy) work. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [consul.io](https://www.consul.io).
