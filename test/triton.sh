#!/bin/bash
set -e

export GIT_BRANCH="${GIT_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
export TAG="${TAG:-branch-$(basename "$GIT_BRANCH")}"
export COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-consul}"
export COMPOSE_FILE="${COMPOSE_FILE:-./docker-compose.yml}"

project="$COMPOSE_PROJECT"
manifest="$COMPOSE_FILE"

fail() {
    echo
    echo '------------------------------------------------'
    echo 'FAILED: dumping logs'
    echo '------------------------------------------------'
    triton-compose -p "$project" -f "$manifest" ps
    triton-compose -p "$project" -f "$manifest" logs
    echo '------------------------------------------------'
    echo 'FAILED'
    echo "$1"
    echo '------------------------------------------------'
    exit 1
}

pass() {
    teardown
    echo
    echo '------------------------------------------------'
    echo 'PASSED!'
    echo
    exit 0
}

function finish {
    result=$?
    if [ $result -ne 0 ]; then fail "unexpected error"; fi
    pass
}
trap finish EXIT



# --------------------------------------------------------------------
# Helpers

# asserts that 'count' Consul instances are running and marked as Up
# by Triton. fails after the timeout.
wait_for_containers() {
    local count timeout i got
    count="$1"
    timeout="${3:-60}" # default 60sec
    i=0
    echo "waiting for $count Consul containers to be Up..."
    while [ $i -lt "$timeout" ]; do
        got=$(triton-compose -p "$project" -f "$manifest" ps consul | grep -c "Up")
        if [ "$got" -eq "$count" ]; then
            echo "$count instances reported Up in <= $i seconds"
            return
        fi
        i=$((i+1))
        sleep 1
    done
    fail "$count instances did not report Up within $timeout seconds"
}

# asserts that the raft has become healthy with 'count' instances
# and an elected leader. Queries Consul to determine the status
# of the raft. Compares the status against a list of containers
# and verifies that the leader is among those.
wait_for_cluster() {
    local count timeout i got consul_ip
    count="$1"
    timeout="${2:-60}" # default 60sec
    i=0
    echo "waiting for raft w/ $count instances to converge..."
    consul_ip=$(triton ip "${project}_consul_1")
    while [ $i -lt "$timeout" ]; do
        leader=$(curl -s "http://${consul_ip}:8500/v1/status/leader" | json)
        if [[ "$leader" != "[]" ]]; then
            peers=$(curl -s "http://${consul_ip}:8500/v1/status/peers" | json -a)
            peer_count=$(echo "$peers" | wc -l | tr -d ' ')
            if [ "$peer_count" -eq "$count" ]; then
                echo "$peers" | grep -q "$leader"
                if [ $? -eq 0 ]; then
                    echo "raft converged in <= $i seconds w/ leader $leader"
                    return
                fi
            fi
        fi
        i=$((i+1))
        sleep 1
    done
    fail "raft w/ $count instances did not converge within $timeout seconds"
}

restart() {
    node="${project}_$1"
    triton-docker restart "$node"
}

netsplit() {
    echo "netsplitting ${project}_$1"
    triton-docker exec "${project}_$1" ifconfig eth0 down
}

heal() {
    echo "healing netsplit for ${project}_$1"
    triton-docker exec "${project}_$1" ifconfig eth0 up
}

run() {
    echo
    echo '------------------------------------------------'
    echo 'cleaning up previous test run'
    echo '------------------------------------------------'
    triton-compose -p "$project" -f "$manifest" stop
    triton-compose -p "$project" -f "$manifest" rm -f

    echo
    echo '------------------------------------------------'
    echo 'standing up initial test targets'
    echo '------------------------------------------------'
    echo
    triton-compose -p "$project" -f "$manifest" up -d
}

teardown() {
    echo
    echo '------------------------------------------------'
    echo 'tearing down containers'
    echo '------------------------------------------------'
    echo
    triton-compose -p "$project" -f "$manifest" stop
    triton-compose -p "$project" -f "$manifest" rm -f
}

scale() {
    count="$1"
    echo
    echo '------------------------------------------------'
    echo 'scaling up cluster'
    echo '------------------------------------------------'
    echo
    triton-compose -p "$project" -f "$manifest" scale consul="$count"
}

# --------------------------------------------------------------------
# Test sections

profile() {
    echo
    echo '------------------------------------------------'
    echo 'setting up profile for tests'
    echo '------------------------------------------------'
    echo
    export TRITON_PROFILE="${TRITON_PROFILE:-us-east-1}"
    set +e
    # if we're already set up for Docker this will fail noisily
    triton profile docker-setup -y "$TRITON_PROFILE" > /dev/null 2>&1
    set -e
    triton profile set-current "$TRITON_PROFILE"
    eval "$(triton env)"

    # print out for profile debugging
    env | grep DOCKER
    env | grep SDC
    env | grep TRITON

    bash /src/setup.sh
}

test-rejoin-raft() {
    count="$1"
    echo
    echo '------------------------------------------------'
    echo "executing rejoin-raft test with $count nodes"
    echo '------------------------------------------------'
    echo
    run
    scale "$count"
    wait_for_containers "$count"
    wait_for_cluster "$count"

    restart "consul_1"
    wait_for_containers "$count"
    wait_for_cluster "$count"
}

test-graceful-leave() {
    echo 'TODO'
}

test-quorum-consistency() {
    echo 'TODO'
}

# --------------------------------------------------------------------
# Main loop

profile
test-rejoin-raft 3
test-rejoin-raft 5
#test-graceful-leave 5
#test-quorum-consistency 5
