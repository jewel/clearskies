ClearSkies Protocol v1 Draft
=========================

The ClearSkies protocol is a two-way (or multi-way) directory synchronization
protocol, inspired by BitTorrent Sync.  It is a friend-to-friend protocol, as
opposed to a peer-to-peer protocol, meaning that files are only shared with
computers that are given an access key -- never anonymously.


Draft Status
------------

This is a draft of the version 1 protocol and is subject to changes as the need
arises.  However, it is believed to be feature complete.

Comments and suggestions are welcome in the form of github issues.
Analysis of the cryptography is doubly welcome.


License
-------

This license is in the public domain.  See the file LICENSE in this same
directory for licensing information about the protocol.


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

When a share is first created, a 128-bit encryption key is generated.  It must
not be generated with a psuedo-random number generator (PRNG), but must come
from a source of cryptographically secure numbers, such as "/dev/random" on
Linux, CryptGenRandom() on Windows, or RAND_bytes() in OpenSSL.

This key is used as the communication key.  All of the read-write peers posses
it, but they do not give it to read-only peers.  It will be referred to as the
read-write pre-shared-key (PSK).  (Details of communication encryption are found
in the "Handshake" section.

The SHA256 of the read-write PSK is called the share ID.  This is used to
locate other share peers.

A 128-bit random number called the peer ID is also generated.  Each peer has
its own peer ID, and the peer should use a different peer ID for each share.

A 4096-bit RSA key should be generated for the share.  It will be used to
digitally sign messages to stop read-only shares from pretending to be
read-write shares.

More keys should be generated for the other access levels:

* A 128-bit read-only PSK
* A 4096-bit read-only RSA key
* A 128-bit untrusted PSK

Once generated, all keys are saved to disk.


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
multi-use and persist for a longer time (even indefinitely).

The human-sharable version of the access code is written with a prefix of
'CLEA', followed by the access code itself.  The access code should be
represented as base32, as defined in [RFC
4648](http://tools.ietf.org/html/rfc4648).  Since the access code is 16 bytes,
and base32 requires lengths that are divisible by 5, a prefix is added to the
access code so that the final result spells CLEARSKIES.  The prefix bytes are
8C948248.  Finally, a LUN check digit is added, using the [LUN mod N
algorithm](http://en.wikipedia.org/wiki/Luhn_mod_N_algorithm), where N is 32.

The 128-bit number is run through SHA256 to get an access ID.  This is used
to locate other peers.

The user may opt to replace the provided access code with a passphrase before
sending it.  If this is done, the SHA256 of the passphrase should be taken
one million times.  This 256-bit hash is considered the access code, and its
SHA256 is the access ID.

Long-lived access codes are spread to other nodes with the same (or higher)
level of access so that the sharing node does not have to stay online.


Access Code UI
--------------

This section contains a suggested user interface for sharing access codes.

When the user activates the "share" button, a dialog is shown with the
following:

* A radio input for one of "read-write", "read-only", and "untrusted"
* The new access code, as a text field that can be edited
* A status area
* A "Cancel Access Code" button
* A "Extend Access Code" button

If the user chooses to "Cancel Access Code", the access code should no longer
unlock the share.  The "Extend Access Code" button should present advanced
options, and perhaps default to 24 hours.

Once the access code has been used by the friend and both computers are
connected, the status area should indicate as such.  It will no longer be
possible to cancel the access code, but it can still be extended.


Peer Discovery
--------------

When first given an access code, the access ID is used to find peers.  If the
share ID is known, it is used instead.

Various sources of peers are supported:

 * A central tracker
 * Manual entry by the user
 * LAN broadcast
 * A distributed hash table (DHT) amongst all participants

Each of these methods can be disabled by the user on a per-share basis and
implementations can elect not to implement them at their discretion.

Peer addresses are represented as ASCII, with the address and port number
separated by a colon.  IPv6 addresses should be surrounded by square brackets.


Tracker Protocol
----------------

The tracker is an HTTP or HTTPS service.  The main tracker service runs at
tracker.example.com (to be determined).

Software should come with the main tracker service address built-in, and may
optionally support additional tracker addresses.  Finally, the user should be
allowed to customize the tracker list.

Note that both peers should register themselves immediately with the tracker,
and re-registration should happen if the local IP address changes, or after the
TTL period has expired of the registration.

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

The TTL is the number of seconds until the client should register again.

The "others" key contains a list of all other peers that have registered for
this ID, with the client's "peer ID", followed by an @ sign, and then
peer's IP address.  The IP address can be an IPV4 address, or an IPV6 address
surrounded in square brackets.


Fast Tracker Extension
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
broadcast contains the following JSON payload:

```json
{
  "name": "ClearSkiesBroadcast",
  "version": 1,
  "id": "22596363b3de40b06f981fb85d82312e8c0ed511",
  "peer": "2a3728dca353324de4d6bfbebf2128d9",
  "myport": 40121
}
```

The ID is the share ID or access ID that the software is aware of.

Broadcast should be sent on startup, when a new share is added, when a new
network connection is detected, when a new access id is created, and every
minute or so afterwards.


Distributed Hash Table
----------------------

Once connected to a peer, a global DHT can be used to find more peers.  The DHT
contains a mapping from share ID to peer address.

Future updates to protocol version 1 will include the DHT mechanism.


Firewall Transversal
--------------------

There is no standard port number on which to listen.

Software should use UPnP to make sure that its listening port is open to the
world.

Future updates to the protocol will include a method for communicating over
UDP.


Wire Protocol
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
prefixed with an exclamation point and then the JSON message as usual,
including the termination newline.  After the newline, the binary payload is
sent.  It is sent in one or more chunks, ending with a zero-length binary
chunk.  Each chunk begins with its length in ASCII digits, followed by a
newline, followed by the binary data.

For example:

```
!{"type":"file_data","path":"test/file.txt",...}
45
This is just text, but could be binary data!
25
This is more binary data
0
```

A signed message will be prefixed with a dollar sign.  The JSON message is then
sent, and then on the next line the RSA signature is given, encoded with
base64, and followed up with a newline.  The base64 data should not include any
newlines.

```
${"type":"foo","arg":"bar"}
MC0CFGq+pt0m53OP9eZSndaUtWwKnoJ7AhUAy6ScPi8Kbwe4SJiIvsf9DUFHWKE=
```

If a message has both a binary payload and a signature, it will start with a
dollar sign and then an exclamation mark, in that order.  The signature does
not cover the binary data, just the JSON text.  Here is the previous example,
but with binary data added:

```
$!{"type":"foo","arg":"bar"}
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
that lists all of the protocol versions it supports, as well as an optional
feature list.  The protocol version is an integer.  The features are strings.

The current protocol version is 1.  Future improvements to version 1 will be
done in a backwards compatible way.  Version 2 will not be compatible with
version 1.

Officially supported features will be documented here.  Unofficial features
should start with a period and then a unique prefix (similar to Java).
Unofficial messages should prefix the "type" key with its unique prefix.

What follows is an example greeting (newlines have been added for legibility,
but they would not be legal to send over the wire):

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
"start" message:

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

If the server does not recognize the ID, it will send back a "cannot_start"
message and close the connection:

```json
{
  "type": "cannot_start"
}
```

Otherwise, it will send back a "starttls" message:

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
times is too great, software may notify the user and refuse to participate or
may attempt to account for the difference in conflict resolution algorithm.


Key Exchange
------------

If the access level negotiated in the handshake is "unknown", then the keys
will now be given to the new peer.

The appropriate set of keys will be chosen according to the access level that
was chosen when the access code was created.

RSA keys should be encoded as PEM files, and the PSKs should be encoded as hex.

Keys that the peer should not have are also sent, encrypted with the read-write
PSK.  This is necessary so that the master passphrase can be used to create a
read-write peer when there are no longer any read-write peers.

The "File Encryption" section explains how to encrypt files.  After encrypting
each key, it should be base64 encoded.

Here is an example key exchange for a read-only node.  RSA keys have been
abbreviated for clarity:

```json
{
  "type": "keys",
  "access": "read_only",
  "share_id": "2bd01bbb634ec221f916e176cd2c7c6c2fa04e641c494979613d3485defd7d18",
  "untrusted": {
    "psk": "1f5d969cdbfe090bf740974d27e7d8ee",
  },
  "read_only": {
    "psk": "b699049ce1f453628117e8ba6ee75f42",
    "rsa": "-----BEGIN RSA PRIVATE KEY-----\nMIIJKAIBAAKCAgEA4Zu1XDLoHf...TE KEY-----\n"
  },
  "read_write": {
    "encrypted_rsa": "KaPwf85p4PUXUImWMEn1MwlRC77TWlEtZjqxI+QhDKTlFxi...",
  }
}
```

If the keys given are encrypted, the key name should be prefixed with
"encrypted_".  Note that the read-write PSK is never included in this exchange.

Once the keys are received, the peer should respond with a
"keys_acknowledgement" message:

```json
{
  "type": "keys_acknowledgement"
}
```

As soon as the acknowledgment is received, the corresponding access code
should be deactivated, unless it was a multi-use access code.

The connection is then closed, and the new share ID is used to create a new
connection.


File Tree Database
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
 * "key" - a 256-bit encryption key, stored as hex

If a file is deleted, the deleted boolean is set to true.  Any fields listed
after the deleted field in the list above can be blanked.  The entry for the
deleted file will persist indefinitely in the database.  An explanation for the
necessity of this behavior is in the later section called "Deleted Files".

The "mtime" is the integer number of seconds since the unix epoch (normally
called a unix timestamp) since the file contents were last modified.

The "update time" is the time that the file was last changed, as a unix
timestamp.  On first scan, this is the time the scan discovered the file.

The unix mode bits represent the user, group, and other access modes for the
file.  This is represented as an octal number, for example "0755".

The SHA256 of the file contents should be cached in a local database for
performance reasons, and should be updated with the file size or mtime changes.

The file ID is used for untrusted peers.  It is created when the file entry
is first created and does not change again.

The key field holds an 128-bit encryption key and a 128-bit Initialization
Vector (IV), in that order.  The key is used to encrypt files when being sent
to untrusted peers.  They are predetermined so that all peers agree on how to
encrypt the file.


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
other's file tree listing.

Each access level has its own way of creating file listings.  The file listing
and a signature are together called a manifest.

A read-write peer will generate a new manifest whenever requested by a peer
from the contents of its database.  It contains the entire contents of the
database, including the database "version" timestamp.  The file entries should
be sorted by path.  Its own peer_id is also included.  The entire manifest will
be signed (using the key-signing mechanism explained in the "Wire Protocol"
section) except when being sent to other read-write peers.

Here is an example manifest JSON as would be sent over the wire (the signature
is not shown):

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
      "key": "5121f93b5b2fe518fd2b1d33136ddc33d8fba39749d57c763bf30380a387a1fa"
    },
    {
      "path": "photos/img2.jpg",
      "utime": 1379220468,
      "size": 6293123
      "mtime": 1379100421.442491,
      "mode": "0600",
      "sha256": "64578d0dc44b088b030ee4b258de316b5cb07fdf42b8d40050fe2635659303ed",
      "id": "ade5f6098c8d99bd6b5472e51c64e09a",
      "key": "2304bde0b070a0d3ca65c78127f2f1895121f93b5b2fe518fd2b1d33136ddc33"
    },
    {
      "path": "photos/img3.jpg",
      "utime": 1379489028,
      "deleted": true,
      "id": "ccccf6098c8d99bd6b5472e51c64e0aa"
    }
  ]
}
```

The contents of the shared directory can diverge between two read-write peers,
and stay diverged for a long time.  (Most notably, this happens when a peer
opts not to sync some files, as is explained in the "Subtree Copy" section.)
For this reason, each read-write peer has its own manifest.

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
respond with a "manifest_current" message.

```json
{
  "type": "manifest_current"
}
```

If the "get_manifest" request didn't include a "version" field, or the manifest
version is not current, the peer should respond with the full "manifest"
message, as explained above.

A peer may elect not to request a manifest, and may also elect to ignore the
"get_manifest" message.


Tree Merge Algorithm
--------------------

When two read-write peers are connected, they merge their manifests together in
memory on a file-by-file basis in what is called tree merging.  A tree merge
compares entry and the one with the latest "utime" field wins.  If the "utime"
matches, the file with the latest "mtime" wins.  If the "mtime" matches, the
largest file wins.  If the sizes match, the file with the smallest "sha256"
wins.

This merged tree is kept in memory and is used to decide which files need to be
retrieved from the peer.  Information about the new files shouldn't be applied
to the database until after the files have been retrieved. 


Read-Only Manifests
-------------------

A read-only peer cannot change files, but needs to prove to other read-only
peers that the files it has are genuine.  To do this, it saves the read-write
manifest and signature to disk whenever it receives it.  The manifest and
signature should be combined, with a newline separating them, and a newline
after the signature.

The read-only peer builds its own manifest from the read-write manifest, called
a read-only manifest.  When it does not have all the files mentioned in the
manifest, it includes a bitmask of the files it has, encoded as base64.

If there are two diverged read-write peers and a single read-only peer, there
will be multiple read-write manifests to choose from.  The read-only peer will
add both read-write manifests, with associated bitmasks, to its read-only
manifest.

Similar to the "version" of the read-write database, read-only clients should
keep a "version" number that changes only when its files change.  (Since it is
a read-only, a change would be due to something being downloaded.)

The read-only manifests do not need to be signed.  Here is an example, with the
read-write manifest abbreviated with an ellipsis for clarity:

```json
{
   "type": "manifest",
   "peer": "a41f814f0ee8ef695585245621babc69",
   "version": 1379997032,
   "sources": [
     {
       "manifest": "{\"type\":\"manifest\",\"peer\":\"489d80...}\nMC4CFQCEvTIi0bTukg9fz++hel4+wTXMdAIVALoBMcgmqHVB7lYpiJIcPGoX9ukC\n",
       "bitmask": "Lg=="
     }
   ]
```


Manifest Merging
----------------

When building the read-only manifest from two or more read-write manifests, the
read-write manifests from each peer should be examined in "version" order,
newest to oldest.  A manifest should only be included if it contains files that
the read-only peer actually has on disk.  Once all the files the read-only peer
has have been represented, it includes no more manifests.

In normal operation where the read-write peers have not diverged, this merging
strategy means that the read-only manifest will only contain one read-write
manifest.


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
    "key": "5121f93b5b2fe518fd2b1d33136ddc3361fd9c18cb94086d9a676a9166f9ac52"
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
    "key": "5121f93b5b2fe518fd2b1d33136ddc3371ea246f902804fb64e7cf822eb8453c"
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


Untrusted Peers
---------------

Absent from the sections above is how to communicate with an untrusted peer.
Untrusted peers are given encrypted files, which they will then send to peers
of all other types, including other untrusted peers.  Its behavior is similar
to how read-write and read-only peers interact.

What follows is a high-level overview of the entire operation of an untrusted
peer.  Detailed descriptions of each process are in later sections.

The peer's encrypted manifest is combined with a list of all relevant file IDs,
this is known as the untrusted manifest.  The result is then signed with the
read-only RSA key.

This manifest is sent to untrusted peers.  The untrusted peer stores the
manifest and then asks the read-only peer for each file, which is then saved to
disk.

When an untrusted peer connects to another untrusted peer, it sends an
untrusted manifest, which is built using one or more encrypted manifests, each
with a bitmask.

The SHA256 of the file isn't known until the file is encrypted, which doesn't
happen until the file is requested by an untrusted node.  Once calculated,
peers should store the hash value and include it in future file listings.

Untrusted peers can be given a cryptographic challenge by read-only and
read-write peers to see if they are actually storing files they claim to be
storing.


Untrusted Manifests
-------------------

Manifests are negotiated with the "get_manifest" and "manifest_current" messages
as usual.

A read-only or read-write peer will encrypt its manifest with the read-only
PSK, as described in the "File Encryption" section below, and the result is
base64 encoded.  This is encrypted with the read-only manifest is encrypted
with the read-only PSK and base64 encoded.  This is combined with the peer ID
and "version", as well as a list of all the file IDs and their sizes.  If the
SHA256 of the encrypted file is known, it should be added to the file.  Note
that the file list should only include files actually present on the peer, and
all deleted files.

The message is signed with the read-write or read-only RSA key (as appropriate
for the peer).

```json
{
  "type": "manifest",
  "peer": "989a2afee79ec367c561e3857c438d56",
  "version": 1380082110,
  "manifest": "VGhpcyBpcyBzdXBwb3NlZCB0byBiZSB0aGUgZW5jcn...",
  "files": [
    {
      "id": "8adbd1cdaa0200747f6f2551ce2e1244",
      "utime": 1379220476,
      "size": 2387629
    },
    {
      "id": "eefacb80ad05fe664d6f0222060607c0",
      "utime": 1379318976,
      "size": 3932,
      "sha256": "220a60ecd4a3c32c282622a625a54db9ba0ff55b5ba9c29c7064a2bc358b6a3e"
    }
  ]
}
```

The manifest sent from an untrusted peer includes any manifests necessary to
prove that the files it has are legitimate and a bitmask:

```json
{
  "type": "manifest",
  "peer": "7494ab07987ba112bd5c4f9857ccfb3f",
  "version": 1380084843,
  "sources": [
    {
      "manifest": "{\"type\":\"manifest\",\"peer\":\"989fac...}\nMC4CFQCEvTIi0bTukg9fz++hel4+wTXMdAIVALoBMcgmqHVB7lYpiJIcPGoX9ukC\n",
      "bitmask": "Lg=="
    }
  ]
}
```

This should follow the same manifest merging algorithm explained in an earlier
section.

The list of files is merged using the tree merging algorithm also as explained
earlier.

File change updates work in a similar manner to how they work between
read-write and read-only peers.  Here is a regular update from the earlier
section:

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
    "key": "5121f93b5b2fe518fd2b1d33136ddc3361fd9c18cb94086d9a676a9166f9ac52"
  }
}
```

The entire message and its signature (separated by a newline), are encrypted
with the read-only PSK and put into a similar message containing the ID, size,
and sha256 of the encrypted contents (if known).  This message should be signed.

```json
{
  "type": "update",
  "proof": "Z29vZCBncmllZiwgbW9yZSBmYWtlIGRhdGEuI...",
  "file": {
    "id": "8adbd1cdaa0200747f6f2551ce2e1244",
    "utime": 1379220476,
    "size": 2387629
  }
}
```

File moves do not require special handling (they are just sent with type
"update"), since the file ID is unique and only the encrypted metadata changed.

File deletes are handled as an "update" where the "deleted" member is set to
true.

Just like with read-write and read-only file changes, the change messages
should be appended to the copy of the manifest including their signatures.


Deduplicating on Untrusted Peers
--------------------------------

Since untrusted peers do not have access to the unencrypted SHA256, the
read-only and read-write peers need to help the untrusted peers know which file
IDs match, and when those file IDs stop matching.  A "matches" member is added
to the untrusted manifest on all but the first duplicate file (where "first" is
considered to be the file ID that is lowest when the hex value is sorted with
strcmp).

```json
{
  "type": "manifest",
  "peer": "989a2afee79ec367c561e3857c438d56",
  "version": 1380082110,
  "manifest": "VGhpcyBpcyBzdXBwb3NlZCB0byBiZSB0aGUgZW5jcn...",
  "files": [
    {
      "id": "8adbd1cdaa0200747f6f2551ce2e1244",
      "utime": 1379220476,
      "size": 2387629
    },
    {
      "id": "eefacb80ad05fe664d6f0222060607c0",
      "utime": 1379318976,
      "size": 3932,
      "sha256": "220a60ecd4a3c32c282622a625a54db9ba0ff55b5ba9c29c7064a2bc358b6a3e"
    },
    {
      "id": "dd711c53e77e793bb77555a53a5feb84",
      "utime": 1379221088,
      "matches": "8adbd1cdaa0200747f6f2551ce2e1244"
    }
  ]
}
```


File Encryption
---------------

Encryption should be done with AES128 in CTR mode (CTR mode is seekable).  The
first sixteen bytes of the file are "ClearSkiesCrypt1".  A random encryption
key is chosen.  This is XOR'd with the encryption key and written as the next
16 bytes of the file.  The following 16 bytes in the file should be the
initialization vector (IV).  Then the encrypted data is written.  The last 32
bytes in the file should be the SHA256 of the file.


Untrusted Proof of Storage
--------------------------

Untrusted peers can be asked to prove that they are storing a file.  This is
I/O intensive for both peers, so some steps should be taken to reduce
unnecessary verification.  If there are read-write peers present on the
network, read-only peers should not perform any verification.  By default, the
rate of verification should be extremely low, perhaps a single file per day.

Software may support user-initiated full verifications.

A random file is chosen and a 32-byte random sequence is generated.  This is
sent to the untrusted peer.

The read-write peer then asks for file verification with a *signed* message:

```json
{
  "type": "verify",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "prefix": "3d820dcc0ecad651e87fc84bb688bf7e6c7ee019ba47d9bdaaf6bc4bed2b9620"
}
```

The untrusted peer concatenates the 32-bytes and the entire contents of the
file and sends back the result:

```json
{
  "type": "verify_result",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "result": "fff8acd78f7528c143cb5a6971f911d3869368cbc177f3f4404d945c6accc08d"
}
```

The read-write peer then uses the prefix and IV to recreate the experiment and
validate that resulting hash is correct.  If the hash is not correct, software
may notify the user, or it could change the file_id and encryption key for that
file so that the untrusted node re-downloads an undamaged version.

If an untrusted peer is overloaded, it may choose to ignore the proof-of-storage
request.  It may also send back a busy message:

```json
{
  "type": "verify_busy",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "retry_in": 600
}
```


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


Spreading Access Codes
----------------------

Long-lived access codes are shared with other peers so that the originating
peer does not need to stay online.

Access codes should only be given to peers with the same security level.

Since access codes are short and created rarely, all known access codes are
sent when the connection is first opened.

Access codes should be kept locally in a database.  Each record has a "utime"
timestamp and should only be replaced with a record with a newer timestamp.  To
stop read-only peers from being able to fill up the hard drive of other peers,
software may rate-limit access code updates.

Access codes can be revoked and single-use access codes are marked as used.
They should not be removed from the database until they expire, if time limited,
otherwise they should be kept indefinitely.

Passphrases are not stored verbatim but instead the SHA256(SHA256(...)) is
stored.  Note that this is a 256-bit access code instead of the usual 128-bit
codes.

When first connected to a peer, all known access codes should be sent.
Thereafter, only database updates need to be sent.  Updates do not need to be
relayed.

The "access_code_list" message is used for the initial list, and subsequent
updates send an "access_code_update".  Here is an example message, which shows
an access code of each type:


```json
{
  "type": "access_code_update",
  "codes": [
    {
      "code": "a0929405c4ff5a96ffeb8cbe672c82d4",
      "one_time": true,
      "created": 1379735175,
      "expiration": 1379744200,
      "utime": 1379735175
    },
    {
      "code": "e47c0685fe4bad29cdc0a7bdbd5335cb",
      "created": 1379744627,
      "expiration": false,
      "utime": 1379744627
    },
    {
      "code": "ed384f58875d01e242293142eed75a7a",
      "created": 1379741016,
      "expiration": false,
      "revoked": true,
      "utime": 1379744623
    },
    {
      "code": "61a08703a6a4c774cad650afaedd9c10",
      "created": 1379744460,
      "one_time": true,
      "used": true,
      "expiration": false,
      "utime": 1379744616
    },
    {
      "code": "19ababf69f21cf018e846bb90ecac80cddfa532c5aae97acc99172b5be529fb7",
      "created": 1379744616,
      "one_time": true,
      "expiration": 1379744611
      "utime": 1379744616
    }
  ]
}
```


Checking for Missing Shares
---------------------------

Each directory should have a hidden file, perhaps named ".ClearSkies", which is
not synced but is used to check if a drive is not mounted or a removable drive
is not present.  The file should contain the Share ID or another ID that is
unique to the share.  If this file is not present, the software should not
attempt to do any synchronization, instead showing an error state for the
share.


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

Software may choose to create read-only directories, and read-only files, in
read-only mode, so that a user doesn't make changes that will be immediately
overwritten.  It could detect changes in the read-only directory and warn the
user that they will not be saved.

While it is not the designed use case of this protocol, some shares may have
hundreds or thousands of peers.  In this case, it is recommended that
connections only be made to a few dozen of them, chosen at random.
