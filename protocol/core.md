ClearSkies Protocol v1 Draft
=========================

The ClearSkies protocol is a two-way (or multi-way) directory synchronization
protocol, inspired by BitTorrent Sync.  It is a friend-to-friend protocol as
opposed to a peer-to-peer protocol, meaning that files are only shared with
computers that are given an access key -- never anonymously.


Draft Status
------------

This is a draft of the version 1 protocol and is subject to changes as the need
arises.  The final version will replace this document.

If something in this document is ambiguous, the reference implementation may
be illuminating.

Comments and suggestions are welcome.


License
-------

This protocol documentation is in the public domain.  Private implementations
of this protocol are not constrained by the terms of the GPL v3.


Access Levels
-------------

The protocol supports peers of three types:

1. Read-write.  These peers can change or delete any file, and create new
   files.

2. Read-only.  These peers can read all files, but cannot change them.

3. Untrusted.  These peers receive the files encrypted.  This is intended for
   backups, but could also be used by a service provider to provide cloud
   services.

A share can have any number of all three peer types.

All peers can spread data to any other peers.  Said another way, a read-only
peer does not need to get the data directly from a read-write peer, but can
receive it from another read-only peer or even an untrusted peer.  Digital
signatures are used to ensure that there is no foul play.


Cryptographic Keys
------------------

When a share is first created, a 128-bit encryption key is generated.  This
must not be generated with a psuedo-random number generator (PRNG), but
must come from a source of cryptographically secure numbers, such as
"/dev/random" on Linux, CryptGenRandom() on Windows, or RAND_bytes() in
OpenSSL.

This key is used as the communication key.  All of the read-write peers posses
it, but they do not give it to read-only peers.  It will be referred to as the
read-write PSK.  Details of communication encryption will come later.

A 4096-bit RSA key should be generated for the share.  It will be used to
digitally sign some messages to stop read-only shares from pretending to be
read-write shares.

The original read-write peer should also create some keys to support read-only
peers.  The read-only PSK and read-only RSA key should be of the same size as
the read-write keys.

Two more 128-bit keys should also be generated.  These are the read-only PSK
and the read-only RSA key.

A final 128-bit key should be generated.  This is the untrusted key.

Once generated, all keys are saved to disk.

The SHA256 of the read-write PSK is called the share ID.  This is used to
locate other peers of the share.


Passphrase
----------

Instead of generating the master key, the user may enter a custom passphrase.
The SHA256 algorithm is applied twenty million times to generate the 256-bit
encryption key, meaning SHA256(SHA256(...(SHA256(SHA256("secret")))...)).  Due
to the nature of the secret sharing mechanism, it is not possible to use a salt
as is done with with PBKDF2, but someone possessing the key would already have
access to the files themselves, making the passphrase less valuable.

The purpose of this passphrase is backup recovery.


Access Codes
------------

To grant access to a new peer, an access code is generated.  Access codes are
random 128-bit numbers that are regenerated each time an access code is needed.

The default method of granting access sharing uses codes that are short-lived,
single-use code.  This is to reduce the risk of sharing the code over
less-secure channels, such as SMS.

Implementations may choose to also support advanced access codes, which may be
multi-use and persist for a longer time (perhaps indefinitely, at the user's
option).

