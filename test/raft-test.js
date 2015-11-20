#!/usr/local/bin/node
var Docker = require('dockerode');
var Consul = require('consul');
var async = require('async');

// this will automatically pick up your DOCKER_HOST, DOCKER_CERT_PATH
var docker = new Docker();

listConsul(function (err, consulNodes) {
    if (err) {
        console.log(err);
        return;
    }
    switch (consulNodes.length) {
    case 3:
        console.log('Running 3-node raft tests.');
        run3NodeTests(consulNodes);
        break;
    case 5:
        console.log('Running 5-node raft tests.');
        run5NodeTests(consulNodes);
        break;
    default:
        console.log(consulNodes.length + ' Consul nodes up.');
        console.log('We need exactly 3 or 5 nodes to be up. Exiting.');
        break;
    }
    return;
});

// Runs a series of tests on raft behavior for a 3-node Consul cluster
function run3NodeTests(consulNodes) {
    console.log('Bootstrap node is:', consulNodes[0].Names[0]);
    waitForRaft(consulNodes, function (err, results) {
        if (err) {
            console.log(err);
            return;
        }
        console.log('Raft is healthy:', results);
    });

    async.series([
        function (cb) { test3_1(consulNodes, cb); },
        function (cb) { test3_2(consulNodes, cb); },
        function (cb) { test3_3(consulNodes, cb); }
    ],
    function (err, results) {
        console.log(err);
        console.log(results);
    });
}

// Runs a series of tests on raft behavior for a 5-node Consul cluster
function run5NodeTests(consulNodes) {
    console.log('Bootstrap node is:', consulNodes[0].Names[0]);
    waitForRaft(consulNodes, function (err, results) {
        if (err) {
            console.log(err);
            return;
        }
        console.log('Raft is healthy:', results);
    });

    async.series([
        function (cb) { test5_1(consulNodes, cb); },
        function (cb) { test5_2(consulNodes, cb); }
    ],
    function (err, results) {
        console.log(err);
        console.log(results);
    });
}


// Test that a non-bootstrap node rejoins the raft after reboot
function test3_1(consulNodes, callback) {
    var consul3 = consulNodes[2];
    async.series([
        function (cb) { stop(consul3, cb); },
        function (cb) { waitForRaft(consulNodes.slice(0, 1), cb); },
        function (cb) { testWrites(consulNodes.slice(0, 1),
                                   'consistent', true, cb); },
        function (cb) { start(consul3, cb); },
        function (cb) { waitForRaft(consulNodes, cb); }
    ],
    function (err, results) {
        callback(err, results);
    });
}

// Test that the bootstrap node rejoins the same raft after reboot
function test3_2(consulNodes, callback) {
    var consul1 = consulNodes[0];
    async.series([
        function (cb) { stop(consul1, cb); },
        function (cb) { waitForRaft(consulNodes.slice(1), cb); },
        function (cb) { start(consul1, cb); },
        function (cb) { waitForRaft(consulNodes, cb); }
    ],
    function (err, results) {
        callback(err, results);
    });
}

// Test that non-bootstrap nodes rejoin the raft even if bootstrap
// node is gone
function test3_3(consulNodes, callback) {
    var consul1 = consulNodes[0],
        consul2 = consulNodes[1],
        consul3 = consulNodes[2];

    async.series([
        function (cb) { stop(consul1, cb); },
        function (cb) { stop(consul2, cb); },
        function (cb) { stop(consul3, cb); },
        function (cb) { start(consul3, cb); },
        function (cb) { waitForRaft([consul3, consul2], cb); },
        function (cb) { start(consul1, cb); },
        function (cb) { waitForRaft(consulNodes, cb); }
    ],
    function (err, results) {
        callback(err, results);
    });
}

// Test that consistent reads fail without quorum but that they become
// available after partition heals
function test5_1(consulNodes, callback) {
    var consul1 = consulNodes[0],
        consul2 = consulNodes[1],
        consul3 = consulNodes[2],
        consul4 = consulNodes[3],
        consul5 = consulNodes[4];

    async.series([
        function (cb) { stop(consul1, cb); },
        function (cb) { stop(consul2, cb); },
        function (cb) { testWrites([consul3, consul4, consul5],
                                   'stale', true, cb); },
        function (cb) { testWrites([consul3, consul4, consul5],
                                   'consistent', false, cb); },
        function (cb) { start(consul2, cb); },
        function (cb) { waitForRaft(consulNodes.slice(1), cb); },
        function (cb) { testWrites([consul3, consul4, consul5],
                                   'consistent', true, cb); },
        function (cb) { start(consul1, cb); },
        function (cb) { waitForRaft(consulNodes, cb); }
    ],
    function (err, results) {
        callback(err, results);
    });
}

