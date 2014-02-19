ClearSkies Protocol v1 Draft
============================

The ClearSkies protocol is a two-way (or multi-way) friend-to-friend protocol.
This is a special kind of peer-to-peer protocol, in that the data is shared
without the need for a central server, but it is focused on use cases where each
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

Finally, the [file_sync](file_sync.md) extension uses both the essentials and
the database store to implement.


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

When the user connects two of her devices, their association forms a club.
Clubs usually have several thousand 

A set of devices that have been associated by the user.  For file
sharing this would represent a shared directory, and the members of the club
would be each of the user's devices.  For IM there would be a different club
for each buddy in a user's list.


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
numbers, such as "/dev/random" on Linux, CryptGenRandom() on Windows, or
RAND_bytes() in OpenSSL.

These keys are used as the communication key.  All of the peers in an access
level share the same communication key, but they do not reveal the access key
with those in other access levels.

A 256-bit number is generated that is associated with each key, called the key
ID.

A 128-bit random number called the peer ID is also generated.  Each peer has
its own peer ID, and the peer should use a different peer ID for each database.

A 2048-bit RSA key should be generated for the share.  It will be used to
digitally sign messages to stop read-only shares from pretending to be
read-write shares.  Only the public portion of this key is given to read-only
shares.

A 256-bit read-only key should also be generated.  It is used as the
communication key for a read-only and read-write peer, as well as between two
read-only peers.  It also has its own 256-bit key ID.

Once generated, all keys are saved to disk.


Access Codes
------------

To grant access to a new peer, an access code is generated.  Access codes are
two cryptographically secure 64-bit numbers, which are combined for user
presentation as a single 128-bit number.

The default method of granting access uses short-lived, single-use codes.  This
is to reduce the risk of sharing the code over less-secure channels, such as
SMS.

Implementations may choose to also support advanced access codes, which may be
used multiple times and persist for a longer time (even indefinitely).  More
details on multi-use codes are in the next section.

