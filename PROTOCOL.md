ClearSkies Protocol v1
======================

The ClearSkies protocol is a two-way directory synchronization protocol,
inspired by BitTorrent Sync.  It is not compatible with btsync but a client
could potentially implement both protocols.  It is a friend-to-friend protocol
as opposed to a peer-to-peer protocol.


License
-------

This protocol documentation is in the public domain.  Private implementations
of this protocol are not constrained by the terms of the GPL v3.


Shared secrets
---------------

When a directory is first shared, a 160-bit encryption key is generated.  This
should not be generated with a psuedo-random number generator (PRNG), but
should come from a source of cryptographically secure numbers, such as
"/dev/random" on Linux, CryptGenRandom() on Windows, or RAND_bytes() in
OpenSSL.

This key is known as the read-write key.  The human-sharable version of this
key is prefixed with "CSW" and the key itself is encoded with base32 (see
the later for a precise definition).  Finally, a LUN check digit is added,
using the [LUN mod N algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm).

The SHA1 of the original 160-bit encryption key is the read-only key.  The
base32 version of this key is prefixed with an 'CSR'.

The SHA1 of the 160-bit read-only key is used as the share ID.  This ID is
represented as hex to avoid users confusing it with a key.

To share a directory with someone either the read-only or read-write key is
shared by some other means (over telephone, in person, by QR code, etc.)


Peer discovery
--------------

The share ID is used to find peers.  Various sources of peers are supported:

 * A central tracker
 * Manual entry by the user
 * LAN broadcast
 * A distributed hash table (DHT) amongst all participants
 * Previously valid addresses for the share

Each of these methods can be disabled by the user on a per-share basis and
implementations can elect not to implement them at their digression.

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


Tracker protocol
----------------

The tracker is an HTTP or HTTPS service.  The main tracker service runs at
tracker.example.com (To be determined).

Clients should come with the main tracker service address coded into the
software, and may optionally support additional tracker addresses.  Finally,
the user should be allowed to customize the tracker list.

Note that both peers should register themselves immediately with the tracker,
and re-registration should happen if the local IP address changes, or after the
TTL period has expired of the registration.

The share ID and listening port are used to make a request to the tracker:

    GET http://tracker.example.com/clearskies/track?id=22596363b3de40b06f981fb85d82312e8c0ed511&myport=30020

The response must have the content-type of application/json and will have a
JSON body like the following (newlines have been added for clarity):

```json
{
   "your_ip": "192.169.0.1",
   "others": ["128.1.2.3:40321"],
   "ttl": 3600
}
```

The TTL is a number of seconds until the client should register again.

The "others" key contains a list of all other clients that have registered for
this share ID.

The "features" list is a list of optional features supported by the tracker.


Fast tracker
------------

The fast tracker service is an extension to the tracker protocol that avoids
the need for polling.  The official tracker supports this extension.

An additional parameter, "fast_track" is set to "1" and the HTTP server will
not close the connection, instead sending new JSON messages whenever a new peer
is discovered.  This method is sometimes called HTTP push or HTTP streaming.

If the tracker does not support fast-track responses, it will just send a
normal response and close the connection.

The response will contain the first JSON message as normal, with an additional
key "timeout", with an integer value.  If the connection is idle for more than
"timeout" seconds, the client should consider the connection dead and open a
new one.

Some messages will be empty and used as a ping message to keep the connection
alive.

A complete response might look like:

```json
{"success":true,"your_ip":"192.169.0.1","others":["128.1.2.3:40321"],"ttl":3600,"timeout":120}
{}
{}
{"others":["128.1.2.3:40321","99.1.2.4:41234"]}
{}
{}
```


LAN Broadcast
-------------

Peers are discovered on the LAN by a UDP broadcast to port 60106.  The
broadcast contains the following JSON payload (newlines have been added for legibility):

```json
{
  "name": "ClearSkiesBroadcast",
  "version": 1,
  "share": "22596363b3de40b06f981fb85d82312e8c0ed511",
  "myport": 40121
}
```

