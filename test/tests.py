"""
Integration tests for autopilotpattern/consul. These tests are executed
inside a test-running container based on autopilotpattern/testing.
"""
import os
from os.path import expanduser
import random
import subprocess
import string
import sys
import time
import unittest
import uuid

from testcases import AutopilotPatternTest, WaitTimeoutError, \
     dump_environment_to_file


class ConsulStackTest(AutopilotPatternTest):

    project_name = 'consul'

    def setUp(self):
        """
        autopilotpattern/consul setup.sh writes an _env file with a CNS
        entry for Consul. If this has been mounted from the test environment,
        we'll use that, otherwise we have to generate it from the environment.
        Then make sure we use the external CNS name for the test rig.
        """
        account = os.environ['TRITON_ACCOUNT']
        dc = os.environ['TRITON_DC']
        internal = 'consul.svc.{}.{}.cns.joyent.com'.format(account, dc)
        external = 'consul.svc.{}.{}.triton.zone'.format(account, dc)

        if not os.path.isfile('_env'):
            os.environ['CONSUL'] = internal
            dump_environment_to_file('_env')

        os.environ['CONSUL'] = external

    def settle(self, count, timeout=30):
        """
        Waits for all containers to marked as 'Up'
        """
        while timeout > 0:
            containers = self.compose_ps()
            if len(containers) != count:
                continue
            if all([container.state == 'Up' for container in containers]):
                break
            time.sleep(1)
            timeout -= 1
        else:
            raise WaitTimeoutError("Timed out waiting for containers to start.")


    def converge(self, count, timeout=30):
        """
        Wait for the raft to become healthy with 'count' instances
        and an elected leader. Queries Consul to determine the status
        of the raft. Compares the status against a list of containers
        and verifies that the leader is among those.
        """
        while True:
            try:
                leader = self.consul.status.leader()
                peers = self.consul.status.peers()
                self.assertIsNotNone(peers, "Expected {} peers but got None"
                                     .format(count))
                self.assertNotEqual(leader, "",
                                    "Expected a leader but got none with peers={}"
                                    .format(peers))
                self.assertIn(leader, peers)
                self.assertEqual(len(peers), count,
                                 "Expected {} peers but got {}"
                                 .format(count, len(peers)))
                break
            except AssertionError:
                if timeout < 0:
                    raise
                time.sleep(1)
                timeout -= 1


class ConsulStackThreeNodeTest(ConsulStackTest):

    def test_rejoin_raft(self):
        """
        Given a healthy 3-node raft, make sure an instance that restarts
        can return to the raft.
        """
        self.compose_scale('consul', 3)
        self.instrument(self.settle, 3)
        self.instrument(self.converge, 3)
        self.docker('restart', self.get_container_name('consul', 1))
        self.instrument(self.settle, 3)
        self.instrument(self.converge, 3)


class ConsulStackFiveNodeTest(ConsulStackTest):

    def test_rejoin_raft(self):
        """
        Given a healthy 5-node raft, make sure an instance that restarts
        can return to the raft.
        """
        self.compose_scale('consul', 5)
        self.instrument(self.settle, 5)
        self.instrument(self.converge, 5)
        self.docker('restart', self.get_container_name('consul', 1))
        self.instrument(self.settle, 5)
        self.instrument(self.converge, 5)

    # TODO
    # def test_no_quorum_no_consistent_writes(self):
    #     """
    #     Given a broken quorum, make sure consistent reads fail
    #     until the quorum is restored.
    #     """
    #     pass

    # TODO
    # def test_majority_writes_win(self):
    #     """
    #     Given a healed quorum, make sure majority writes win.
    #     """
    #     pass


if __name__ == "__main__":
    unittest.main()