The human-sharable version of the access code is written with a prefix of
'CLEARSKIES', followed by the access code itself.  The access code should be
represented as base32, as defined in [RFC
4648](http://tools.ietf.org/html/rfc4648), with the equals-sign padding at the
end removed.  Finally, a LUN check digit is added, using the [LUN mod N
algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), where N is 32.

The 128-bit number is run through SHA256 to get an access ID.  This is used
to locate other peers.

The user may opt to replace the provided access code with a passphrase before
sending it.  If this is done, the SHA256 of the passphrase should be taken
one million times.  This 256-bit hash is considered the access code, and its
SHA256 is the access ID.


Access code UI
--------------

What follows is only a suggested user interface.

When the user activates the "share" button a dialog is shown with the following:

* A radio input for one of "read-write", "read-only", and "untrusted"
* The new access code, as a text field that can be edited
* A status area
* A "Cancel access code" button
* A "Extend access code" button

If the user chooses to "Cancel access code", the access code should no longer
unlock the share.  The "Extend access code" button should present advanced
options, and perhaps default to 24 hours.

Once the access code has used by the friend and both computers are connected,
the status area should indicate as such.  It will no longer be possible to
cancel the access code, but it can still be extended.


Peer discovery
--------------

When first given an access code, the access ID is used to find peers.  If the
share ID is known, it is used instead.

Various sources of peers are supported:

 * A central tracker
 * Manual entry by the user
 * LAN broadcast
 * A distributed hash table (DHT) amongst all participants
 * Previously valid addresses for the share

Each of these methods can be disabled by the user on a per-share basis and
implementations can elect not to implement them at their discretion.

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


Tracker protocol
----------------

The tracker is an HTTP or HTTPS service.  The main tracker service runs at
tracker.example.com (to be determined).

Software should come with the main tracker service address built-in, and may
optionally support additional tracker addresses.  Finally, the user should be
allowed to customize the tracker list.

Note that both peers should register themselves immediately with the tracker,
and re-registration should happen if the local IP address changes, or after the
TTL period has expired of the registration.

A peer ID is an 128-bit random ID that should be generated when the share is
first created, and is unique to each peer.

The ID and listening port are used to make a GET request to the tracker
(whitespace has been added for clarity):

    http://tracker.example.com/clearskies/track?myport=30020
         &peer=e139d99b48e6d6ca033195a39eb8d9a1
         &id=00df70a2ec5a8bfe4e68d00aba75792b839ea84aa70aa1dd4dfe0e7116e253cc

The response must have the content-type of application/json and will have a
JSON body like the following (whitespace has been added for clarity):

```json
{
   "your_ip": "32.169.0.1",
   "others": ["be8b773c227f44c5110945e8254e722c@128.1.2.3:40321"],
   "ttl": 300
}
```

The TTL is a number of seconds until the client should register again.

The "others" key contains a list of all other peers that have registered for
this ID, with the client's "peer ID", followed by an @ sign, and then
peer's IP address.  The IP address can be an IPV4 address, or an IPV6 address
surrounded in square brackets.


Fast tracker extension
----------------------

The fast tracker service is an extension to the tracker protocol that avoids
the need for polling.  The official tracker supports this extension.

An additional parameter, "fast_track", is set to "1" and the HTTP server will
not close the connection, instead sending new JSON messages whenever a new peer
is discovered.  This is sometimes called HTTP push or HTTP streaming.

If the tracker does not support fast-track responses, it will just send a
normal response and close the connection.

The response will contain the first JSON message as previously specified, with
an additional key, "timeout", with an integer value.  If the connection is idle
for more than "timeout" seconds, the client should consider the connection dead
and open a new one.

Some messages will be empty and used as a ping message to keep the connection
alive.

A complete response might look like:

```json
{"success":true,"your_ip":"192.169.0.1","others":["a958e1b202a3a432caeeb66616b1305f@128.1.2.3:40321"],"ttl":3600,"timeout":120}
{}
{}
{"others":["a958e1b202a3a432caeeb66616b1305f@128.1.2.3:40321","2a3728dca353324de4d6bfbebf2128d9@99.1.2.4:41234"]}
{}
{}
```


LAN Broadcast
-------------

Peers are discovered on the LAN by a UDP broadcast to port 60106.  The
broadcast contains the following JSON payload (whitespace has been added for
legibility):

```json
{
  "name": "ClearSkiesBroadcast",
  "version": 1,
  "ids": ["22596363b3de40b06f981fb85d82312e8c0ed511"],
  "peer": "2a3728dca353324de4d6bfbebf2128d9",
  "myport": 40121
}
```

The IDs are the share IDs or access IDs that the software is aware of.

Broadcast should be sent on startup, when a new share is added, when a new
network connection is detected, when a new access id is created, and every
minute or so afterwards.


Distributed Hash Table
----------------------

Once connected to a peer, a global DHT can be used to find more peers.  The DHT
contains a mapping from share ID to peer address.

Future updates to protocol version 1 will include the DHT mechanism.


Firewall transversal
--------------------

There is no standard port number on which to listen.

Software should use UPnP to make sure that its listening port is open to the
world.

Future updates to the protocol will include a method for communicating over
UDP.


Wire protocol
-------------

The wire protocol is composed of JSON messages.  Some message types include
binary data, which is sent as a binary payload after the JSON message, but
considered part of it.  In a similar manner, some JSON messages are signed, and
the signature is included after the JSON message.

A normal message is a JSON object on a single line, followed by a newline.  No
newlines are allowed within the JSON representation.  (Note that JSON encodes
newlines in strings as "\n", so there is no need to worry about cleaning out
newlines within the object.)

The object will have a "type" key, which will identify the type of message.

For example:

```json
{"type":"foo","arg1":"Basic example message","arg2":"For great justice"}
```

To simplify implementations, messages are asynchronous (no immediate response
is required).  The protocol is almost entirely stateless.  For forward
compatibility, unsupported message types or extra keys are silently ignored.

A message with a binary data payload is also encoded in JSON, but it is
prefixed an exclamation point, followed by the size (in bytes) of the binary
payload, followed by an exclamation point, and then the JSON message as usual,
including the termination newline.  After the newline, the entire binary
payload will be sent.

For example:

```
!44!{"type":"file_data","path":"test/file.txt",...}
This is just text, but could be binary data!
```

A signed message will be prefixed with a $.  The JSON message is then sent, and
then on the next line the RSA signature is given, encoded with base64, and
followed up with a newline.  The base64 data should not include any newlines.

```
${"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
```

If a message has both a binary payload and a signature, it will start with a
dollar sign and then an exclamation mark, in that order.  The signature does
not cover the binary data, just the JSON text.  Here is the previous
example, but with binary data added:

```
$!39!{"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
Another example of possibly binary data
```

Most messages are not signed (as no security benefit would be gained from
signing them).

As a rule, the receiver of file data should always be the one to request it.
It should never be pushed unrequested.  This allows streaming content and do
partial copies, as will be explained in later sections.

If a message does not begin with a, '$', '{' or an '!', it should be ignored,
for forwards compatibility.


Handshake
---------

We will distinguish between client and server for the purposes of the
handshake.  The server is the computer that received the connection, but isn't
necessarily the computer where the share was originally created.  In fact, the
server can be the computer that only has an access code so far.

The handshake negotiates a protocol version as well as optional features, such
as compression.  When a connection is opened, the server sends a "greeting"
that lists all the protocol versions it supports, as well as an optional
feature list.  The protocol version is an integer.  The features are strings.

The current protocol version is 1.  Future improvements to version 1 will be
done in a backwards compatible way.  Version 2 will not be compatible with
version 1.

Officially supported features will be documented here.  Unofficial features
should start with a period and then a unique prefix (similar to Java).
Unofficial messages should prefix the "type" key with its unique prefix.

What follows is an example greeting.  (Newlines have been added for legibility,
but they would not be legal to send over the wire.)

```json
{
  "type": "greeting",
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
  "type": "start",
  "software": "beetlebox 0.3.7",
  "protocol": 1,
  "features": [],
  "id": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1",
  "access": "read_write",
  "peer": "6f5902ac237024bdd0c176cb93063dc4"
}
```

The ID is the share ID or access ID.

The "access" level is one of "read_write", "read_only", "untrusted", or
"unknown".  When a peer only has an access code, its access level is "unknown".

The "peer" field is the ID explained in the tracker section.  This is used
to avoid accidental loopback.

If the server does not recognize the id it will send back a "cannot_start"
message, and close the connection:

```json
{
  "type": "cannot_start"
}
```

Otherwise it will send back a "starttls" message:

```json
{
  "type": "starttls",
  "peer": "77b8065588ec32f95f598e93db6672ac",
  "access": "read_only"
}
```

The "access" in the starttls response is the highest access level that both
peers have.

For example, if the client is read-write and the server is read-only, the
access is "read_only".  If one of the peers only has an access code, it is
"unknown".

The corresponding key or access code is then used by both peers as a pre-shared
key (PSK) for TLS.

The connection is encrypted with with TLS_DHE_PSK_WITH_AES_128_CBC_SHA
from [RFC 4279](http://tools.ietf.org/html/rfc4279).  Protocol version 1 only
supports this mode, not any other modes.  (It has perfect forward secrecy, which
is critical for key exchange.)

Once the server sends the "starttls" message, it upgrades the unencrypted
connection to a TLS connection.  Likewise, when the client receives the
"starttls" message from the server, it upgrades its socket connection.

Both peers send a message through the connection divulging more information
about themselves for diagnostic purposes:

```json
{
  "type": "identity",
  "name": "Jaren's Laptop",
  "time": 1379225084
}
```

The "name" field is a human-friendly identifier for the computer.

The "time" is a unix timestamp of the current time.  This is sent because the
conflict resolution relies on an accurate time.  If the difference between the
times is too great, software may notify the user, and/or attempt to account for
the difference in conflict resolution algorithm, at the software's discretion.
The software may also refuse to participate.


Key exchange
------------

If the access level negotiated in the handshake is "unknown", then the keys
will now be given to the new peer.

The appropriate set of keys will be chosen according to the access level that
was chosen when the access code was created.

RSA keys should be encoded as PEM files, and the PSKs should be encoded as hex.

Keys that the peer should not have should also be sent, encrypted with the
read-write PSK.  This is necessary so that the master passphrase can be used to
create a read-write peer.

The encryption should be done with AES128 in CBC mode.  The first 16 bytes in
the file should be the initialization vector (IV), which should be chosen at
random for each file.  This is followed by the encrypted data.  The entire file
is then base64 encoded.

Here is an example key exchange for a read-only node.  RSA keys have been
abbreviated for clarity:

```json
{
  "type": "keys",
  "access": "read_only",
  "untrusted": {
    "psk": FIXME,
    "rsa": FIXME
  },
  "read_only": {
    "psk": "b699049ce1f453628117e8ba6ee75f42",
    "rsa": "== BEGIN RSA FIXME ===\nADFASF..."
  },
  "encrypted_read_write": {
    "rsa": FIXME
  }
}
```

If the keys given are encrypted, the access level should be prefixed with
"encrypted_".  Note that the read-write PSK is not included in this exchange
since it would be encrypted with itself.

As soon as the keys have been sent the corresponding access code should be
deactivated, unless it was a multi-use access code.

The connection is then closed, and the new share ID is used with the tracker
to reconnect.


File tree database
------------------

Each read-write peer needs to keep a persistent database of all the files in a
share.  The database has a "version" attribute, which is a double-precision
floating-point unix timestamp representing the last time anything has changed
in the database.

The following fields are tracked for each file:

 * "path" - relative path (without a leading slash)
 * "utime" - update time
 * "id" - a 128-bit file ID, chosen at random, stored as hex
 * "deleted" - deleted boolean
 * "size" - file size in bytes
 * "mtime" - last modified time as a unix timestamp
 * "mode" - unix mode bits
 * "sha256" - SHA256 of file contents
 * "aes128" - a 128-bit encryption key, stored as hex

If a file is deleted, the deleted boolean is set to true.  Any fields listed
after the deleted field in the list above can be blanked.  The entry for the
deleted file will persist indefinitely in the database.  An explanation for
this behavior is in a later section devoted to this topic.

The "mtime" is the integer number of seconds since the unix epoch (normally
called a unix timestamp) since the file contents were last modified.

The "update time" is the time that the file was last changed, as a unix
timestamp.  On first scan, this is the time the scan discovered the file.

The unix mode bits represent the user, group, and other access modes for the
file.  This is represented as an octal number, for example "0755".

The SHA256 of the file contents should be cached in a local database for
performance reasons, and should be updated with the file size or mtime changes.

The file ID is used for untrusted peers.  It should be updated when the SHA256
changes.

The aes128 encryption key is only used when sending the file to untrusted
peers.  It is predetermined so that all peers agree on how to encrypt the file.
It should be changed whenever the SHA256 changes.

FIXME: The file id and aes128 should match for all files with the same SHA256
so that we get deduplication to trusted peers.


Windows compatibility
---------------------

Software running on an operating system that doesn't support all the characters
that unix supports in a filename, such as Microsoft Windows, must ensure
filenames with unsupported characters are handled properly, such as '\', '/',
':', '*', '?', '"', '<', '>', '|'.  The path used on disk can use URL encoding
for these characters, that is to say the percent character, followed by two hex
digits.  The software should then keep an additional field that tracks the
original file path, and continue to interact with other peers as if that were
the file name on disk.

In a similar manner, Windows software should preserve unix mode bits.  A
read-only file in unix can be mapped to the read-only attribute in Windows.
Files that originate on Windows should be mapped to mode '0600' by default.

Finally, Windows should always use '/' as a directory separator when
communicating with other peers.

Said another way, software for Windows should pretend to be a peer running unix.


Read-write manifests
--------------------

Once an encrypted connection is established, the peers usually ask for each
other's file tree listing.

Each access level has its own way of creating file listings.  The file listing
and a signature are together called a manifest.

A read-write peer will generate a new manifest whenever requested by a peer
from the contents of its database.  It contains the entire contents of the
database, including the database "version" timestamp.  The file entries should
be sorted by path.  Its own peer_id is also included.  The entire manifest will be
signed (using the key-signing mechanism explained earlier) when sent to other
peers.

Here is an example manifest JSON as would be sent over the wire.  The signature
is not shown.

```json
{
  "type": "manifest",
  "peer": "489d80c2f2aba1ff3c7530d0768f5642",
  "version": 1379487751.581837,
  "files": [
    {
      "path": "photos/img1.jpg",
      "utime": 1379220476,
      "size": 2387629
      "mtime": 1379220393.518242,
      "mode": "0664",
      "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1",
      "id": "8adbd1cdaa0200747f6f2551ce2e1244",
      "aes128": "5121f93b5b2fe518fd2b1d33136ddc33",
    },
    {
      "path": "photos/img2.jpg",
      "utime": 1379220468,
      "size": 6293123
      "mtime": 1379100421.442491,
      "mode": "0600",
      "sha256": "64578d0dc44b088b030ee4b258de316b5cb07fdf42b8d40050fe2635659303ed",
      "id": "ade5f6098c8d99bd6b5472e51c64e09a",
      "aes128": "2304bde0b070a0d3ca65c78127f2f189"
    },
    {
      "path": "photos/img3.jpg",
      "utime": 1379489028,
      "deleted": true
      "id": "ccccf6098c8d99bd6b5472e51c64e0aa",
    }
  ]
}
```

The contents of the shared directory can diverge between two read-write peers,
and stay diverged for a long time.  (Most notably, this happens when a peer
opts not to sync some files, as in "subtree copies", explained later.)  For
this reason, each read-write peer has its own manifest.

To request a manifest, a "get_manifest" message is sent.  The message may
optionally contain the last-synced "version" of the peer's database.
(Read-write peers are never required to store manifests.)

```json
{
  "type": "get_manifest",
  "version": 1379489220.149822
}
```

If the manifest version matches the current database number, the peer will
respond with an "manifest_current" message.

```json
{
  "type": "manifest_current"
}
```

If the "get_manifest" request didn't include a "version" field, or the manifest
version is not current, the peer should respond with the full signed "manifest"
message, as explained above.

A peer may elect not to request a manifest, and may also elect to ignore the
"get_manifest" message.


Tree merge algorithm
--------------------

When two read-write peers are connected, they merge their manifests together in
memory on a file-by-file basis in what is called tree merging.  A tree merge
looks at each entry and the one with the latest "utime" field wins.  If the
"utime" matches, the file with the latest "mtime" wins.  If the "mtime" wins,
the largest file wins.  If the sizes match, the file with the smallest "sha256"
wins.

This merged tree is kept in memory and is used to decide which files need to be
retrieved from the peer.  Information about the new files shouldn't be applied
to the database until after the files have been retrieved. 


Read-only manifests
-------------------

A read-only peer cannot change files but needs to prove to other read-only
peers that the files it has are genuine.  To do this, it saves the read-write
manifest and signature to disk whenever it receives it.  The manifest and
signature should be combined, with a newline separating them, and a newline
after the signature.

It then builds its own manifest from the read-write manifest, called a
read-only manifest.  When it does not have all the files mentioned in the
manifest, it includes a bitmask of the files it has, encoded as base64.

If there are two diverged read-write peers and a single read-only peer, there
will be multiple read-write manifests to choose from.  The read-only peer will
add both read-write manifests, with associated bitmasks, to its read-only
manifest.

Similar to the "version" of the read-write database, read-only clients should
keep a "version" number that changes only when its files change.  (Since it is
a read-only, a change would be due to something being changed on a different
peer.)

The read-only manifests do not need to be signed.  Here is an example, with the
read-write manifest abbreviated with an ellipsis for clarity:

```json
{
   "type": "manifest",
   "peer": "a41f814f0ee8ef695585245621babc69",
   "sources": [
     {
       "manifest": "{\"type\":\"manifest\",\"peer\":\"489d80...}\nMC4CFQCEvTIi0bTukg9fz++hel4+wTXMdAIVALoBMcgmqHVB7lYpiJIcPGoX9ukC\n",
       "bitmask": "Lg=="
     }
   ]
```

Manifest merging
----------------

When building the read-only manifest from two or more read-write manifests, the
read-write manifests from each peer should be examined in "version" order,
newest to oldest.  A manifest should only be included if it contains files that
the read-only peer actually has on disk.  Once all the files the read-only peer
has have been represented, it includes no more manifests.

In normal operation where the read-write peers have not diverged, this merging
strategy means that the read-only manifest will only contain one read-write
manifest.


Retrieving files
----------------

Files should be asked for in a random order so that if many peers are involved
with the share the files spread as quickly as possible.

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
bytes from the file.

The server responds with the file data.  This will have a binary payload of
the file contents (encoding of the binary payload was explained in an earlier
section):

```
!100000!{"type": "file_data","path":"photos/img1.jpg", ... }
JFIF.123l;jkasaSDFasdfs...
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


File change notification
------------------------

Files should be monitored for changes on read-write shares.  This can be done
with OS hooks, or if that is not possible, the directory can be rescanned
periodically.

If it appears a file has changed, the hash should be recomputed.  If it doesn't
match, the mtime should be checked one last time to make sure that the file
hasn't been written to while the hash was being computed.  Peers should then be
notified of the change.

Change notifications are signed messages.

Read-only peers should append the change notification, and its signature, to
the stored manifest that it's keeping for each read-write peer.  (Each piece
should have a newline after it.)

The "utime" for file changes is the current time if OS hooks are being used.
If it is detected by a file scan, then the mtime should be used if it is before
the previous time the file was scanned, otherwise the previous scan time should
be used.  Deleted files should always use the previous scan time as the
"utime".  (The start time of the previous scan can be used instead of the
previous scan time for the file in question if desired.)

Notification of a new or changed file looks like this:

```json
{
  "type": "update",
  "file": {
    "path": "photos/img1.jpg",
    "utime": 1379220476,
    "size": 2387629
    "mtime": 1379220393.518242,
    "mode": "0664",
    "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1",
    "id": "8adbd1cdaa0200747f6f2551ce2e1244",
    "aes128": "5121f93b5b2fe518fd2b1d33136ddc33",
  }
}
```

Note that the "file" field makes it possible to differentiate between metadata
about the file and extensions to the "replace" message itself.

Notification of a deleted file looks like this:

```json
{
  "type": "update",
  "file": {
    "path": "photos/img3.jpg",
    "utime": 1379224548,
    "deleted": true,
    "id": "8adbd1cdaa0200747f6f2551ce2e1244"
  }
}
```

Notification of a moved file looks like this:

```json
{
  "type": "move",
  "source": "photos/img5.jpg",
  "destination": {
    "path": "photos/img1.jpg",
    "utime": 1379220476,
    "size": 2387629
    "mtime": 1379220393.518242,
    "mode": "0664",
    "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1",
    "id": "8adbd1cdaa0200747f6f2551ce2e1244",
    "aes128": "5121f93b5b2fe518fd2b1d33136ddc33"
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

File changes notifications should be relayed to other peers once the file has
been successfully retrieved, assuming the other peers haven't already sent
notification that they have the file.


Untrusted peers
---------------

Absent from the above description is how to communicate with an untrusted peer.
Untrusted peers are given encrypted files, which they will can then send to
other peers with the untrusted key, read-only key, or read-write key.

followed by the 16-byte IV,
followed by the encrypted data, using AES in CTR mode.

Files with the same contents should use the same encryption key, they do not
need to be encrypted twice.

Filenames are encrypted using the read-only key (FIXME how?).  The sha1 given
is the sha1 of the encrypted data, including the encryption header.  The size
given is the size of the file including the header.

"file_data" responses will always include the encryption header as the first 32
bytes of the binary payload, even for ranged requests.

FIXME: It is too much burden to calculate the sha1 for the listing, so we could
xor the sha1 with the read-only key.  However, this means that the encrypted
files cannot be verified locally, nor can a listing for an encrypted directory
be built from scratch.  I guess we could add the unencrypted sha1 (with xor) to
the encryption header and add the sha1 of the encrypted data to its footer so
that the listing could be regenerated.

A random amount of padding may be added to the end of each file before the
footer (up to 3% of its size) to reduce the amount of data leaked by
file size.

Instead, why not have the untrusted source store the manifest and then store
all the files by their SHA sum.  That deduplicates without having to store the



Deleted files
-------------

Special care is needed with deleted files to ensure that the user always gets
expected behavior.

If the care is not taken, "ghost" copies of deleted files will reappear
unexpectedly if a peer that hasn't connected in a while returns.

A list of deleted files and the time they were first noticed to be missing must
be tracked until the file stops being reported by all known peers.

An alternative method that is easier to implement is to track deleted files for
a limited amount of time, which should be at minimum 90 days.

If the exact deletion time is unknown, the oldest possible time it could have
been deleted is used.  For example, if the software is not running when the
file is deleted, the time that the last successful scan was started is used.
Additionally, if the software notices that a file is missing during a scan, it
should use the start time of the previous scan as the deletion time for that
file.


Consider the following scenarios:

There are only two peers, operating in read-write mode, peer A and B, which
both have a file.  Peer A deletes it.

Case 1: Both peers are running at that time

Peer A notices the file is missing, and notifies B.  B deletes the file.  The
next time A and B sync reconnect, A notices that B no longer has the file and
stops tracking it.

Case 2: Only A is running

Peer A notices the file is missing and saves the file in its deleted files
list.  The next time B starts, it is notified of the deleted file during file
tree synchronization and file is deleted.  The next reconnect the deleted file
can stop being tracked.

Case 3: Only B is running

When peer A is started it notices that the file was deleted.  It sets the
deletion time to the last time it had seen the file in a scan, which is
nevertheless newer than the mtime of the file.  It connects to B and the
deleted file wins in tree sync.  Things then proceed like case 1 and 2.

Case 4: Neither is running

This is identical to case 3.

+++ More peers

If there are three peers, then the delete must be tracked by all peers until
they all know about the deletion.  This avoids the following scenario:

1. Peers A, B, and C know about a file
2. Only peers A and B are running.
3. The file is deleted on A.
4. B also deletes its file.
5. A disconnects
6. C connects to B.  Since C has the file and B does not, the file reappears on B.
7. A reconnects to B.  The file reappears on A.


First sync and ghost files
--------------------------

When a key is first added to the software from a peer in read-write mode, the
software should warn the user that any directory contents may be overridden.

The existing contents of the directory should not be merged.  However, if a
file appears with an mtime that is newer than the time the share was added to
the software, it can be merged.  This allows the user to start work before the
directory has completely synced.


Keepalive
---------

A message of type "ping" should be sent every minute or so to keep connections
from being dropped:

```json
{"type":"ping"}
```


Known issues
------------

We need to add an 'untrusted challenge' so that we can verify that untrusted
peers have all files and that they are correct.

We should suggest that files be rehashed on rare occasion so that file
corruption can be detected (and hopefully corrected.)

If a file is reverted by copying in an old copy from another source, the mtime
will be older on peers and so it will not be reverted.

ECC keys are not as well supported as RSA keys, but were chosen because they
are much shorter therefore practical to share.  The read-only key-generation
mechanism was chosen because it makes it possible for a read-only key holder to
verify that a read-write share is legitimate.

Since the group most likely to use clearskies are those who care about security,
it's probably reasonable to trade a little usability for improved security.
Instead, we could have the keys be a nonce that just gets a user connected to a
peer.  Once connected, the RSA keys are exchanged.  This requires some
bookkeeping by all the peers, as they should keep the list of valid nonces
synced amongst themselves.

For added security the nonces can be time-limited or single-use, and the GUI
can let the user revoke a nonce.


Checking for missing shares
---------------------------

Each directory should have a hidden file, perhaps named ".ClearSkiesID", which
is not synced but is used to check if a drive is not mounted or a removable
drive is not present.  The file should contain the Share ID.  If this file is
not present, the software should not attempt to do any synchronization, instead
showing an error state for the share.


Archival
--------

When files are changed or deleted on one peer, the other peer may opt to save
copies in an archival directory.  If an archive is kept, it is recommended that
the SHA1 of these files still be tracked so that they can be used for
deduplication in the future.

Software may opt to limit the archive to a certain size, or offer a friendly
way to navigate through the archive.


Deduplication
-------------

The SHA1 hash should be used to avoid requesting duplicate files when already
present in the local share.  Instead, a copy of the local file should be used.


Ignoring files
--------------

Software may choose to allow the user to ignore files with certain extensions
or matching a pattern.  These files won't be sent to peers.


Base32
------

Base32 is used to encode keys for ease of manual keying.  Only uppercase A-Z
and the digits 2-9 are used.  Strings are taken five bits at a time, with
00000 being an 'A', 11001 being 'Z', 11010 being '2', and '11111' being '9'.

Human input should allow for lowercase letters, and should automatically
translate 0 as O.

FIXME: Can we refer to the relevant RFC instead of documenting this ourselves?
Also is there a documented format that includes a checksum?



Subtree copy
------------

Software may support the ability to only checkout a single subdirectory of a
share.  This does not require peer cooperation or knowledge.

In order to make this efficient, the client should keep a cached copy of the
entire tree so that the server doesn't need to send a complete copy of the tree
at connection time.


Partial copy
------------

Software may opt to implement the ability to not sync some folders or files
from the peer.

The software may let the user specify extensions not to sync, give them the
ability to match patterns, or give them a GUI to pick files or folders to
avoid.

As with partial copies, the client should keep a cached copy of the metadata
for the entire tree for efficiency reasons.


Streaming
---------

Software may optionally support not keeping a local copy of the files at all,
and instead stream the file contents live, perhaps as a FUSE filesystem,
directly integrated into a music player as a plugin, or on a mobile device.
The client can keep a small local cache of commonly used files.

It should also be possible to stream writes back to the server.  The client
would need to keep a buffer of outgoing files on local storage while waiting
for the server.

As with subtree copies and  the client should keep a cached copy of the metadata
for the entire tree for efficiency reasons.


Computer resources
------------------

This section is a set of recommendations for implementors and are not part of
the protocol.

The period between directory scans should be a multiple of the time it takes to
do rescans, for example, scans may be done every ten minutes, unless it takes
more than a minute to run a scan, in which case the scan won't be run until ten
times the time it took to run the scan.  This guarantees that scanning overhead
will be less than 10% of system load.

The software should run with low priority.  It should let the user pause sync
activity.

The software should and give battery users the option to not sync while on
battery.

Software should implement rate limiting, as sync is intended as something that
will run in the background without interfering with normal usage.

Software should also consider that many ISPs limit the amount of bandwidth that
can be consumed in a month, and support for limits can be used to ensure that
the cap isn't exceeded.

The software should debounce files changes so that it can stop syncing a file
that is changing too frequently.

The software should not lock files for reading while syncing them so that the
user can continue normal operation.

The software should give the users a rough estimate of the amount of time
remaining to sync a share so that the user can manually transfer files through
sneakernet if necessary.

Users may be relying on your software to back up important files.  You may want
to alert the user (on both computers) if the share has not synced with its peer
if has been longer than certain threshold (perhaps defaulting to a week).

Software may choose to create read-only directories, and read-only files, in
read-only mode, so that a user doesn't make changes that will be immediately be
overwritten.  It could detect changes in the read-only directory and warn the
user that they will not be saved.

While it is not the designed use case of this protocol, some shares may have
hundreds or thousands of peers.  In this case it is recommended that
connections only be made to a few dozen of them, chosen at random.
