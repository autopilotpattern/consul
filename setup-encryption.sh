#!/bin/bash
set -e -o pipefail

function help() {
  echo "in help"
  cat << 'EOF'
Usage: ./setup-encryption.sh [ build | generate | upload | help ] [options]

---

setup-encryption.sh build:
  Builds a container that boostraps a Certificate Authority and can be
  invoked to generate certficates. This container should only be built
  --image-name/-i <val>:
    The image name to tag when building the bootstrap CA container.

setup-encryption.sh generate:
  Invokes the bootstrap Certificate Authority container to generate a
  new certificate to be used when encrypting RPC traffic.
  --image-name/-i <val>:
    The image name to use when generating the certificate or key. Should
    be the same as the argument specified to `build`.
  --datacenter-name/-d <val>:
    The name of the Consul datacenter in which the certificate will be installed.
    Generates a directory with the same name as the provided argument in the `secrets` directory
    containing root and datacenter certificates in addition to a datacenter-specific key.
    If this is omitted no certificate will be generated.
  --hostname/-h <val>:
    Hostname under which Consul will be deployed to be included in the Common Name field of the
    certificate. Defaults to "consul" is only appropriate in local deployments or deployments where
    Consul will only be accessed from within a docker-compose network. Alternatively, specify
    `--triton-profile/-t` to generated the name using Triton CNS.
  --triton-profile/-t <val>:
    Name of triton profile for\ automatic hostname configuration based on Triton CNS.
  --gossip/-g <val>:
    Name of file to generate the Consul gossip shared key. Will be placed in the `secrets`
    directory. If this is omitted no gossip key will be generated.

setup-encryption.sh upload:
  Uploads tokens into remote Consul instaces that are awaiting TLS files.
  --compose-file/-f <val>:
    Path to docker-compose.yml file. Passed to docker-compose -f argument.
  --compose-project-name/-p <val>:
    Project name used by docker-compose. Passed to docker-compose -p argument.
  --service-name/-s <val>:
    Name of docker-compose service to filter on when querying container IDs. Defaults to "consul"
  --datacenter-name/-d <val>:
    The name of the Consul datacenter passed to `generate`. Should reference
    a directory in the `secrets` directory containing:

      ca.crt
      \$DATACENTER.key
      \$DATACENTER.crt
  --tls-path/-t <val>:
    The value provided to `CONSUL_TLS_PATH` where the key content is expected. Defaults to "/ssl"
EOF
}

#
# Build the bootstrap CA container. Useful for testing. STDIN is used
# to eliminate build context.
#
function build() {
  image_name=

  while true; do
      case $1 in
          -i | --image-name ) image_name=$2; shift 2;;
          *) break;;
      esac
  done

  if [ -z "$image_name" ]; then
    echo "Image name must be provided"
    exit 1
  fi

  docker build - < ca/Dockerfile -t "$image_name"
}

