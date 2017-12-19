#!/bin/bash
set -e -o pipefail

help() {
    echo
    echo 'Usage ./setup-multi-datacenter.sh <triton-profile1> [<triton-profile2> [...]]'
    echo
    echo 'Invokes ./setup repeatedly to create one _env file per datacenter per triton profile,'
    echo 'attempting to preserve the triton profile set before this script was invoked.'
    echo
    echo 'Warning: The current triton profile will be changed for each invocation of ./setup.sh,'
    echo 'this may cause unexpected behavior if other commands that read the current triton profile'
    echo 'are executed concurrently!'
}

if [ "$#" -lt 1 ]; then
  help
  exit 1
fi

# ---------------------------------------------------
# Top-level commands

#
# Check for correct configuration and setup _env file named $1
#
generate_env() {

    command -v docker >/dev/null 2>&1 || {
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Docker is required, but does not appear to be installed.'
        tput sgr0 # clear
        echo 'See https://docs.joyent.com/public-cloud/api-access/docker'
        exit 1
    }
    command -v triton >/dev/null 2>&1 || {
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Joyent Triton CLI is required, but does not appear to be installed.'
        tput sgr0 # clear
        echo 'See https://www.joyent.com/blog/introducing-the-triton-command-line-tool'
        exit 1
    }

    # make sure Docker client is pointed to the same place as the Triton client
    local docker_user=$(docker info 2>&1 | awk -F": " '/SDCAccount:/{print $2}')
    local docker_dc=$(echo $DOCKER_HOST | awk -F"/" '{print $3}' | awk -F'.' '{print $1}')

    local TRITON_USER=$(triton profile get $TRITON_PROFILE | awk -F": " '/account:/{print $2}')
    local TRITON_DC=$(triton profile get $TRITON_PROFILE | awk -F"/" '/url:/{print $3}' | awk -F'.' '{print $1}')
    local TRITON_ACCOUNT=$(triton account get | awk -F": " '/id:/{print $2}')

    if [ ! "$docker_user" = "$TRITON_USER" ] || [ ! "$docker_dc" = "$TRITON_DC" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! The Triton CLI configuration does not match the Docker CLI configuration.'
        tput sgr0 # clear
        echo
        echo "Docker user: ${docker_user}"
        echo "Triton user: ${TRITON_USER}"
        echo "Docker data center: ${docker_dc}"
        echo "Triton data center: ${TRITON_DC}"
        exit 1
    fi

    local triton_cns_enabled=$(triton account get | awk -F": " '/cns/{print $2}')
    if [ ! "true" == "$triton_cns_enabled" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Triton CNS is required and not enabled.'
        tput sgr0 # clear
        echo
        exit 1
    fi

    # setup environment file
    if [ ! -f "$1" ]; then
        echo '# Consul bootstrap via Triton CNS' >> $1
        echo CONSUL=consul.svc.${TRITON_ACCOUNT}.${TRITON_DC}.cns.joyent.com >> $1
        echo >> $1
    else
        echo "Existing _env file found at $1, exiting"
        exit
    fi
}


declare -a written
declare -a consul_hostnames

# check that we won't overwrite any _env files first
if [ -f "_env" ]; then
    echo "Existing env file found, exiting: _env"
fi

# check the names of _env files we expect to generate
for profile in "$@"
do
    if [ -f "_env-$profile" ]; then
        echo "Existing env file found, exiting: _env-$profile"
        exit 2
    fi

    if [ -f "_env-$profile" ]; then
        echo "Existing env file found, exiting: _env-$profile"
        exit 3
    fi

    if [ -f "docker-compose-$profile.yml" ]; then
        echo "Existing docker-compose file found, exiting: docker-compose-$profile.yml"
        exit 4
    fi
done

# check that the docker-compose.yml template is in the right place
if [ ! -f "docker-compose-multi-dc.yml.template" ]; then
    echo "Multi-datacenter docker-compose.yml template is missing!"
    exit 5
fi

# invoke ./setup.sh once per profile
for profile in "$@"
do
    echo "Temporarily switching profile: $profile"
    eval "$(TRITON_PROFILE=$profile triton env -d)"

    TRITON_PROFILE=$profile generate_env("_env-$profile")

    unset CONSUL
    source "_env-$profile"

    consul_hostnames+=("\"${CONSUL//cns.joyent.com/triton.zone}\"")

    cp docker-compose-multi-dc.yml.template \
       "docker-compose-$profile.yml"

    sed -i '' "s/ENV_FILE_NAME/_env-$profile/" "docker-compose-$profile.yml"

    written+=("_env-$profile")
done


# finalize _env and prepare docker-compose.yml files
for profile in "$@"
do
    # add the CONSUL_RETRY_JOIN_WAN addresses to each _env
    echo '# Consul multi-DC bootstrap via Triton CNS' >> _env-$profile
    echo "CONSUL_RETRY_JOIN_WAN=$(IFS=,; echo "${consul_hostnames[*]}")" >> _env-$profile

    cp docker-compose-multi-dc.yml.template \
       "docker-compose-$profile.yml"

    sed -i '' "s/ENV_FILE_NAME/_env-$profile/" "docker-compose-$profile.yml"
done

echo "Wrote: ${written[@]}"
