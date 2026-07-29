#!/usr/bin/env python3
"""CLI messaging subcommands for it2agent-broker (agent-comms).

`it2agent broker send/poll` give an agent that has it2agent on PATH but no MCP
wired a CLI path to the durable mailbox, parallel to the MCP send_message /
read_messages tools. These tests are headless and socket-free: they check the
arg→op mapping, then round-trip a CLI-built send through the real op dispatch +
mailbox and read it back with a CLI-built poll (the socket layer, _cmd_client,
is the same one ping/health/prune already use and is not re-tested here).
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import dispatch  # noqa: E402
import it2agent_broker as cli  # noqa: E402
import mailbox  # noqa: E402,F401  (importing registers the send/poll/ack ops)
import schema  # noqa: E402


def _args(argv):
    return cli._build_parser().parse_args(argv)


class TestSendPollArgMapping(unittest.TestCase):
    def test_send_request_minimal(self):
        args = _args(["send", "--to", "a1", "--from", "b2", "--body", "hi"])
        self.assertEqual(
            cli._build_send_request(args),
            {"op": "send", "to": "a1", "from": "b2", "body": "hi"},
        )

    def test_send_request_with_key(self):
        args = _args(
            ["send", "--to", "a1", "--from", "b2", "--body", "hi", "--key", "k1"]
        )
        self.assertEqual(cli._build_send_request(args)["key"], "k1")

    def test_send_omits_key_when_absent(self):
        args = _args(["send", "--to", "a1", "--from", "b2", "--body", "hi"])
        self.assertNotIn("key", cli._build_send_request(args))

    def test_poll_request_minimal(self):
        args = _args(["poll", "--agent", "a1"])
        self.assertEqual(cli._build_poll_request(args), {"op": "poll", "agent": "a1"})

    def test_poll_request_with_since(self):
        args = _args(["poll", "--agent", "a1", "--since", "5"])
        self.assertEqual(cli._build_poll_request(args)["since"], 5)


class TestSendPollRoundTripViaDispatch(unittest.TestCase):
    """A CLI-built send is a valid op that lands in the mailbox, and a CLI-built
    poll reads it back — proven through the real dispatch + mailbox, no socket."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self._tmp.name, "broker.db")
        self.conn = schema.init_db(self.db)
        self.ctx = dispatch.BrokerContext(conn=self.conn, db_path=self.db)

    def tearDown(self):
        self.conn.close()
        self._tmp.cleanup()

    def test_send_then_poll_round_trips(self):
        send_req = cli._build_send_request(
            _args(["send", "--to", "consultor", "--from", "tl", "--body", "ready?"])
        )
        resp = dispatch.handle(send_req, self.ctx)
        self.assertTrue(resp["ok"], resp)

        poll_req = cli._build_poll_request(_args(["poll", "--agent", "consultor"]))
        polled = dispatch.handle(poll_req, self.ctx)
        self.assertTrue(polled["ok"], polled)
        self.assertIn("ready?", [m["body"] for m in polled["messages"]])

    def test_key_dedups_on_repeat_send(self):
        argv = ["send", "--to", "c", "--from", "t", "--body", "hi", "--key", "once"]
        first = dispatch.handle(cli._build_send_request(_args(argv)), self.ctx)
        second = dispatch.handle(cli._build_send_request(_args(argv)), self.ctx)
        self.assertTrue(first["ok"] and second["ok"])
        # Same recipient+key => same id, flagged deduped (no second insert).
        self.assertEqual(first["id"], second["id"])
        self.assertTrue(second.get("dedup"))


if __name__ == "__main__":
    unittest.main()
