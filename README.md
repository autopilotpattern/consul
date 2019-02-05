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

Check that everything is configured correctly by changing to the `examples/triton` directory and executing `./setup.sh`. This will check that your environment is setup correctly and will create an `_env` file that includes injecting an environment variable for a service name for Consul in Triton CNS. We'll use this CNS name to bootstrap the cluster.

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

### Run it with more than one datacenter!

Within the `examples/triton-multi-dc` directory, execute `./setup-multi-dc.sh`, providing as arguments Triton profiles which belong to the desired data centers.

Since interacting with multiple data centers requires switching between Triton profiles it's easier to perform the following steps in separate terminals. It is possible to perform all the steps for a single data center and then change profiles. Additionally, setting `COMPOSE_PROJECT_NAME` to match the profile or data center will help distinguish nodes in Triton Portal and the `triton instance ls` listing.

One `_env` and one `docker-compose-<PROFILE>.yml` should be generated for each profile. Execute the following commands, once for each profile/datacenter, within `examples/triton-multi-dc`:

```
$ eval "$(TRITON_PROFILE=<PROFILE> triton env -d)"

# The following helps when executing docker-compose multiple times. Alternatively, pass the -f flag to each invocation of docker-compose.
$ export COMPOSE_FILE=docker-compose-<PROFILE>.yml

# The following is not strictly necessary but helps to discern between clusters. Alternatively, pass the -p flag to each invocation of docker-compose.
$ export COMPOSE_PROJECT_NAME=<PROFILE>

$ docker-compose up -d
Creating <PROFILE>_consul_1 ... done

$ docker-compose scale consul=3
```

Note: the `cns.joyent.com` hostnames cannot be resolved from outside the datacenters. Change `cns.joyent.com` to `triton.zone` to access the web UI.

## Environment Variables

