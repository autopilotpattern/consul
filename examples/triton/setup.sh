#!/bin/bash
set -e -o pipefail

help() {
    echo
    echo 'Usage ./setup.sh'
    echo
    echo 'Checks that your Triton and Docker environment is sane and configures'
    echo 'an environment file to use.'
}

# populated by `check` function whenever we're using Triton
TRITON_USER=
TRITON_DC=
TRITON_ACCOUNT=

# ---------------------------------------------------
# Top-level commands

# Check for correct configuration and setup _env file
check() {

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
        echo 'See https://docs.joyent.com/public-cloud/api-access/triton-cli'
        exit 1
    }

    TRITON_USER=$(triton profile get 2>/dev/null | awk -F": " '/account:/{print $2}')
    TRITON_DC=$(triton profile get 2>/dev/null | awk -F"/" '/url:/{print $3}' | awk -F'.' '{print $1}')
    TRITON_ACCOUNT=$(triton account get 2>/dev/null | awk -F": " '/id:/{print $2}')
    if [ -z "$TRITON_USER" ] || [ -z "$TRITON_DC" ] || [ -z "$TRITON_ACCOUNT" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! A Triton profile does not appear to be configured.'
        tput sgr0 # clear
        echo
        echo 'See https://docs.joyent.com/public-cloud/api-access/triton-cli'
        echo
        exit 1
    fi

    command -v triton-docker >/dev/null 2>&1 || {
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! Joyent Triton CLI is required, but does not appear to be installed.'
        tput sgr0 # clear
        echo 'See https://docs.joyent.com/public-cloud/api-access/docker'
        exit 1
    }

    local triton_docker_configured=$(triton-docker info 2>/dev/null | awk -F": " '/Operating System:/{print $2}')
    if [ ! "SmartDataCenter" == "$triton_docker_configured" ]; then
        echo
        tput rev  # reverse
        tput bold # bold
        echo 'Error! The current Triton profile does not appear to be configured for use with triton-docker.'
        tput sgr0 # clear
        echo
        echo 'Consider running:'
        echo '  triton profile docker-setup'
        echo
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
    if [ ! -f "_env" ]; then
        echo '# Consul bootstrap via Triton CNS' >> _env
        echo CONSUL=consul.svc.${TRITON_ACCOUNT}.${TRITON_DC}.cns.joyent.com >> _env
        echo >> _env
    else
        echo 'Existing _env file found, exiting'
        exit
    fi
}

# ---------------------------------------------------
# parse arguments

# Get function list
funcs=($(declare -F -p | cut -d " " -f 3))

until
    if [ ! -z "$1" ]; then
        # check if the first arg is a function in this file, or use a default
        if [[ " ${funcs[@]} " =~ " $1 " ]]; then
            cmd=$1
            shift 1
        fi

        $cmd "$@"
        if [ $? == 127 ]; then
            help
        fi

        exit
    else
        check
    fi
do
    echo
done