#
# Use the bootstrap CA container to generate a certificate, a gossip shared key, or both.
#
function generate() {

  if [ ! -d ./secrets ]; then
    mkdir ./secrets
  fi

  local image_name=
  local datacenter_name=
  local target_hostname=
  local triton_profile=
  local gossip_key_file=

  while true; do
      case $1 in
          -i | --image-name )           image_name=$2;      shift 2;;
          -d | --datacenter-name )      datacenter_name=$2; shift 2;;
          -h | --hostname )             target_hostname=$2; shift 2;;
          -t | --triton-profile )       triton_profile=$2; shift 2;;
          -g | --gossip )               gossip_key_file=$2; shift 2;;
          *) break;;
      esac
  done

  if [ -z "$image_name" ]; then
    echo "Image name must be provided"
    exit 1
  fi

  if [ ! $(docker inspect "$image_name" &>/dev/null && echo $?) ]; then
    echo "Image specified ($image_name) does not exist"
    exit 1
  fi

  if [ -f ./secrets/gossip ] && [ -n "$gossip_key_file" ]; then
    echo "Gossip key generation requested but key already exists at ./secrets/gossip"
    exit 1
  fi

  if [ -z "$datacenter_name$gossip_key_file" ]; then
    echo "Not enough arguments to generate, need --datacenter-name/-d and/or --gossip/-g"
    exit 1    
  fi

  if [ -n "$target_hostname" ] && [ -n "$triton_profile" ]; then
    echo "Error, both target hostname and triton profile were specified."
    exit 1
  elif [ -z "$target_hostname" ] && [ -z "$triton_profile" ]; then
    target_hostname=consul
  elif [ -n "$triton_profile" ]; then
    # TODO: calculate hostname from triton profile:

    echo not yet
    exit 1

    TRITON_DC=$(triton profile get $triton_profile | awk -F"/" '/url:/{print $3}' | awk -F'.' '{print $1}')
    TRITON_ACCOUNT=$(TRITON_PROFILE=$triton_profile triton account get | awk -F": " '/id:/{print $2}')

    local triton_cns_enabled=$(TRITON_PROFILE=$triton_profile triton account get | awk -F": " '/cns/{print $2}')
    if [ ! "true" == "$triton_cns_enabled" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Triton CNS is required and not enabled.'
        tput sgr0 # clear
        echo
        exit 1
    fi

    target_hostname=consul.svc.${TRITON_ACCOUNT}.${TRITON_DC}.cns.joyent.com
  fi

  if [ -n "$datacenter_name" ]; then
    echo "Generating certificates for datacenter $datacenter_name"

    docker run -it --rm -v $(PWD)/secrets:/out "$image_name" $datacenter_name $target_hostname
    output_dir="$(PWD)/secrets/$datacenter_name"

    if ! $(find "$output_dir/ca.crt" "$output_dir/$datacenter_name.crt" "$output_dir/$datacenter_name.key" &>/dev/null); then
      echo "Error occurred while generating certificates or key!"
      exit 1
    fi

    echo "Certificates saved at $output_dir"
  fi

  if [ -n "$gossip_key_file" ]; then
    gossip_key_file="$(PWD)/secrets/$gossip_key_file"

    if [ -f "$gossip_key_file" ]; then
      echo "Gossip key file already exists at $gossip_key_file"
      exit 1
    else
      docker run -it --rm --entrypoint /bin/consul "$image_name" keygen > "$gossip_key_file"

      echo "Gossip key saved at $gossip_key_file"
    fi
  fi
}


function upload() {

  local compose_file=${COMPOSE_FILE:-${COMPOSE_FILE:-docker-compose.yml}}
  local compose_project_name=${COMPOSE_PROJECT_NAME:-$(basename $PWD)}
  local service_name=consul
  local datacenter_name=
  local tls_path=/ssl

  while true; do
      case $1 in
          -f | --compose-file )         compose_file=$2; shift 2;;
          -p | --compose-project-name ) compose_project_name=$2; shift 2;;
          -s | --service-name )         service_name=$2; shift 2;;
          -d | --datacenter-name )      datacenter_name=$2; shift 2;;
          -t | --tls-path )             tls_path=$2; shift 2;;
          *) break;;
      esac
  done

  if [ ! -f "$compose_file" ]; then
    echo "docker-compose file not found: $compose_file"
    exit 1
  fi

  local_tls_path="$PWD/secrets/$datacenter_name"
  echo "Checking for certificates and key in $local_tls_path"

  if [ ! -d "$local_tls_path" ] \
    || [ ! -f "$local_tls_path/ca.crt" ] \
    || [ ! -f "$local_tls_path/$datacenter_name.crt" ] \
    || [ ! -f "$local_tls_path/$datacenter_name.key" ]; then
    echo "Missing files in $local_tls_path. Check that the following files exist:"
    echo "Root certificate: $local_tls_path/ca.crt"
    echo "Client certificate: $local_tls_path/$datacenter_name.crt"
    echo "Client key: $local_tls_path/$datacenter_name.key"

    exit 1
  fi

  local container_ids=$(docker-compose -f $compose_file -p $compose_project_name ps -q $service_name)

  if [ -z "$container_ids" ]; then
    echo "No containers found! Project name: $compose_project_name, file: $compose_file"
    exit 1
  fi

  echo "Uploading key material to container IDs: ${container_ids[@]}"

  for container_id in $container_ids; do
    echo "Uploading key material from $local_tls_path to container ID: [$container_id] path: [$tls_path]"

    docker cp $local_tls_path $container_id:$tls_path
  done

  echo Successfully uploaded TLS certificates and key.
}

while true; do
    case $1 in
        build | generate | upload | help) cmd=$1; shift; break;;
        *) break;;
    esac
done

if [ -z $cmd ]; then
    help
    exit
fi

$cmd $@