// Test that majority writes win after raft heals
function test5_2(consulNodes, callback) {
    var consul1 = consulNodes[0],
        consul2 = consulNodes[1],
        consul3 = consulNodes[2],
        consul4 = consulNodes[3],
        consul5 = consulNodes[4];

    async.series([
        function (cb) { createNetsplit([consul1, consul2],
                                       [consul3, consul4, consul5], cb); },
        function (cb) { testWrites([consul1, consul2],
                                   'stale', true, cb); },
        function (cb) { testWrites([consul1, consul2],
                                   'consistent', false, cb); },
        function (cb) { healNetsplit([consul1, consul2, consul3,
                                      consul4, consul5], cb); },
        function (cb) { waitForRaft(consulNodes, cb); },
        function (cb) { testWrites([consul1, consul2],
                                   'consistent', true, cb); }
    ],
    function (err, results) {
        callback(err, results);
    });
}


// Queries Consul to determine the status of the raft. Compares the status
// against a list of containers and verifies that they match exactly and
// that one of those nodes is the leader. If failing, will retry twice with
// some backoff and then return error to the callback if the raft still has
// not healed.
// @param    {containers} array of container objects from our Consul nodes
//           array that should be members of the raft.
// @callback {callback} function(err, result)
function waitForRaft(containers, callback) {

    var expected = [];
    containers.forEach(function (container) {
        expected.push(container.Ip+':8300');
    });
    expected.sort();
    console.log('Expected peers', expected);

    var isMatch = false;
    var count = 0;

    async.doUntil(
        function (cb) {
            getPeers(containers[0], function (err, peers) {
                if (err || !peers) {
                    cb(err);
                    return;
                }
                peers.sort();
                isMatch = (expected.length == peers.length) &&
                    expected.every(function (e, i) {
                        return e == peers[i];
                    });
                cb(null);
            });
        },
        function () {
            count++;
            return (isMatch || count > 3);
        },
        function (err) {
            if (err) {
                callback(err, false);
            } else {
                callback(null, isMatch);
            }
        });
}

// @param    {[containers]} array of container objects from our Consul
//                          nodes array that we want to test writes against
// @callback {callback} function(err, result)
function testWrites(containers, callback) {
    // TODO: implementation
    console.log(containers);
    console.log(callback);
}


function createNetsplit(group1, group2, callback) {
    // TODO: implementation
    console.log(group1);
    console.log(group2);
    console.log(callback);
}

function healNetsplit(containers, callback) {
    // TODO: implementation
    console.log(containers);
    console.log(callback);
}


// Create an array of containers labelled with the service 'consul',
// sorted by name
// @callback {fn} function(err, result)
function listConsul(callback) {
    var consul = [];
    docker.listContainers(
        {all: false,
         filters: ['{"label":["com.docker.compose.service=consul"]}']},
        function (err, containers) {
            if (err) {
                callback(err, null);
                return;
            }
            async.each(containers, function (container, cb) {
                docker.getContainer(container.Id).inspect(
                    function (e, data) {
                        if (e) {
                            cb(e);
                            return;
                        }
                        // dynamically add the Ip field to this object
                        // so that we can use it later without inspecting
                        container['Ip'] = data.NetworkSettings.IPAddress;
                        cb(null);
                    });
            }, function (inspectErr) {
                if (inspectErr) {
                    callback(inspectErr, null);
                }
                containers.forEach(function (container) {
                    consul.push(container);
                });
                consul.sort(byName);
                callback(null, consul);
                return;
            });
        });
}

function byName(a, b) {
    var x = a.Names[0]; var y = b.Names[0];
    return ((x < y) ? -1 : ((x > y) ? 1 : 0));
}

// @callback {fn} function(err, result)
function stop(container, fn) {
    docker.getContainer(container.Id).stop(fn);
}

// @callback {fn} function(err, result)
function start(container, fn) {
    docker.getContainer(container.Id).start(fn);
}

// @callback {fn} function(err, leader)
function getLeader(container, fn) {
    runExec(container,
            ['curl', '127.0.0.1:8500/v1/status/leader'],
            function (err, leader) {
                fn(err, matchIpPort(leader)[0]);
            });
}

// @callback {fn} function(err, peers)
// peers will be an array of strings in the form "{ip}:{port}"
function getPeers(container, fn) {
    runExec(container,
            ['curl', '127.0.0.1:8500/v1/status/peers'],
            function (err, peers) {
                fn(err, matchIpPort(peers));
            });
}

// returns an array of strings in the form ["{ip}:{port}"]
function matchIpPort(input) {
    return input.match(/[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:8300/g);
}


// Runs `docker exec` and concatenates stream into a single `results`
// string for the callback.
// @param    {container} container to run command on
// @param    {command} command and args ex. ['curl', '-v', 'example.com']
// @callback {callback(err, results)} results
function runExec(container, command, callback) {
    var options = {
        AttachStdout: true,
        AttachStderr: true,
        Tty: true,
        Cmd: command
    };
    docker.getContainer(container.Id).exec(options, function (execErr, exec) {
        if (execErr) {
            callback(execErr, null);
            return;
        }
        exec.start(function (err, stream) {
            if (err) {
                callback(err, null);
                return;
            }
            const chunks = [];
            stream.on('data', function (chunk) {
                chunks.push(chunk);
            });
            stream.on('end', function () {
                callback(null, chunks.join(''));
            });
        });
    });
}
