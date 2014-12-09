ClearSkies Protocol v1 Draft
============================

The ClearSkies protocol is a multi-way friend-to-friend protocol.  This is a
peer-to-peer protocol, in that the data is shared without the need for a
central server, but it is focused on use cases where the participants cooperate
with each other.

The original intended usage is file sharing, as inspired by BitTorrent Sync,
but the protocol is layered in such a way that other applications that wish to
use it for other purposes can do so easily.

This document describes the internals of the protocol.  Those wishing to use
clearskies as a library do not need to understand the internals, and instead
should consult with the implementation guide of a clearskies library.

The core protocol specifies the essentials: the format of access keys, peer
discovery, connection encryption, and message formatting.

The [database](database.md) extension builds on the core to add a distributed
key-value store and explain how to keep it synchronized.

Finally, the [directory](directory.md) extension uses both the core and the
database store to implement synchronization of an entire directory and its
contents.


Draft Status
------------

This is a draft of the version 1 protocol and is subject to changes as the need
arises.  However, it is believed to be feature complete.

Comments and suggestions are welcome in the form of github issues or on the
mailing list.  Analysis of the cryptography is doubly welcome.


License
-------

This spec is in the public domain.  See the file LICENSE in this same directory
for details.


Channel
-------

When the user connects two or more devices, their association forms a channel.
A channel is an encrypted, peer-to-peer connection.


Cryptographic Keys
------------------

When a channel is first created, a 2048-bit RSA private key is generated.  This
key is the communication key.  All of the peers share the same communication
key.  It is used to encrypt the communications, but is not used to authenticate
individual devices.

The first 128-bits of the SHA256 digest of the corresponding public RSA key
is known as the channel ID.

A 128-bit random number called the peer ID is also generated.  Each peer has
its own peer ID.  A different peer ID for each channel.  These are not private
nor secure.  (In other words, they are used to simplify some implementation
details, not to authenticate the source of messages.)

Finally, a 64-bit random number called the channel secret is generated.  The
secret MUST NOT be generated with a psuedo-random number generator (PRNG), but
instead must come from a source of cryptographically secure numbers, such as
`/dev/random` on Linux, `CryptGenRandom()` on Windows, or `RAND_bytes()` in
OpenSSL.

The RSA keys, channel ID, peer ID, and channel secret are stored permanently.


Access Codes
------------

To grant access to a new peer, an access code is generated.  The access code is
composed of the 128-bit channel ID the 64-bit channel secret.  The numbers are
presented to the user as an opaque 192-bit number.