The human-sharable version of the access code is represented as base32, as
defined in [RFC 4648](http://tools.ietf.org/html/rfc4648).  Since the access
code is 16 bytes, and base32 requires lengths that are divisible by 5, a
special prefix is added to the access code.  The prefix bytes are 0x96, 0x1A,
0x2F, 0xF3.  Finally, a LUN check digit is added, using the [LUN mod N
algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), where N is 32.
The final result is a 33 character string which (due to the magic prefix) will
start with "SYNC".

The human-readable access code should be shown with a "clearskies:" URL prefix.
This facilitates single-click opening on platforms that support registering
custom protocols.  Manual entry should support the code both with and without
the URL prefix.

The SHA256 of the first 64 bits of the access ID is known as the access ID.  It
is publicly known and used to locate other peers.  The second half is called
the "password".

The user may opt to replace the provided access code with her own password.
The user is prompted for a "username" and "password", both of which can be
arbitrary.  (It is not essential that the username be globally unique, as long
as the combination of username and password is unique.) The SHA256 of the
username is used for the access ID.

The core protocol has no mechanism for spreading access codes to other peers,
so the peer where the user created the code needs to be online for a new peer
to join.  The [code_spread](code_spread.md) extension adds access code
spreading.


Access Code UI
--------------

This section contains a user interface for access codes.  This is only a
suggestion, and is included to illustrate how access codes are intended to
work.

When the user activates the "share" button, a dialog is shown with the
following:

* A radio input for one of "read-write" and "read-only"
* The new access code, as a text field that can be copied
* A "Custom Password" button next to the access code
* A status area
* A "Cancel Access Code" button
* A "Extend Access Code" button

As soon as the dialog is shown, the access code is communicated with the
tracker (and via other means, as is explained later).  The status area will tell
the user the progress of communicating this to the tracker, switching to "ready"
once it has been communicated.

If the user chooses the "Custom Password" button, the access code text field
should be replaced with username and password fields.

If the user chooses to "Cancel Access Code", the access code is immediately
deactivated.  The "Extend Access Code" button should present advanced options,
namely the ability to have the access code be multi-use, and an expiration for
the access code, defaulting to 24 hours.

Once the access code has been used by the friend and both computers are
connected, the status area should indicate as such.  It will no longer be
possible to cancel the access code, but it can still be extended.


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

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


Tracker Protocol
----------------

The tracker is a socket service.  The main tracker service runs at
clearskies.tuxng.com on port 49200.  Only one connection to the tracker is
necessary.

Both peers should register themselves immediately with the tracker, and
re-registration should happen if the IP address or port changes.

Communication with the tracker is done with JSON messages, which are encoded
using the "wire protocol" explained in a later section.

Upon receiving a connection, the tracker will send a greeting message.  Note
that in all examples newlines have been added for clarity, but aren't allowed
in the actual wire protocol.  The "tracker.greeting" looks like this:

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
guidelines, the client will populate his own "ttl" response field, which
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

The client should also register the databases and access codes it knows about.
As was explained earlier, the tracker doesn't differentiate between access IDs
and databases IDs.  The distinction isn't important for peer discovery.
Registration is done with the "tracker.register" message:

```json
{
  "type": "tracker.register",
  "codes": [
    "1bff33a239ae76ab89f94b3e582bcf7dde5549c141db6d3bf8f37b49b08d1075": "be8b773c227f44c5110945e8254e722c",
    "2da03f6f37cee78fb13e32f4fc5a261e1c57c173087ccc787fb2c4f24d3447d9": "feeb61382cb9bbfb31ed4349727fa70c"
  ]
}
```

The "codes" field contains a hash where the key is the ID (either the access ID
or the key ID) and the value is the peer ID.

If a database or access code is added or removed on the client, it should send
a complete "tracker.register" message, including all known IDs.

The tracker combines this information into a "tracker.peers" message.  There is
a separate peers message for each database.  Subsequent messages about the same
database are meant to replace all earlier information about that database.

```json
{
  "type": "tracker.peers",
  "code": "1bff33a239ae76ab89f94b3e582bcf7dde5549c141db6d3bf8f37b49b08d1075",
  "peers": {
    "be8b773c227f44c5110945e8254e722c": ["tcp:128.1.2.3:3512", "utp:128.1.2.3:52012"]
  }
}
```

The "peers" field is a mapping from peer ID to a list of connection addresses.

As of the time of writing, only the `tcp` and `utp` psuedo-protocols are known.
Clients should ignore other protocols for future compatibility.

The client should send a "tracker.ping" message periodically.  If not sent less
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

Broadcast should be sent on startup, when a new share is added, when a new
network connection is detected, when a new access id is created, and every
minute or so afterwards.


Distributed Hash Table
----------------------

Once connected to a peer, a global DHT can be used to find more peers.  The DHT
contains a mapping from share ID to peer address.

Future updates to protocol version 1 will include the DHT mechanism.


NAT Transversal
---------------

There is no standard port number on which to listen.

Software should attempt to use UPnP to make sure that the listening TCP port is
open to the world.

In order to bypass typical home NATs,
[STUN](http://tools.ietf.org/html/rfc5389) and
[uTP](http://www.bittorrent.org/beps/bep_0029.html) are used.  STUN is a way to
determine the public port of an open UDP socket.  uTP is akin to a TCP-in-UDP
wrapper.

On startup, the software should connect to the STUN server to determine its UDP
port.  Each software vendor should hard-code a default STUN server or list of
STUN servers.

The UDP port mapping in the firewall's NAT table should be kept open by
accessing the STUN server periodically if there is no other activity on the
port.

Once the UDP port has be determined, it should be sent to the tracker using the
"utp_port" parameter.  A peer can then use this information to open a uTP
session.

Since uTP acts very similar to TCP, the TLS encryption (described later) can be
used as if it were a normal TCP connection.


Wire Protocol
-------------

The wire protocol is composed of JSON messages.  Sometimes the messages are
accompanied by binary data, which is sent as a payload after the JSON message,
but considered part of it.  In a similar manner, some JSON messages are signed,
and the signature is included after the JSON message.

Each message begins with a single character prefix:

* `_` is a message with only JSON
* `!` is a JSON message with a binary attachment
* `s` is a signed JSON message
* `$` is a signed JSON message with a binary attachment

After the prefix the JSON object should be sent, terminated by a newline.  No
newlines are allowed within the JSON representation.  (Note that JSON encodes
newlines in strings as "\n", so it is safe to remove all newline characters
from the output of a JSON library.)

Note that only JSON objects are allowed, not strings, literals, or null.

The maximum size for the JSON part of the message is 16777216 bytes.

The object will have a "type" member, which will identify the type of message.

For example:

```
_{"type":"foo","arg1":"Basic example message","arg2":"For great justice"}
```

To simplify implementations, messages are asynchronous (no immediate response
is required).  The protocol is almost entirely stateless.  For forward
compatibility, unsupported message types or extra keys should be silently
ignored.

A message with a binary data payload is also encoded in JSON, but it is
prefixed with an exclamation point and then the JSON message as usual,
including the termination newline.  After the newline, the binary payload is
sent.  It is sent in one or more chunks, ending with a zero-length binary
chunk.  Each chunk begins with its length in ASCII digits, followed by a
newline, followed by the binary data.  The size for each chunk shall be no
greater than 16777216 bytes.

Note: Since large chunk sizes minimize the protocol overhead and syscall
overhead for high-speed transfers, the recommended chunk size is a megabyte.  A
memory-constrained implementation might receive a chunk that is bigger than its
maximum desired buffer size, in which case it will need to read the chunk in
multiple passes.

An example message with a binary payload might look like:

```
!{"type":"file_data","path":"test/file.txt",...}
45
This is just text, but could be binary data!
25
This is more binary data
0
```

A signed message will be prefixed with an 's' character, lower case.  The JSON
message is then sent, and then on the next line the RSA signature is given,
encoded with base64, and followed up with a newline.  All newlines should be
removed from the base64 data so that it fits on a single line.

```
s{"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
```

If a message has both a binary payload and a signature, it will start with a
dollar sign.  The signature does not cover the binary data, just the JSON text.
Here is the previous example, but with binary data added:

```
${"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
40
Another example of possibly binary data
0
```

Most messages are not signed (as no security benefit would be gained from
signing them, and signatures are expensive to calculate).

As a rule, the receiver of file data should always be the one to request it.
It should never be pushed unrequested.  This allows streaming content and do
partial copies, as will be explained in later sections.


Connection
----------

We will distinguish between client and server for the purposes of establishing
the connection.  The server is the computer that received the connection, but
isn't necessarily the computer where the share was originally created.

Clearskies uses TLS-SRP mode.  For example SRP-AES-256-CBC-SHA,
SRP-3DES-EDE-CBC-SHA, SRP-AES-128-CBC-SHA.  Note that SRP mode has [perfect
forward secrecy](http://en.wikipedia.org/wiki/Forward_secrecy), which is
critical to the security of the protocol, since the access codes are designed
to be shared over low-security transports such as SMS.

Authentication attempts should be rate limited to avoid dictionary attacks
against the password.

As part of the SRP initialization, the client communicates a "username" to the
server.  Clearskies uses the username field to ask for a desired share.  The
username is built from the string "clearskies:1:".  (The 1 in this instance
refers to the encryption establishment protocol version, and is versioned
separately from the rest of this protocol.)

The access ID or key ID is appended to the string, as hexadecimal.

The server then uses the username to see if it has a corresponding access code
or share.  If it does, it completes the connection.  The password or key is
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

What follows is an example greeting (newlines have been added for legibility,
but they would not be legal to send over the wire):

```json
{
  "type": "greeting",
  "software": "bitbox 0.1",
  "name": "Jaren's Laptop",
  "protocol": [1],
  "extensions": ["gzip", "rsync"],
  "peer": "77b8065588ec32f95f598e93db6672ac"
}
```

The "peer" field is the share-specific ID explained in the tracker section.
This is used to avoid accidental loopback.  The "name" is an optional
human-friendly identifier, if set by the user.

The client will examine the greeting and decide which protocol version and
extensions it has in common with the server.  It will then respond with a start
message, which asks for a particular share by the share's public ID.  (See the
encryption section for an explanation of public IDs.)  Here is an example
"start" message:

```json
{
  "type": "start",
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
to the access level that was chosen when the access code was created.

RSA keys should be encoded as using the PEM format, and keys should be
encoded as hex.

Here is an example key exchange for a read-only peer.  RSA keys have been
abbreviated for clarity:

```json
{
  "type": "keys",
  "access": "read_only",
  "read_only": {
    "id": "ae3d2bc89735c918f6d4a3f082924924e903f204eba949529140c41bfc8f711e",
    "key": "b699049ce1f453628117e8ba6ee75f42b699049ce1f453628117e8ba6ee75f42",
    "private_rsa": "-----BEGIN RSA PRIVATE KEY-----\nMIIJKAIBAAKCAgEA4Zu1XDLoHf...TE KEY-----\n"
  },
  "read_write": {
    "public_rsa": "-----BEGIN RSA PUBLIC KEY-----\nMIIBgjAcBgoqhkiG9w0BDAEDMA4E..."
  }
}
```

The "access" key is one of "read_write" or "read_only", and tells the receiver
what access level it is allowed to participate at.

The "public_rsa" key is not required when the private key is included, since it
can be derived from the private key.

Once the keys are received, the peer should respond with a
"keys_acknowledgment" message:

```json
{
  "type": "keys_acknowledgment"
}
```

As soon as the acknowledgment is received, the corresponding access code
should be deactivated, unless it was a multi-use access code.

The rest of the connection can then proceed as normal.


File Tree Database
------------------

Each read-write peer needs to keep a persistent database of all the files in a
share.  The database has a "revision" attribute, which is a 64-bit unsigned
integer that is incremented any time the peer writes makes a change to a
record.  It should not be changed when writing changes coming from other peers.
The empty database should have revision 0.

The following fields are tracked for each file:

 * "path" - relative path (without a leading slash)
 * "deleted" - boolean set true once file is deleted
 * "size" - file size in bytes
 * "sha256" - SHA256 of file contents
 * "utime" - update time

If a file is deleted, the deleted boolean is set to true.  Any fields listed
after the deleted field in the list above can be blanked.  The entry for the
deleted file will persist indefinitely in the database.  An explanation for the
necessity of this behavior is in the later section called "Deleted Files".

The "mtime" is the number of seconds since the unix epoch (normally called a
unix timestamp) since the file contents were last modified.  This should
include the number of nanoseconds, if tracked by the system.  Note that a
double-precision floating point number is not precise enough to store all nine
digits after the decimal point, so it may need to be tracked as two separate
fields internally.

The "update time" is the time that the file was last changed, as a unix
timestamp.  On first scan, this is the time the scan discovered the file.  This
is different than the mtime because the mtime can go back in time.

The unix mode bits represent the user, group, and other access modes for the
file.  This is represented as an octal number, for example "0755".

The SHA256 of the file contents should be cached in a local database for
performance reasons, and should be updated with the file size or mtime changes.


Windows Compatibility
---------------------

Software running on an operating system that doesn't support all the characters
that unix supports in a filename, such as Microsoft Windows, must ensure
filenames with unsupported characters are handled properly, such as '\', '/',
':', '*', '?', '"', '<', '>', '|'.  The path used on disk can use URL encoding
for these characters, that is to say the percent character followed by two hex
digits.  The software should then keep an additional field that tracks the
original file path, and continue to interact with other peers as if that were
the file name on disk.

In a similar manner, Windows software should preserve unix mode bits.  A
read-only file in unix can be mapped to the read-only attribute in Windows.
Files that originate on Windows should be mapped to mode '0600' by default.

Windows clients will also need to transparently handle multiple files with the
same name but different case, such as Secret.txt and secret.txt.

Finally, Windows should always use '/' as a directory separator when
communicating with other peers.

Said another way, software for Windows should pretend to be a peer running unix.


First Sync
----------

When a user types in an access code and picks a non-empty directory in which to
store the share, the software should warn the user that any directory contents
will be erased.

The directory contents shouldn't be removed immediately, because they may be
the right file contents that were copied manually, and can be used to sync
quickly.

The existing contents of the directory should not be merged, either.  However,
care should be taken so that the user can start work before the directory has
been completely scanned, since hashing existing files can take quite a while.
The scan should capture the entire list of files before hashing any of them,
which will allow "utime" tracking to work like normal.


Read-Write Manifests
--------------------

Once an encrypted connection is established, the peers usually ask for each
other's file tree listing.  This step is not required in all cases, for example
if two peers have multiple open connections with each other they wouldn't share
manifests on all of them.

Each access level has its own way of creating file listings.  The file listing
and a signature are together called a manifest.

A read-write peer will generate a new manifest whenever requested by a peer
from the contents of its database.  It contains the entire contents of the
database, including the database "revision" number.  The file entries should
be sorted by path.  Its own peer_id is also included.  The entire manifest will
be signed (using the key-signing mechanism explained in the "Wire Protocol"
section) except when being sent to other read-write peers.

Here is an example manifest JSON as would be sent over the wire (the signature
is not shown):

```json
{
  "type": "manifest",
  "peer": "489d80c2f2aba1ff3c7530d0768f5642",
  "revision": 379,
  "files": [
    {
      "path": "photos/img1.jpg",
      "utime": 1379220476.4512,
      "size": 2387629
      "mtime": [1379220393, 323518242],
      "mode": "0664",
      "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1"
    },
    {
      "path": "photos/img2.jpg",
      "utime": 1379220468.2303,
      "size": 6293123
      "mtime": [1379100421,421442491],
      "mode": "0600",
      "sha256": "64578d0dc44b088b030ee4b258de316b5cb07fdf42b8d40050fe2635659303ed"
    },
    {
      "path": "photos/img3.jpg",
      "utime": 1379489028.4324,
      "deleted": true
    }
  ]
}
```

The contents of the shared directory can diverge between two read-write peers,
and stay diverged for a long time.  (Most notably, this happens when a peer
opts not to sync some files, as is explained in the "Subtree Copy" section.)
For this reason, each read-write peer has its own manifest.

To request a manifest, a "get_manifest" message is sent.  The message may
optionally contain the last-synced "revision" of the peer's database.
(Read-write peers are never required to store manifests.)

```json
{
  "type": "get_manifest",
  "revision": 379
}
```

If the manifest revision matches the current database number, the peer will
respond with a "manifest_current" message.

```json
{
  "type": "manifest_current"
}
```

If the "get_manifest" request didn't include a "revision" field, or the
manifest revision number is not current, the peer should respond with the full
"manifest" message, as explained above.

A peer may elect not to request a manifest, and may also elect to ignore the
"get_manifest" message.

Note: By default, read-only peers should cache read-write peers they receive,
so that they can retrieve files from other read-only peers even when no
read-write peers are present.  The "read_only_manifest" extension adds a more
robust way to get metadata from a read-only peer.


Large Manifests
---------------

Shares with many files will create JSON messages that are larger than the spec
allows (16777216 bytes).  For that reason, manifests should be split into
multiple "manifest" messages.  A `"partial":true` member should be included on
all but the final manifest message.  Only the files in the "files" array should
differ between the messages, in other words, both the "peer" and "revision"
keys should be present in the future messages

Care should be taken to have an atomic view of the manifest.  In other words,
if a change is made to the tree while a set of manifest messages are being sent
to a peer, that change shouldn't appear in any of the partial manifest
messages.


Tree Merge Algorithm
--------------------

When two read-write peers are connected, they merge their manifests together in
memory on a file-by-file basis in what is called tree merging.  A tree merge
compares entry and the one with the latest "utime" field wins.  If the "utime"
matches, the file with the latest "mtime" wins.  If the "mtime" matches, the
largest file wins.  If the sizes match, the file with the smallest "sha256"
wins.

This merged tree is remembered and is used to decide which files need to be
retrieved from the peer.  Information about the new files shouldn't be applied
to the database until after the files have been retrieved.


Retrieving Files
----------------

Files should be asked for in a random order so that if many peers are involved
with the share, the files spread as quickly as possible.

In this section, "client" and "server" are used to denote the peer receiving
and peer sending the file, respectively.

When the client wishes to retrieve the contents of a file, it sends the
following message:

```json
{
  "type": "get",
  "path": "photos/img1.jpg",
  "range": [0, 100000]
}
```

The "range" parameter is optional and allows the client to request only certain
bytes from the file.  The first number is the start byte, and the second number
is the number of bytes.

The server responds with the file data.  This will have a binary payload of the
file contents (encoding of the binary payload is explained in the "Wire
Protocol" section):

```
!{"type": "file_data","path":"photos/img1.jpg", ... }
100000
JFIF.123l;jkasaSDFasdfs...
0
```

A better look at the JSON above:

```json
{
  "type": "file_data",
  "path": "photos/img1.jpg",
  "range": [0, 100000]
}
```

The receiver should write to a temporary file, perhaps with a ".!clearsky"
extension, until it has been fully received.  The SHA256 hash should be verified
before replacing the original file.  On unix systems, rename() should be used
to overwrite the original file so that it is done atomically.

A check should be done on the destination file before replacing it to see if it
has changed.  If so, the usual conflict resolution rules should be followed as
explained earlier.

Remember that the protocol is asynchronous, so software may issue multiple
"get" requests in order to receive pipelined responses.  Pipelining will cause
a large speedup when small files are involved and latency is high.

If the client wants to receive multiple files at once, it should open up another
connection to the peer.

Software may choose to respond to multiple "get" requests out of order.


File Change Notification
------------------------

Files should be monitored for changes on read-write shares.  This can be done
with OS hooks, or if that is not possible, the directory can be rescanned
periodically.

If it appears a file has changed, the hash should be recomputed.  If it doesn't
match, the mtime should be checked one last time to make sure that the file
hasn't been written to while the hash was being computed.  Peers should then be
notified of the change.

Change notifications should only be sent on connections when a "manifest" or
"manifest_current" message have already been sent on that connection (which
would have been in response to a "get_manifest" message.)

Change notifications are signed messages except when sent to other read-write
peers.

Read-only peers should append the change notification, and its signature, to
the stored manifest that it's keeping for each read-write peer.  (Each piece
should have a newline after it.)

The "utime" for file changes is the current time if OS hooks are being used.
If it is detected by a file scan, then the mtime should be used if it is before
the previous time the file was scanned.  Otherwise the previous scan time
should be used.  Deleted files should always use the previous scan time as the
"utime".  (The start time of the previous scan can be used instead of the
previous scan time for the file in question, if desired.)

Each change contains the manifest "revision" number.

Notification of a new or changed file looks like this:

```json
{
  "type": "update",
  "revision": 400,
  "file": {
    "path": "photos/img1.jpg",
    "utime": 1379220476,
    "size": 2387629,
    "mtime": [1379220393, 194518242],
    "mode": "0664",
    "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1"
  }
}
```

Note that the "file" field makes it possible to differentiate between metadata
about the file and extensions to the "replace" message itself.

Notification of a deleted file looks like this:

```json
{
  "type": "update",
  "revision": 401,
  "file": {
    "path": "photos/img3.jpg",
    "utime": 1379224548,
    "deleted": true
  }
}
```

Notification of a moved file looks like this:

```json
{
  "type": "move",
  "revision": 402,
  "source": "photos/img5.jpg",
  "destination": {
    "path": "photos/img1.jpg",
    "utime": 1379220476.512824,
    "size": 2387629
    "mtime": [1379220393, 132518242],
    "mode": "0664",
    "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1"
  }
}
```

Moves should internally be treated as a "delete" and a "replace".  That is to
say, an entry for the old path should be kept in the database.

It is the job of the detector to notice moved files (by SHA256 hash).  In order
to accomplish this, a rescan should look at the entire batch of changes before
sending them to the other peer.  If file change notification support by the OS
is present, the software may want to delay outgoing changes for a few seconds
to ensure that a delete wasn't really a move.

File change notifications should be relayed to other peers once the file has
been successfully retrieved, including back to the originator of the change.


Deleted Files
-------------

Special care is needed with deleted files to ensure that "ghost" copies of
deleted files don't reappear unexpectedly.

The solution chosen by ClearSkies is to track the path of deleted files
indefinitely.  Consider the following example of what would happen if these
files were not tracked:

1. Peers A, B, and C know about a file.
2. Only peers A and B are running.
3. The file is deleted on A.
4. B also deletes its file.
5. A disconnects.
6. C connects to B.  Since C has the file and B does not, the file reappears on B.
7. A reconnects to B.  The file reappears on A.



Keep-alive
---------

A message of type "ping" should be sent by each peer occasionally to keep
connections from being dropped:

```json
{"type":"ping","timeout":60}
```

The "timeout" specified is the absolute minimum amount of time to wait for the
peer to send another ping before dropping the connection.  A peer should adjust
its own timeout to be same as the timeout of its peer if the peer's timeout is
greater, that way software on mobile devices can adjust for battery life and
network conditions.


Archival
--------

When files are changed or deleted on one peer, the other peer may opt to save
copies in an archival directory.  If an archive is kept, it is recommended that
the SHA256 of these files is still tracked so that they can be used for
deduplication in the future.

Software could limit the archive to a certain size, or offer a friendly way to
navigate through the archive.


Deduplication
-------------

The SHA256 hash should be used to avoid requesting duplicate files when already
present somewhere else in the local share.  Instead, a copy of the local file
should be used.


Ignoring Files
--------------

Software may choose to allow the user to ignore files with certain extensions
or that match a pattern.  These files won't be sent to peers.


Subtree Copy
------------

Software may support the ability to only sync a single subdirectory of a share.
This does not require peer cooperation or knowledge.

In order to make this efficient, the software should keep a cached copy of the
peer's manifest so that the peer doesn't need to send a complete copy of the
tree on every connection.


Partial Copy
------------

Software may opt to implement the ability to not sync some folders or files
from the peer.

The software may let the user specify extensions not to sync, give them the
ability to match patterns, or give them a GUI to pick files or folders to
avoid.

As with partial copies, the client should keep a cached copy of the peer
manifests for efficiency reasons.


Streaming
---------

Software may optionally support not keeping a local copy of the files at all,
and instead stream the file contents live, perhaps as a FUSE filesystem,
directly integrated into a music player as a plugin, or on a mobile device.
The client can keep a small local cache of commonly used files.

It should also be possible to stream writes back to the server.  The client
would need to keep a buffer of outgoing files on local storage while waiting
for the server.

As with subtree copies and partial copies the client should keep a cached copy
of the peer's manifest for efficiency reasons.


Computer Resources
------------------

This section is a set of recommendations for implementors and are not part of
the protocol.

Software should attempt to resume partial file transfers.

The period between directory scans should be a multiple of the time it takes to
do rescans.  For example, scans may be done every ten minutes, unless it takes
more than a minute to run a scan, in which case the scan won't be run until ten
times the time it took to run the scan.  This guarantees that scanning overhead
will be less than 10% of system load.

The software should run with low priority.  It should let the user pause sync
activity.

The software should give battery users the option to not sync while on battery.

Software should implement rate limiting, as sync is intended as something that
will run in the background without interfering with normal usage.

Software should also consider that many ISPs limit the amount of bandwidth that
can be consumed in a month, and support for limits that can be used to ensure
that the cap isn't exceeded.

The software should debounce file changes so that it can stop syncing a file
that is changing too frequently.

The software should not lock files for reading while syncing them so that the
user can continue normal operation.

The software should give the users a rough estimate of the amount of time
remaining to sync a share so that the user can manually transfer files through
sneakernet if necessary.

Users may be relying on the software to back up important files.  The software
may want to alert the user if the share has not synced with its peer after a
certain threshold (perhaps defaulting to a week).

Software can rescan files from time-to-time to detect files that cannot be read
from disk or that have become corrupted, and replace them with good copies from
other peers.

Software should detect when a share is on a removable device, and put the share
in a soft error state when the device is not present.  (As opposed to deleting
all the files in the share on the peers.)

Software may choose to create read-only directories, and read-only files, in
read-only mode, so that a user doesn't make changes that will be immediately
overwritten.  It could detect changes in the read-only directory and warn the
user that they will not be saved.

Software should rate limit authentication attempts to avoid key guessing.

While it is not the designed use case of this protocol, some shares may have
hundreds or thousands of peers.  In this case, it is recommended that
connections only be made to a few dozen of them, chosen at random.


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
