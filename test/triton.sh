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
        got=$(triton-compose -p "$project" -f "$manifest" ps consul)
        got=$(echo "$got" | grep -c "Up")
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
        leader=$(curl -s "http://${consul_ip}:8500/v1/status/leader")
        leader=$(echo "$leader" | json)
        if [[ "$leader" != "[]" ]]; then
            peers=$(curl -s "http://${consul_ip}:8500/v1/status/peers")
            peers=$(echo "$peers" | json -a)
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
    echo '* cleaning up previous test run'
    echo
    triton-compose -p "$project" -f "$manifest" stop
    triton-compose -p "$project" -f "$manifest" rm -f

    echo
    echo '* standing up initial test targets'
    echo
    triton-compose -p "$project" -f "$manifest" up -d
}

teardown() {
    echo
    echo '* tearing down containers'
    echo
    triton-compose -p "$project" -f "$manifest" stop
    triton-compose -p "$project" -f "$manifest" rm -f
}

scale() {
    count="$1"
    echo
    echo '* scaling up cluster'
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
    run
    scale "$count"
    wait_for_containers "$count"
    wait_for_cluster "$count"

    restart "consul_1"
    wait_for_containers "$count"
    wait_for_cluster "$count"
}

test-graceful-leave() {
    echo
    echo '------------------------------------------------'
    echo "executing graceful-leave test with 5 nodes"
    echo '------------------------------------------------'
    run
    scale 5
    wait_for_containers 5
    wait_for_cluster 5

    echo
    echo '* writing key'
    consul_ip=$(triton ip "${project}_consul_1")
    curl --fail -s -o /dev/null -XPUT --data "hello" \
         "http://${consul_ip}:8500/v1/kv/test_grace"

    echo
    echo '* gracefully stopping 3 nodes of cluster'
    triton-docker stop "${project}_consul_3"
    triton-docker stop "${project}_consul_4"
    triton-docker stop "${project}_consul_5"
    wait_for_containers 2

    echo
    echo '* checking consistent read'
    consistent=$(curl -s "http://${consul_ip}:8500/v1/kv/test_grace?consistent")
    if [[ "$consistent" == "aGVsbG8=" ]]; then
       fail "got '${consistent}' back from query; should not have cluster leader after 3 nodes"
    fi

    echo '* checking stale read'
    stale=$(curl -s "http://${consul_ip}:8500/v1/kv/test_grace?stale")
    stale=$(echo "$stale" | json -a Value)
    # this value is "hello" base64 encoded
    if [[ "$stale" != "aGVsbG8=" ]]; then
        fail "got '${stale}' back from query; could not get stale key after 3 nodes gracefully exit"
    fi
}

test-quorum-consistency() {
    echo
    echo '------------------------------------------------'
    echo "executing quorum-consistency test with 5 nodes"
    echo '------------------------------------------------'
    run
    scale 5
    wait_for_containers 5
    wait_for_cluster 5

    echo
    echo '* writing key'
    consul_ip=$(triton ip "${project}_consul_1")
    curl --fail -s -o /dev/null -XPUT --data "hello" \
         "http://${consul_ip}:8500/v1/kv/test_quorum"

    echo
    echo '* netsplitting 3 nodes of cluster'
    netsplit "consul_3"
    netsplit "consul_4"
    netsplit "consul_5"

    echo
    echo '* checking consistent read'
    consistent=$(curl -s "http://${consul_ip}:8500/v1/kv/test_quorum?consistent")
    if [[ "$consistent" == "aGVsbG8=" ]]; then
       fail "got '${consistent}' back from query; should not have cluster leader after 3 nodes"
    fi

    echo
    echo '* checking write to isolated node'
    set +e
    docker exec -it "${project}_consul_1" \
           curl --fail -XPUT -d someval localhost:8500/kv/somekey
    result=$?
    set -e
    if [ "$result" -eq 0 ]; then
        fail 'was able to write to isolated node'
    fi

    echo '* checking stale read'
    stale=$(curl -s "http://${consul_ip}:8500/v1/kv/test_quorum?stale")
    stale=$(echo "$stale" | json -a Value)
    # this value is "hello" base64 encoded
    if [[ "$stale" != "aGVsbG8=" ]]; then
        fail "got '${stale}' back from query; could not get stale key after 3 nodes netsplit"
    fi

    echo
    echo '* healing netsplit'
    heal "consul_3"
    heal "consul_4"
    heal "consul_5"
    wait_for_cluster 5

    echo '* checking consistent read'
    consistent=$(curl -s "http://${consul_ip}:8500/v1/kv/test_quorum?consistent")
    consistent=$(echo "$consistent" | json -a Value)
    # this value is "hello" base64 encoded
    if [[ "$consistent" != "aGVsbG8=" ]]; then
        fail "got '${consistent}' back from query; could not get consistent key after recovery"
    fi
}

# --------------------------------------------------------------------
# Main loop

profile
test-rejoin-raft 3
test-rejoin-raft 5
test-graceful-leave
test-quorum-consistency
