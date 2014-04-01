ClearSkies Protocol v1 Draft
============================

The ClearSkies protocol is a multi-way friend-to-friend protocol.  This is a
special kind of peer-to-peer protocol, in that the data is shared without the
need for a central server, but it is focused on use cases where each
participant is given an access key.

The original intended usage is file sharing, as inspired by BitTorrent Sync,
but the protocol is layered in such a way that other applications that wish to
use it for other purposes can do so easily.

This document describes the internals of the protocol.  Those wishing to use
clearskies as a library need not understand the internals, and instead will
want to consult with the implementation guide of the clearskies library.

The core protocol specifies the essentials: the format of access keys, peer
discovery, connection encryption, and message formatting.

The [database](database.md) extension builds on the essentials to a distributed
key-value store and how to keep it synchronized.

Finally, the [directory](directory.md) extension uses both the essentials and
the database store to implement synchronization of an entire directory and its
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
for licensing information about the protocol.


Clubs
-----

When the user connects two devices, their association forms a club.  As an
example, in file sharing this would represent a shared directory, and the
members of the club would be each of the user's devices.  For IM there would be
a different club for each buddy in a user's list.


Access Levels
-------------

A single club may have multiple levels of access.  The most obvious are
read-write access and read-only access, but applications may decide to have
more or less.  A peer may have multiple levels of access to a club
simultaneously.  For example, the peer may have both read-write and read-only
access at the same time.  This allows the peer to communicate with those of
both types.

Some applications may only need a single access level.


Cryptographic Keys
------------------

When a club is first created, a 256-bit encryption key is generated for each
access level.  They must not be generated with a psuedo-random number generator
(PRNG), but instead must come from a source of cryptographically secure
numbers, such as `/dev/random` on Linux, `CryptGenRandom()` on Windows, or
`RAND_bytes()` in OpenSSL.

These keys are used as the communication key.  All of the peers in an access
level share the same communication key, but they do not reveal the access key
with those in other access levels.

A 256-bit number is generated that is associated with each key, called the key
ID.

A 128-bit random number called the peer ID is also generated.  Each peer has
its own peer ID, and the peer should use a different peer ID for each club.

Each access level also has a 2048-bit RSA key.  It can be used to digitally
sign messages, which prevents one access level from pretending to be another,
however, not all messages need to be signed.

Once generated, all keys are saved to disk.


Access Codes
------------

To grant access to a new peer, an access code is generated.  Access codes are
two cryptographically secure 64-bit numbers, which are combined for user
presentation as a single 128-bit number.

The default method of granting access uses short-lived, single-use codes.  This
is to reduce risk when sharing the code over less-secure channels, such as
SMS.

Implementations may choose to also support advanced access codes, which may be
used multiple times and persist for a longer time (even indefinitely).  More
details on multi-use codes are in the next section.