The human-sharable version of the access code is represented in base32, as
defined in [RFC 4648](http://tools.ietf.org/html/rfc4648).  Since base32
requires lengths that are divisible by 5, we add another 8-bits to the 192-bit
string to make 200 bits.

The 8 bit number is a check digit, created using the [LUN mod N
algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), where N is 256.
The final result is a 40 character string.

Note: The core protocol does not support granting short-lived or single-use
access codes, but sophisticated peers can create them by using the
`temporary_code` extension.  (Documentation on that extension will be
forthcoming.)  The core protocol is written in such a way that temporary access
codes can be used by peers that do not implement the extension.


Wire Protocol
-------------

The wire protocol is composed of JSON messages.  Sometimes the messages are
accompanied by binary data, which is sent as a payload after the message body,
but considered part of it.

To simplify implementations, messages are asynchronous (no immediate response
is required).  Once initial negotiation is complete, the protocol is stateless.
For forward compatibility, unsupported message types or extra keys should be
silently ignored.

Each message begins with a header.  The header starts with a single character
prefix.

* `m` is only JSON
* `!` is JSON with a binary attachment

Each of these types will be explained in turn.

For both message types the length of the JSON object is added after the prefix,
using ASCII characters, followed by a newline.

The JSON body must start with a "{" character.  That is to say, it is not valid
to have an array, string, or other non-object as the body.

The JSON object will have a "type" member, which will identify the type of
message.

For example:

```
m82
{
  "type": "foo",
  "message": "Basic example message",
  "declaration": "For great justice"
}
```

A message with a binary data payload is prefixed with an exclamation point and
then the JSON body he binary payload is sent as usual.  The binary payload is
then sent in one or more chunks, ending with a zero-length binary chunk.  Each
chunk begins with its length in ASCII digits, followed by a newline, followed
by the binary data.

Note: Since large chunk sizes minimize the protocol overhead and syscall
overhead for high-speed transfers, the recommended chunk size is at least a
megabyte.  In order to handle very large chunks, the data should be processed
as it is received.

Explanation:  Why have chunking?  Chunked binary data allows a binary
attachment of unknown length to be streamed to a peer.  For example, streaming
a long video that is being transcoded on the fly.

An example message with a binary payload might look like:

```
!44
{"type":"file_data","path":"test/file.txt"}
45
This is just text, but could be binary data!
25
This is more binary data
0
```


Peer Discovery
--------------

When given an access code, the first 128-bits, which is a digest of the RSA
public key, is used to find peers.

Various sources of peers are supported:

 * A [central tracker](tracker.md)
 * Manual IP address and port entry by the user
 * LAN [broadcast](broadcast.md)
 * A distributed hash table (DHT) amongst all participants (not yet specified)
 * A cache of previously known peer addresses

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


NAT Transversal
---------------

There is no standard port number on which to listen.

Software can attempt to use UPnP to make sure that the listening TCP port is
open to the world.

In order to bypass typical residential NATs, UDP hole punching is used.  This
is facilitated by [STUN](http://tools.ietf.org/html/rfc5389) is used.  STUN is
a way to determine the public IP address and port of an open UDP socket on the
NAT firewall.

To add reliability to UDP, SCTP-over-UDP (rfc ????), (link to usrsctp) is
recommended.  However, for simple implementations and non-bandwidth-intensive
purposes, all clearskies implementations must also support the [Basic UDP
Reliability Protocol](burp.md), hereafter BURP.

On startup, the software should connect to the STUN server to determine its UDP
port.  Each software vendor should hard-code a default STUN server or list of
STUN servers.  (It is not important that all peers use the same STUN server.)

The UDP port mapping in the firewall's NAT table should be kept open by
accessing the STUN server periodically if there is no other activity on the
port.

Once the UDP port has be determined, it should be sent to the tracker using a
"tracker.connection" message.  A peer can then use this information to open a
BURP session.

The TLS encryption (described later) is sent on the BURP socket or
SCTP-over-UDP socket just as if it were a regular TCP socket.


Connection
----------

ClearSkies uses any of the TLS modes that support RSA keys.  Even though it is
a peer-to-peer protocol, for the purposes of clarity the originating computer
is will be called the "client" and the other will be called the "server".

An initial, unencrypted exchange happens on the socket before TLS is started.
The client tells the server which channel it is seeking.  Alternatively, the
client can already be a member of the channel, and the server is the peer with
just an access code.

The client sends the server the either the word "want" or "have", followed by a
space, followed the 128-bit channel ID, encoded in lowercase hexadecimal,
followed by a newline:

```
have 1ee612634987d088e96580b84526f560
```

If the server does not recognize the channel ID, it should close the
connection.

If the client said "want", the server starts a TLS session using
the RSA key.

If the client said "have", the TLS session is started with the client acting as
the TLS server, with its RSA key.  This is backwards from what would normally
happen on a normal TLS-over-TCP connection.

The TLS server is verified by the client by taking the digest of its public
key and seeing if it matches the channel ID.

Once the TLS session is established, whichever peer is acting as the "TLS
client" sends the word "secret", followed by a space, followed by the 64-bit
"channel secret" as lowercase hexadecimal, followed by a newline:

```
secret 1395538cbb0eec91
```

The TLS server responds by closing the connection if the secret is invalid.
Otherwise, the peers handshake.

The TLS server should rate-limit secret-checking attempts to a reasonable
amount for any given address, and should verify the secret using a
constant-time comparison to avoid timing attacks.


Handshake
---------

In this section, "server" refers to the TLS server.

The handshake negotiates a protocol version as well as optional extensions,
such as compression.  The server sends a "greeting" message that lists all of
the protocol versions it supports, as well as an optional extension list.  The
protocol version is an integer.  The extensions are strings.

What follows is an example greeting:

```json
{
  "type": "core.greeting",
  "software": "bitbox 0.1",
  "name": "Jaren's Laptop",
  "protocol": [1],
  "extensions": ["gzip", "rsync"],
  "peer": "77b8065588ec32f95f598e93db6672ac"
}
```

The "peer" field is the channel-specific ID explained in the cryptographic keys
section.  This is used to avoid accidental loopback.  The "name" is an optional
human-friendly identifier, if set by the user.

The client will examine the greeting and decide which protocol version and
extensions it has in common with the server.  It will then respond with a start
message. Here is an example "core.start" message:

```json
{
  "type": "core.start",
  "software": "beetlebox 0.3.7",
  "protocol": 1,
  "extensions": ["gzip"],
  "peer": "6f5902ac237024bdd0c176cb93063dc4",
  "name": "Jaren's Desktop"
}
```


Extending the Protocol
----------------------

The current protocol version is 1.  Future improvements to version 1 will be
done in a backwards compatible way.  Version 2 will not be compatible with
version 1.

Officially supported extensions will be documented in the same directory as
this spec.  Unofficial extensions should start with a period and then a unique
prefix (similar to Java).  Unofficial messages should prefix the "type" key
with its unique prefix.

For example, if IBM created their own music streaming extension, the extension
name would be ".com.ibm.music_streaming".  The message "type" field should also
be prefixed with this string:

```json
{
  "type": ".com.ibm.music_streaming.get_artists"
}
```


Key Exchange
------------

The very first connection will have been started with an access code instead of
a key, and after the "start" message is received the full channel RSA key can
be requested.  This is done by the new peer sending the `request_key` message.

```json
{
  "type": "core.request_key"
}
```

The older peer will respond with a `key` message.

The RSA key should be encoded using the PEM format.  In this example, the RSA
key has been abbreviated for clarity:

```json
{
  "type": "core.key",
  "private_rsa": "-----BEGIN RSA PRIVATE KEY-----\nMIIJKAIBAAKCAgEA4Zu1XDLoHf...TE KEY-----\n"
}
```


Messages
--------

Once the connection has been established messages are exchanged until one side
closes the connection.

The messages exchanged may be application specific or they might be part of
an official extension, such as `database` or `directory`.


Keep-alive
---------

A message of type "core.ping" should be sent by each peer occasionally to keep
connections from being dropped:

```json
{"type":"core.ping","timeout":60}
```

The "timeout" specified is the absolute minimum amount of time to wait for the
peer to send another ping before dropping the connection.  A peer should adjust
its own timeout to be same as the timeout of its peer if the peer's timeout is
greater, that way software on mobile devices can adjust for battery life and
network conditions.



Known Issues
------------

This is a list of known issues or problems with the protocol.  The serious
issues will be addressed before the spec is finalized.

* When an access code is shared with multiple people, and then the originating
  node is taken offline, the users will unknowingly connect to each other
  instead the original node.  This is an error state but it is hard to detect.
  The tracker can be enhanced to know the difference between those that have
  the keys associated with an access code and those that are seeking those
  keys.