Broadcast should be on startup, when a new share is added, when a new network
connection is detected, and every few minutes afterwards.


Distributed Hash Table
----------------------

One connected to a peer, a global DHT can be used to find more peers.  The DHT
contains the share -> 

Firewall transversal
--------------------

There is no standard port number on which to listen.

Clients support UPnP to make sure that its listening port is open to the world.

Future updates to protocol version 1 will include a method for communicating
over UDP.


Wire protocol
-------------

The wire protocol is composed of JSON messages, with an extension for handling
binary data.

A normal message is a JSON object on a single line, followed by a newline.  No
newlines are allowed within the JSON representation.  (Note that JSON encodes
newlines in strings as "\n", so there is no need to worry about cleaning out
newlines within the object.)

The object will have a "_type" key, which will identify the type of message.

For example:

```json
{"_type":"foo","arg":"Basic example message"}
```

To simplify implementations, messages are asynchronous (no immediate response
is required).  The protocol is almost entirely stateless.  For backwards
compatibility, unsupported message types or extra keys are silently ignored.

A message with a binary data payload is also encoded in JSON, but it is
prefixed with the number of bytes in ASCII, followed by an exclamation point,
and then the JSON message as usual, including the termination newline.  After
the newline, the entire binary payload will be sent.  For ease in debugging,
the binary payload will be followed by a newline.

For example:

```
12042!{"_type":"filedata","path":"photos/baby.jpg"}
JFIF..JdXNgc...8kTh  X gcqlh8kThJdXNg..lh8kThJd...cq.h8k...
```

As a rule, the receiver of file data should always be the one to request it.
It should never be opportunistically pushed.  This allows clients to stream
content or only do partial checkouts.


Handshake
---------

While normally peers are equal, we will distinguish between client and server
for the purposes of the handshake.  The server is the computer that received
the connection, but isn't necessarily the computer where the share was
originally created.

The handshake negotiates a protocol version as well as optional features, such
as compression.  When a connection is opened, the server sends a greeting
that lists all the protocol versions it supports, as well as an optional
feature list.  The protocol version is an integer.  The features are strings.

The current protocol version is 1.  Future improvements to version 1 will be
done in a backwards compatible way.  Version 2 is not compatible with version 1
clients.  Clients do not need to support more than one version.

Officially supported features will be documented here.  Unofficial features
should start with a period and then a unique prefix (similar to Java).

Here is an example message.  Newlines have been added for legibility, but they
would not be legal to send over the wire.

```json
{
  "_type": "greeting",
  "software": "bitbox 0.1",
  "protocol": [1],
  "features": ["gzip", ".com.github.jewel.messaging"]
}
```

The client will examine the greeting and decide which protocol version and
features it has in common with the server.  It will then respond with a start
message, which asks for a particular share by the share's public ID.  (See the
encryption section for an explanation of public IDs.)  Here is an example
"start" message.

```json
{
  "_type": "start",
  "software": "beetlebox 0.3.7",
  "protocol": 1,
  "features": [],
  "share": "22596363b3de40b06f981fb85d82312e8c0ed511"
}
```

If the server does not recognize this share, it will send back an
"no-such-share" message, and close the connection:

```json
{
  "_type": "no_such_share"
}
```

If the server does recognize the share, all future messages will be encrypted.


Connection encryption
---------------------

Encryption is 128-bit AES in CBC mode.  The key is the first 128 bits of the
160-bit read-only secret.  Note that even for read-write shares, the read-only
key is used, as the read-only key can be derived from the read-write key.


Base32
------

Base32 is used to encode keys for ease of manual keying.  Only uppercase A-Z
and the digits 2-9 are used.  Strings are taken five bits at a time, with
00000 being an 'A', 11001 being 'Z', 11010 being '2', and '11111' being '9'.

Human input should allow for lowercase letters, and should automatically
translate 0 as O.


Rate limiting
-------------