The human-sharable version of the access code is represented in base32, as
defined in [RFC 4648](http://tools.ietf.org/html/rfc4648).  Since the access
code is 16 bytes, and base32 requires lengths that are divisible by 5, a
special prefix is added to the access code.  The prefix bytes are 0x96, 0x1A,
0x2F, 0xF3.  Finally, a LUN check digit is added, using the [LUN mod N
algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), where N is 32.
The final result is a 33 character string which (due to the magic prefix) will
start with "SYNC".

When appropriate for the application, the access code should be written as a
URL.  For example, an access code for the `directory` extension would begin
with "clearskies://directory/".  This facilitates single-click opening on
platforms that support registering custom protocols.  Manual entry should
support the code both with and without the URL prefix.  The "clearskies:"
protocol should only be used when using an official extension, otherwise an
application-specific protocol would be more appropriate.

The SHA256 of the first 64 bits of the access code is known as the access ID.
It is publicly known and used to locate other peers.  The second half is used
as the SRP "password", and is not shared.

The user may opt to replace the provided access code with her own password.
The user is prompted for a "username" and "password", both of which can be
arbitrary.  (It is not essential that the username be globally unique, as long
as the combination of username and password is unique.)  The SHA256 of the
username is used for the access ID.  Note that in this case there is no access
code; the username and password would be shared with the friend instead.  (Note
that since the password is used for SRP authentication, it does not need to
have as much entropy as would otherwise be necessary.)

The core protocol has no mechanism for spreading access codes to other peers,
so the peer where the user created the code needs to be online for a new peer
to join.  The optional [code_spread](code_spread.md) extension adds access code
spreading.


Access Code UI
--------------

This section contains a user interface for access codes.  This is only a
suggestion, and is included to illustrate how access codes are intended to
work.

When the user activates the "share" button, a dialog is shown with the
following:

* The new access code, as a text field that can be copied
* A "Custom Password" button next to the access code
* A status area
* A "Cancel Access Code" button
* A "Extend Access Code" button

As soon as the dialog is shown, the access code is communicated with the
tracker (and via other means, as is explained later).  The status area will tell
the user the progress of communicating this to the tracker, switching to "ready"
once it has been communicated.

This dialog should also present a choice of access levels, when applicable.

If the user chooses the "Custom Password" button, the access code text field
should be replaced with username and password fields.

If the user chooses to "Cancel Access Code", the access code is immediately
deactivated.  The "Extend Access Code" button should present advanced options,
namely the ability to have the access code be multi-use, and an expiration for
the access code, defaulting to 24 hours.

Once the access code has been used by the friend and both computers are
connected, the status area should indicate as such.  It will no longer be
possible to cancel the access code, but it can still be extended.


Wire Protocol
-------------

The wire protocol is composed of JSON messages.  Sometimes the messages are
accompanied by binary data, which is sent as a payload after the message body,
but considered part of it.  In a similar manner, some messages are signed, and
the signature is included after the body.

Note that implementations may choose to use a different encoding other than
JSON.  This would be negotiated via the extension mechanism (explained later).
However, JSON support is required to successfully complete the negotiation, as
well as for talking with other peers.

To simplify implementations, messages are asynchronous (no immediate response
is required).  The protocol is almost entirely stateless.  For forward
compatibility, unsupported message types or extra keys should be silently
ignored.

Each message begins with a header.  The header starts with a single character
prefix.

* `m` is only JSON
* `!` is JSON with a binary attachment
* `s` is JSON with a signature
* `$` is JSON with a binary attachment and signature

Each of these types will be explained in turn.

For all message types the length of the JSON object is added after the prefix,
using ASCII characters.  The maximum size for the JSON body is 16777216 bytes.

The JSON body must start with a "{" character.  That is to say, it is not valid
to have an array, string, or other non-object as the body.

After the header the body is sent.  It may contain unnecessary whitespace,
although for efficiency purposes that isn't recommended.

The object will have a "type" member, which will identify the type of message.

For example:

```
m82{
  "type": "foo",
  "message": "Basic example message",
  "declaration": "For great justice"
}
```

A message with a binary data payload is prefixed with an exclamation point and
then the JSON body he binary payload is sent as usual.  The binary payload is
then sent in one or more chunks, ending with a zero-length binary chunk.  Each
chunk begins with its length in ASCII digits, followed by a newline, followed
by the binary data.  The size for each chunk shall be no greater than 16777216
bytes.

Note: Since large chunk sizes minimize the protocol overhead and syscall
overhead for high-speed transfers, the recommended chunk size is a megabyte.  A
memory-constrained implementation might receive a chunk that is bigger than its
maximum desired buffer size, in which case it will need to read the chunk in
multiple passes.

An example message with a binary payload might look like:

```
!44{"type":"file_data","path":"test/file.txt"}
45
This is just text, but could be binary data!
25
This is more binary data
0
```

A signed message will be prefixed with an 's' character, lower case.  The
length of the signature is added to the header, prefixed with a colon.  The
body is then sent, and then the RSA signature is given, encoded with base64.

```
s27:64{"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
```

If a message has both a binary payload and a signature, it will start with a
dollar sign.  The signature does not cover the binary data, just the body.
Here is the previous example, but with binary data added:

```
$27:64{"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
40
Another example of possibly binary data
0
```

Most messages are not signed as no security benefit would be gained from
signing them, and signatures are expensive to calculate.


64-bit Integers in JSON
-------------------

Integers in the JSON messages are usually 32-bit.  However, there are a few
places where a 64-bit integers are needed.  Javascript has a limitation as to
how much precision can be stored in an integer (since it uses floating-point
numbers everywhere), but JSON has no such limitation.  For example:

```json
{
  "path": "video-of-unusual-size.mp4",
  "size": 3762440519426216896
}
```


Datetime Values
---------------

Datetime values are represented in JSON according to ISO 8601, as strings.
Because this is a synchronization protocol, it's important to be able to
represent timestamps with nanosecond precision so that they can be
perfectly synchronized on both ends.

For example:

```json
{
  "path": "devious plan.txt",
  "mtime": "2014-03-30T12:35:29.113243778Z"
}
```


Peer Discovery
--------------

When given an access code, the access ID is used to find peers.  After
connecting the first time, the key ID is given, and this is used in place of
the access ID for subsequent connections.  Throughout these sections, the term
"access ID" will be used, but it refers to either ID, as appropriate.

Various sources of peers are supported:

 * A central tracker
 * Manual entry by the user
 * LAN broadcast
 * A distributed hash table (DHT) amongst all participants (not yet specified)

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


Tracker Protocol
----------------

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
"tracker.register".

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

The client should also register the key IDs and access IDs it knows about.  As
was explained earlier, the tracker doesn't differentiate between access IDs and
key IDs, as the distinction isn't important for peer discovery.  Registration
is done with the "tracker.register" message:

```json
{
  "type": "tracker.register",
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


LAN Broadcast
-------------

Peers are discovered on the LAN by a UDP broadcast to port 60106.  The
broadcast contains the following JSON payload:

```json
{
  "name": "ClearSkiesBroadcast",
  "version": 1,
  "id": "adf6447b553841835aaa712219e01f10486fd1003b1324e94de59f5646b060f3",
  "peer": "2a3728dca353324de4d6bfbebf2128d9",
  "myport": 40121
}
```

The ID is the key ID or access ID that the software is aware of.

The Broadcast message is versioned separately.  For example, the overall
protocol might go to version 2 but the Broadcast will stay at version 1 (if it
hasn't changed).

Broadcast should be sent on startup, when a new club is added, when a new
network connection is detected, when a new access id is created, and every
minute or so afterwards.


Distributed Hash Table
----------------------

Once connected to a peer, a global DHT can be used to find more peers.  The DHT
contains a mapping from access ID to peer address.

Future updates to protocol version 1 will include the DHT mechanism.


NAT Transversal
---------------

There is no standard port number on which to listen.

Software can attempt to use UPnP to make sure that the listening TCP port is
open to the world.

In order to bypass typical home NATs,
[STUN](http://tools.ietf.org/html/rfc5389) and
[uTP](http://www.bittorrent.org/beps/bep_0029.html) are used.  STUN is a way to
determine the public port of an open UDP socket on the NAT firewall.

On startup, the software should connect to the STUN server to determine its UDP
port.  Each software vendor should hard-code a default STUN server or list of
STUN servers.  (It is not important that all peers use the same STUN server.)

The UDP port mapping in the firewall's NAT table should be kept open by
accessing the STUN server periodically if there is no other activity on the
port.

Once the UDP port has be determined, it should be sent to the tracker using a
"tracker.connection" message.  A peer can then use this information to open a uTP
session.

Since uTP acts very similar to TCP, the TLS encryption (described later) is sent
on the uTP socket just as if it were a TCP socket.


Connection
----------

We will distinguish between client and server for the purposes of establishing
the connection.  The server is the computer that received the connection, but
isn't necessarily the computer where the club was originally created.

Clearskies uses TLS-SRP mode.  For example SRP-AES-256-CBC-SHA,
SRP-3DES-EDE-CBC-SHA, SRP-AES-128-CBC-SHA.  Note that SRP mode has [perfect
forward secrecy](http://en.wikipedia.org/wiki/Forward_secrecy), which is
critical to the security of the protocol, since the access codes are designed
to be shared over low-security transports such as SMS.

Authentication attempts should be rate limited to avoid dictionary attacks
against the password.

As part of the SRP initialization, the client communicates a "username" to the
server.  Clearskies uses the username field to ask for a desired club.  The
username is built from the string "clearskies:1:".  (The 1 in this instance
refers to the encryption establishment protocol version, and is versioned
separately from the rest of this protocol.)

The access ID or key ID is appended to the string, as hexadecimal.

The server then uses the username to see if it has a corresponding access code
or club.  If it does, it completes the connection.  The password or key is
given to the TLS library as lowercase hexadecimal.


Handshake
---------

As in the previous section, "server" refers to the server that received the
connection.

The handshake negotiates a protocol version as well as optional extensions,
such as compression.  Once the TLS session has started, the server sends a
"greeting" message that lists all of the protocol versions it supports, as well
as an optional extension list.  The protocol version is an integer.  The
extensions are strings.

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

The "peer" field is the club-specific ID explained in the cryptographic keys section.
This is used to avoid accidental loopback.  The "name" is an optional
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
a key, and after the "start" message is received a "keys" message should be
sent.  The "keys" message will be sent by the creator of the access code, which
may be the "server" or "client".

The "keys" message is required, and until it has been sent (or received),
implementations should take care not to emit or take action on other message
types.

The appropriate set of keys to include in the "keys" will be chosen according
to the access level associated with the access code when it was created.

RSA keys should be encoded as using the PEM format, and keys should be
encoded as hex.

Here is an example key exchange when there are two access levels, "read_write"
and "read_only".  RSA keys have been abbreviated for clarity:

```json
{
  "type": "core.keys",
  "access_level": "read_only",
  "keys": [
    {
      "access_level": "read_only",
      "id": "ae3d2bc89735c918f6d4a3f082924924e903f204eba949529140c41bfc8f711e",
      "key": "b699049ce1f453628117e8ba6ee75f42b699049ce1f453628117e8ba6ee75f42",
      "private_rsa": "-----BEGIN RSA PRIVATE KEY-----\nMIIJKAIBAAKCAgEA4Zu1XDLoHf...TE KEY-----\n"
    },
    {
      "access_level": "read_write",
      "public_rsa": "-----BEGIN RSA PUBLIC KEY-----\nMIIBgjAcBgoqhkiG9w0BDAEDMA4E..."
    }
  ]
}
```

The "access_level" tells the user which key it is supposed to use for its
communications in the future.

The "public_rsa" key is not required when the private key is included, since it
can be derived from the private key.

Once the keys are received, the peer should respond with a
"keys_acknowledgment" message:

```json
{
  "type": "core.keys_acknowledgment"
}
```

As soon as the acknowledgment is received, the corresponding access code
should be deactivated, unless it was a multi-use access code.

From this point forward, the connection can proceed as if it had been connected
using its key.  There is no need to reconnect and reauthenticate with the newly
received key with the same peer.


Messages
--------

Once the connection has been established messages are exchanged until one side
closes the connection.

The messages exchanged may be application specific or they might be part of
an official extension, such as the `database` or `directory`.


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

* When a multi-use access code is shared publicly, a malicious peer can answer
  accept requests for it and send its own "keys" message.  One solution would
  be to have multi-use access codes include a signature (and thus be much
  longer).

* When a multi-use access code is shared amongst a group, and then the
  originating node is taken offline, the users will unknowingly connect to each
  other instead the original node.  This is an error state but it is hard to
  detect.  The tracker can be enhanced to know the difference between those that
  have the keys associated with an access code and those that are seeking those
  keys.