- `CONSUL_DEV`: Enable development mode, allowing a node to self-elect as a cluster leader. Consul flag: [`-dev`](https://www.consul.io/docs/agent/options.html#_dev).
    - The following errors will occur if `CONSUL_DEV` is omitted and not enough Consul instances are deployed:
    ```
    [ERR] agent: failed to sync remote state: No cluster leader
    [ERR] agent: failed to sync changes: No cluster leader
    [ERR] agent: Coordinate update error: No cluster leader
    ```
- `CONSUL_DATACENTER_NAME`: Explicitly set the name of the data center in which Consul is running. Consul flag: [`-datacenter`](https://www.consul.io/docs/agent/options.html#datacenter).
    - If this variable is specified it will be used as-is.
    - If not specified, automatic detection of the datacenter will be attempted. See [issue #23](https://github.com/autopilotpattern/consul/issues/23) for more details.
    - Consul's default of "dc1" will be used if none of the above apply.

- `CONSUL_BIND_ADDR`: Explicitly set the corresponding Consul configuration. This value will be set to `0.0.0.0` if `CONSUL_BIND_ADDR` is not specified and `CONSUL_RETRY_JOIN_WAN` is provided. Be aware of the security implications of binding the server to a public address and consider setting up encryption or using a VPN to isolate WAN traffic from the public internet.
- `CONSUL_SERF_LAN_BIND`: Explicitly set the corresponding Consul configuration. This value will be set to the server's private address automatically if not specified. Consul flag: [`-serf-lan-bind`](https://www.consul.io/docs/agent/options.html#serf_lan_bind).
- `CONSUL_SERF_WAN_BIND`: Explicitly set the corresponding Consul configuration. This value will be set to the server's public address automatically if not specified. Consul flag: [`-serf-wan-bind`](https://www.consul.io/docs/agent/options.html#serf_wan_bind).
- `CONSUL_ADVERTISE_ADDR`: Explicitly set the corresponding Consul configuration. This value will be set to the server's private address automatically if not specified. Consul flag: [`-advertise-addr`](https://www.consul.io/docs/agent/options.html#advertise_addr).
- `CONSUL_ADVERTISE_ADDR_WAN`: Explicitly set the corresponding Consul configuration. This value will be set to the server's public address automatically if not specified. Consul flag: [`-advertise-addr-wan`](https://www.consul.io/docs/agent/options.html#advertise_addr_wan).

- `CONSUL_RETRY_JOIN_WAN`: sets the remote datacenter addresses to join. Must be a valid HCL list (i.e. comma-separated quoted addresses). Consul flag: [`-retry-join-wan`](https://www.consul.io/docs/agent/options.html#retry_join_wan).
    - The following error will occur if `CONSUL_RETRY_JOIN_WAN` is provided but improperly formatted:
    ```
    ==> Error parsing /etc/consul/consul.hcl: ... unexpected token while parsing list: IDENT
    ```
    - Gossip over the WAN requires the following ports to be accessible between data centers, make sure that adequate firewall rules have been established for the following ports (this should happen automatically when using docker-compose with Triton):
      - `8300`: Server RPC port (TCP)
      - `8302`: Serf WAN gossip port (TCP + UDP)

- `CONSUL_TLS_PATH`: Specifies the location of a directory which will contain the TLS key file, certificate, and root certificate. See the section on [securing Consul](#consul-encryption) for more details.

- `CONSUL_ENCRYPT`: Secret key used for encrypting gossip. Consul flag: [`-encrypt`](https://www.consul.io/docs/agent/options.html#_encrypt). See the section on [securing Consul](#consul-encryption) for more details.

## Using this in your own composition

There are two ways to run Consul and both come into play when deploying ContainerPilot, a cluster of Consul servers and individual Consul client agents.

### Servers

The Consul container created by this project provides a scalable Consul cluster. Use this cluster with any project that requires Consul and not just ContainerPilot/Autopilot applications.

The following Consul service definition can be dropped into any Docker Compose file to run a Consul cluster alongside other application containers.

```yaml
version: '2.1'

services:

  consul:
    image: autopilotpattern/consul:1.0.0r43
    restart: always
    mem_limit: 128m
    ports:
      - 8500
    environment:
      - CONSUL=consul
      - LOG_LEVEL=info
    command: >
      /usr/local/bin/containerpilot
```

In our experience, including a Consul cluster within a project's `docker-compose.yml` can help developers understand and test how a service should be discovered and registered within a wider infrastructure context.

### Clients

ContainerPilot utilizes Consul's [HTTP Agent API](https://www.consul.io/api/agent.html) for a handful of endpoints, such as `UpdateTTL`, `CheckRegister`, `ServiceRegister` and `ServiceDeregister`. Connecting ContainerPilot to Consul can be achieved by running Consul as a client to a cluster (mentioned above). It's easy to run this Consul client agent from ContainerPilot itself.

The following snippet demonstrates how to achieve running Consul inside a container and connecting it to ContainerPilot by configuring a `consul-agent` job.

```json5
{
  consul: 'localhost:8500',
  jobs: [
    {
      name: "consul-agent",
      restarts: "unlimited",
      exec: [
        "/usr/bin/consul", "agent",
          "-data-dir=/data",
          "-log-level=err",
          "-rejoin",
          "-retry-join", '{{ .CONSUL | default "consul" }}',
          "-retry-max", "10",
          "-retry-interval", "10s",
      ],
      health: {
        exec: "curl -so /dev/null http://localhost:8500",
        interval: 10,
        ttl: 25,
      }
    }
  ]
}
```

Many application setups in the Autopilot Pattern library include a Consul agent process within each container to handle connecting ContainerPilot itself to a cluster of Consul servers. This helps performance of Consul features at the cost of more clients connected to the cluster.

A more detailed example of a ContainerPilot configuration that uses a Consul agent co-process can be found in [autopilotpattern/nginx](https://github.com/autopilotpattern/nginx).

## Triton-specific availability advantages

Some details about how Docker containers work on Triton have specific bearing on the durability and availability of this service:

1. Docker containers are first-order objects on Triton. They run on bare metal, and their overall availability is similar or better than what you expect of a virtual machine in other environments.
1. Docker containers on Triton preserve their IP and any data on disk when they reboot.
1. Linked containers in Docker Compose on Triton are distributed across multiple unique physical nodes for maximum availability in the case of  node failures.

## Consul encryption

Consul supports TLS encryption for RPC and symmetric pre-shared key encryption for its gossip protocol. Deploying these features requires managing these secrets, and a demonstration of how to do so can be found in the [Vault example](https://github.com/autopilotpattern/vault).

### Configuration

The `CONSUL_TLS_PATH` environment variable will be checked on startup and is used to indicate that TLS should be configured. If it is defined the container will await the creation of the directory specified in `CONSUL_TLS_PATH` and expect the directory to contain a CA certificate along with a datacenter-specific certificate and key. These files will be used to configure `ca_cert`, `cert_file` and `key_file` respectively in Consul, in addition to enabling both `verify_outgoing` and `verify_incoming`. The secret key used for gossip traffic can be provided directly as the environment variable `CONSUL_ENCRYPT`.

The `./setup.sh` and `./setup-multi-dc.sh` scripts both accept `-t/--tls-path` and `-g/--gossip-path` parameters to set `CONSUL_TLS_PATH` and `CONSUL_ENCRYPT` environment variables respectively. Note that `--tls-path` only specifies _where_ the key material will be injected. Deployed containers will remain idle until certificates have been installed by `./setup-encryption.sh upload`

### Generating certificates

In order to simplify certificate generation a `Dockerfile` can be found within the `ca` directory which creates a Certificate Authority on build. Use `./setup-encryption.sh build -i <image-name>` to build the container. This same image name can then be used with `./setup-encryption.sh generate -i <image-name> -d <datacenter-name> -g <gossip-filename>` to generate certificates.

### Installing certificates

When `CONSUL_TLS_PATH` is specified, the `preStart` ContainerPilot job awaits the creation of the relevant certificates and key (i.e. `CONSUL_CACERT`, `CONSUL_CLIENT_CERT`, `CONSUL_CLIENT_KEY`) and uses the [ContainerPilot Control plane](https://www.joyent.com/containerpilot/docs/configuration/control-plane) from within the job to `-putenv` and `-reload` ContainerPilot itself. Without the `-putenv` calls to set the certificates and key, the `preStart` job would see `CONSUL_TLS_PATH` and attempt to restart ContainerPilot indefinitely.

Certificates and the private key can be installed in running containers with `./setup-encryption.sh upload -d <datacenter-name> -t <CONSUL_TLS_PATH>`. Note that `-d` is only used to select the directory containing the key material, you must still run `eval "$(triton env -d)"` with the relevant datacenter's profile in order to target the correct docker endpoint.

The `upload` command will assume the default `docker-compose` file (`./docker-compose.yml`) and project name (the current working directory), reading `COMPOSE_FILE` and `COMPOSE_PROJECT_NAME` if they are defined, but can be overriden with `-f` and `-p` in the same way as `docker-compose` itself.

### Encrypting gossip

The `CONSUL_ENCRYPT` parameter can be passed to encrypt gossip traffic. Use `./setup-encryption.sh generate -g <filename>` to generate a file in the `secrets` directory with the provided name. For local deployments, simply copy the contents of the generated file as an environment variable in `examples/compose/docker-compose.yml`. For Triton deployments, the setup scripts accept a `-g` parameter to specify a relative path to a gossip file (e.g. `examples/triton/setup.sh -g ../../secrets/gossip`) and will inject the contents of the gossip key file as `CONSUL_ENCRYPT` in the relevant `_env` file.

### How do I know if it's working?

Assuming you've spun up `examples/compose/docker-compose.yml` after generating a certificate for the "dc1" datacenter (which would imply the `secrets/dc1` directory was generated) then you'll notice commands fail with odd HTTP responses unless the correct certificates and key are supplied:

```
$ docker-compose exec consul consul info -client-cert=/ssl/dc1.crt -client-key=/ssl/dc1.key -ca-file=/ssl/ca.crt
Error querying agent: Get http://127.0.0.1:8500/v1/agent/self: net/http: HTTP/1.x transport connection broken: malformed HTTP response "\x15\x03\x01\x00\x02\x02"

$ docker-compose exec consul consul info -client-cert=/ssl/dc1.crt -client-key=/ssl/dc1.key -http-addr=https://consul:8500
Error querying agent: Get https://consul:8500/v1/agent/self: x509: certificate signed by unknown authority

$ docker-compose exec consul consul info -client-cert=/ssl/dc1.crt -ca-file=/ssl/ca.crt -http-addr=https://consul:8500
Error querying agent: Get https://consul:8500/v1/agent/self: remote error: tls: bad certificate

# with everything in place
$ docker-compose exec consul consul members -client-cert=/ssl/dc1.crt -client-key=/ssl/dc1.key -ca-file=/ssl/ca.crt -http-addr=https://consul:8500
Node          Address          Status  Type    Build  Protocol  DC   Segment
01e297f34346  172.23.0.2:8301  alive   server  1.0.0  2         dc1  <all>
```

## Testing

The `tests/` directory includes integration tests for both the Triton and Compose example stacks described above. Build the test runner by making sure you've pulled down the submodule with `git submodule update --init` and then `make build/tester`.

Running `make test/triton` will run the tests in a container locally but targeting Triton Cloud. To run those tests you'll need a Triton Cloud account with your Triton command line profile set up. The test rig will use the value of the `TRITON_PROFILE` environment variable to determine what data center to target. The tests use your own credentials mounted from your Docker host (your laptop, for example), so if you have a passphrase on your ssh key you'll need to add `-it` to the arguments of the `test/triton` Make target.

## Credit where it's due

This project builds on the fine examples set by [Jeff Lindsay](https://github.com/progrium)'s ([Glider Labs](https://github.com/gliderlabs)) [Consul in Docker](https://github.com/gliderlabs/docker-consul/tree/legacy) work. It also, obviously, wouldn't be possible without the outstanding work of the [Hashicorp team](https://hashicorp.com) that made [consul.io](https://www.consul.io).
