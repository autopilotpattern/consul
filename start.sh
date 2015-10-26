#!/bin/bash

# check for prereqs
command -v docker >/dev/null 2>&1 || { echo "Docker is required, but does not appear to be installed. See https://docs.joyent.com/public-cloud/api-access/docker"; exit; }
command -v sdc-listmachines >/dev/null 2>&1 || { echo "Joyent CloudAPI CLI is required, but does not appear to be installed. See https://apidocs.joyent.com/cloudapi/#getting-started"; exit; }
command -v json >/dev/null 2>&1 || { echo "JSON CLI tool is required, but does not appear to be installed. See https://apidocs.joyent.com/cloudapi/#getting-started"; exit; }

# manually name the project
export COMPOSE_PROJECT_NAME=consul

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
export BOOTSTRAP_HOST="$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${COMPOSE_PROJECT_NAME}_consulbootstrap_1"):8500"
ISRESPONSIVE=0
while [ $ISRESPONSIVE != 1 ]; do
    echo -n '.'

    curl -fs --connect-timeout 1 http://$BOOTSTRAP_HOST/ui &> /dev/null
    if [ $? -ne 0 ]
    then
        sleep .3
    else
        let ISRESPONSIVE=1
    fi
done
echo
echo 'The bootstrap instance is now running'
echo "Dashboard: $BOOTSTRAP_HOST/ui/"
command -v open >/dev/null 2>&1 && `open http://$BOOTSTRAP_HOST/ui/`



# Wait for, then bootstrap the first Consul raft instance
echo
echo -n 'Initilizing the Consul raft.'
ISRESPONSIVE=0
while [ $ISRESPONSIVE != 1 ]; do
    echo -n '.'

    RUNNING=$(docker inspect "${COMPOSE_PROJECT_NAME}_consul_1" | json -a State.Running)
    if [ "$RUNNING" == "true" ]
    then
        docker exec -it "${COMPOSE_PROJECT_NAME}_consul_1" triton-bootstrap bootstrap
        let ISRESPONSIVE=1
    else
        sleep .3
    fi
done
echo



# Wait for the first Consul raft instance
echo
echo -n 'Waiting for the first Consul raft instance to complete startup.'
export RAFT_HOST="$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "${COMPOSE_PROJECT_NAME}_consul_1"):8500"
ISRESPONSIVE=0
while [ $ISRESPONSIVE != 1 ]; do
    echo -n '.'

    curl -fs --connect-timeout 1 http://$RAFT_HOST/ui &> /dev/null
    if [ $? -ne 0 ]
    then
        sleep .3
    else
        let ISRESPONSIVE=1
    fi
done
echo
echo 'The Consul raft is now running'
echo "Dashboard: $RAFT_HOST/ui/"
command -v open >/dev/null 2>&1 && `open http://$RAFT_HOST/ui/`

echo
echo 'Scaling the Consul raft to three nodes'
echo "docker-compose -p=${COMPOSE_PROJECT_NAME} scale consul=3"
docker-compose -p=${COMPOSE_PROJECT_NAME} scale consul=3
