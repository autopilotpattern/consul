#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { echo "Docker is required, but does not appear to be installed. See https://docs.joyent.com/public-cloud/api-access/docker"; exit; }

# default values which can be overriden by -f or -p flags
export COMPOSE_FILE=
export COMPOSE_PROJECT_NAME=consul

while getopts "f:p:" optchar; do
    case "${optchar}" in
        f) export COMPOSE_FILE=${OPTARG} ;;
        p) export COMPOSE_PROJECT_NAME=${OPTARG} ;;
    esac
done
shift $(expr $OPTIND - 1 )

# give the docker remote api more time before timeout
export DOCKER_CLIENT_TIMEOUT=300

echo 'Starting a Triton trusted Compose service'

echo
echo 'Pulling the most recent images'
docker-compose pull

echo
echo 'Starting containers'
docker-compose up -d --no-recreate

# Wait for the bootstrap instance
echo
echo -n 'Waiting for the bootstrap instance.'
export BOOTSTRAP_HOST="$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${COMPOSE_PROJECT_NAME}_consul_1")"
ISRESPONSIVE=0
while [ $ISRESPONSIVE != 1 ]; do
    echo -n '.'

    curl -fs --connect-timeout 1 http://$BOOTSTRAP_HOST:8500/ui &> /dev/null
    if [ $? -ne 0 ]
    then
        sleep .3
    else
        let ISRESPONSIVE=1
    fi
done
echo
echo 'The bootstrap instance is now running'
echo "Dashboard: $BOOTSTRAP_HOST:8500/ui/"
command -v open >/dev/null 2>&1 && `open http://$BOOTSTRAP_HOST:8500/ui/`


echo 'Scaling the Consul raft to three nodes'
echo "docker-compose -p ${COMPOSE_PROJECT_NAME} scale consul=3"
docker-compose scale consul=3
