Tracker Protocol
================

This is the tracker protocol.  It is part of the core clearskies protocol.

The tracker is a socket service.  The main tracker service runs at
clearskies.tuxng.com on port 49200.  Only one connection to the tracker is
necessary.

Peers should register themselves immediately with the tracker, and
re-registration should happen if the IP address or port changes.

Communication with the tracker is done with clearskies messages, which are
encoded using the "wire protocol", as was explained earlier.

Upon receiving a connection, the tracker will send a greeting message:

```json
{
  "type": "tracker.greeting",
  "software": "clearskies tracker build 143",
  "max_ttl": 3600,
  "min_ttl": 60,
  "your_ip": "1.22.1.184",
  "protocol": [1],
  "extensions": []
}
```

The protocol array has a list of the major version numbers of the tracker
protocol that the tracker supports.  This document describes version 1 of the
tracker protocol.  The extensions array is an optional list of extensions that
the tracker supports, as strings.  See the description for the "greeting"
message later in this document for details about extensions.  As of the time of
writing, no official tracker extensions exist.

The "software" field is strictly informational.

The "your_ip" field tells the client from what source IP address the tracker
server is seeing the connection.  This may be IPv4 or IPv6.  An IPv6 address
will be surrounded with square brackets.

The TTL fields are given as guidelines for the client.  Using these
guidelines, the client will populate its own "ttl" response field, which
tells the tracker how often the client intends to check in.  If the tracker
hasn't heard from the client for longer than this time period, the tracker will
assume the client is no longer active.

The client then responds with a "tracker.start" message, in which it specifies
the version of the protocol it would like to use, as well as which extensions
it would like to activate:

```json
{
  "type": "tracker.start",
  "software": "beetlebox 0.3.7",
  "protocol": 1,
  "ttl": 60,
  "extensions": []
}
```

From this point, messages are allowed in any order.  The messages are
asynchronous, meaning that either side may send a message at any time.

The client can now send two types of messages: "tracker.connection" and
"tracker.registration".

The "tracker.connection" message contains information on how to connect to the
client:

```json
{
  "type": "tracker.connection",
  "addresses": [
    "tcp:192.168.1.2:49221",
    "tcp:1.2.1.1:49221",
    "tcp:[2600:3c01::f03c:91ff:feae:914c]:49221",
    "utp:1.2.1.1:3824"
  ]
}
```

The "addresses" array isn't parsed by the tracker, and is repeated verbatim to
other peers.

If the client later discovers it has another address, it should send another
"tracker.connection" message, with the complete list of addresses.  The address
list will replace the earlier list sent.

The client registers the key IDs and access IDs it knows about.  As
was explained earlier, the tracker doesn't differentiate between access IDs and
key IDs, as the distinction isn't important for peer discovery.  Registration
is done with the "tracker.registration" message:

```json
{
  "type": "tracker.registration",
  "ids": {
    "1bff33a239ae76ab89f94b3e582bcf7dde5549c141db6d3bf8f37b49b08d1075": "be8b773c227f44c5110945e8254e722c",
    "2da03f6f37cee78fb13e32f4fc5a261e1c57c173087ccc787fb2c4f24d3447d9": "feeb61382cb9bbfb31ed4349727fa70c"
  }
}
```

The "ids" field contains a hash where the key is the ID (either the access ID
or the key ID) and the value is the peer ID.

If a club or access code is added or removed on the client, it should send
a complete "tracker.register" message, including all known IDs.

The tracker combines this information into a "tracker.peers" message.  There is
a separate peers message for each club.  Subsequent messages about the same
club are meant to replace all earlier information about that club.

```json
{
  "type": "tracker.peers",
  "id": "1bff33a239ae76ab89f94b3e582bcf7dde5549c141db6d3bf8f37b49b08d1075",
  "peers": {
    "be8b773c227f44c5110945e8254e722c": ["tcp:128.1.2.3:3512", "utp:128.1.2.3:52012"]
  }
}
```

The "peers" field is a mapping from peer ID to a list of connection addresses.

As of the time of writing, only the `tcp` and `utp` psuedo-protocols are known.
Clients should ignore other protocols for future compatibility.

The client should send a "tracker.ping" message periodically.  If sent less
often than the negotiated TTL, the tracker will assume the peer has been
disconnected.

```json
{
  "type": "tracker.ping"
}
```
