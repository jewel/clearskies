ClearSkies Protocol v1 Draft
=========================

The ClearSkies protocol is a two-way (or multi-way) directory synchronization
protocol, inspired by BitTorrent Sync.  It is not compatible with btsync but a
client could potentially implement both protocols.  It is a friend-to-friend
protocol as opposed to a peer-to-peer protocol.

This is a draft of the version 1 protocol and is subject to breaking changes
when necessary.


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

The share ID and listening port are used to make a GEt request to the tracker:

    http://tracker.example.com/clearskies/track?id=22596363b3de40b06f981fb85d82312e8c0ed511&myport=30020

The response must have the content-type of application/json and will have a
JSON body like the following (whitespace has been added for clarity):

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
broadcast contains the following JSON payload (whitespace has been added for legibility):

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
contains a mapping from share ID to peer address.

Future updates to protocol version 1 will include the DHT mechanism.


Firewall transversal
--------------------

There is no standard port number on which to listen.

Clients support UPnP to make sure that its listening port is open to the world.

Future updates to the protocol will include a method for communicating over
UDP.


Wire protocol
-------------

The wire protocol is composed of JSON messages, with an extension for handling
binary data.

A normal message is a JSON object on a single line, followed by a newline.  No
newlines are allowed within the JSON representation.  (Note that JSON encodes
newlines in strings as "\n", so there is no need to worry about cleaning out
newlines within the object.)

The object will have a "type" key, which will identify the type of message.

For example:

```json
{"type":"foo","arg":"Basic example message"}
```

To simplify implementations, messages are asynchronous (no immediate response
is required).  The protocol is almost entirely stateless.  For forward
compatibility, unsupported message types or extra keys are silently ignored.

A message with a binary data payload is also encoded in JSON, but it is
prefixed an exclamation point, followed by the number of bytes in ASCII,
followed by an exclamation point, and then the JSON message as usual, including
the termination newline.  After the newline, the entire binary payload will be
sent.  For ease in debugging, the binary payload will be followed by a newline.

For example:

```
!12042!{"type":"file_data","path":"photos/baby.jpg",...}
JFIF..JdXNgc . 8kTh  X gcqlh8kThJdXNg. lh8kThJd_  cq.h8k...
```

As a rule, the receiver of file data should always be the one to request it.
It should never be opportunistically pushed.  This allows clients to stream
content or only do partial checkouts.

If a message does not begin with an '{' or an '!', it should be ignored.

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
done in a backwards compatible way.  Version 2 will not be compatible with
version 1.

Officially supported features will be documented here.  Unofficial features
should start with a period and then a unique prefix (similar to Java).
Unofficial messages should prefix the "type" key with its unique prefix.

The first message is the "greeting" type.  Newlines have been added for
legibility, but they would not be legal to send over the wire.

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
  "share": "22596363b3de40b06f981fb85d82312e8c0ed511",
  "mode": "read-only"
}
```

The "mode" key is one of "read_only" and "read_write".

If the server does not recognize this share, it will send back an
"no_such_share" message, and close the connection:

```json
{
  "type": "no_such_share"
}
```

From this point forward all messages will be encrypted.


Connection encryption
---------------------

The connection is encrypted with with TLS_DHE_PSK_WITH_AES_128_CBC_SHA from
[RFC 4279](http://tools.ietf.org/html/rfc4279).  Protocol version 1 only
supports this mode.  The key used will depend on the "mode" the client asks
for.

Both peers send a message through the connection divulging more information
about themselves for diagnostic purposes:

```json
{
  "type": "identity",
  "name": "Jaren's Laptop",
  "time": 1379225084,
  "id": "6f5902ac237024bdd0c176cb93063dc4"
}
```

The "name" field is a human-friendly identifier for the computer.  The ID is a
128-bit random ID that should be generated when the software is first
installed.  If the "id" matches on both computers, they should fail to interact
and give the user a diagnostic message.  This avoids accidental loopback.

The "time" is a unix timestamp of the current time.  This is sent because the
conflict resolution relies on an accurate time.  If the difference between the
times is too great, both clients may notify the user and/or attempt to account
for the difference in conflict resolution algorithm, at the client's
disgression.  The clients may also refuse to run.


File tree representation
------------------------

The entire shared directory should be scanned and an in-memory view of the
tree should be created, with the following elements for each file:

 * relative path from inside the share, with no leading slash
 * file size in bytes
 * mtime
 * sha1 of file contents

The "mtime" is the number of seconds since the unix epoch since the file
contents were last modified.

The SHA1 of the file contents should be cached in a local database for
performance reasons, and should be updated with the file size or mtime changes.
To keep repositories in sync, files should be removed from the cache
occasionally to check if they have the same SHA1 hash.

Windows clients must translate all "\" path delimiters to "/", and must use a
reversible encoding for characters that are valid in paths on unix but not on
windows, such as '\', '/', ':', '*', '?', '"', '<', '>', '|'.  The suggested
encoding is to use URL encoding with the percent character, followed by two hex
digits.  This should only be done for these characters and should only be
reversed for these characters.

A SHA1 hash of the file tree needs to be made of the entire file tree, which is
why all systems must handle files in a consistent manner.  The list of files is
sort alphanumerically (the byte representations of the paths should be sent in
UTF8 order) then hashed in the following order, separated by null bytes.

* file path as UTF8 string
* file size as ASCII integer
* mtime as ASCII integer
* SHA1 hash as hexidecimal string, all lowercase


File tree synchronization
-------------------------

In the remainder of the protocol documentation, "server" and "client" has a
different meaning if one of the peers has a read-write copy of the share and
the other has a read-only copy of the share.  In that case, "server" always
refers to the read-write copy and "client" to the read-only copy.  In all other
cases, "server" and "client" refer to the TCP connection initiator and
receiver.

When both clients are read-write or both are read-only, bidirectional
synchronization takes place.  If one is read-write and one is read-only,
unidirectional synchronization happens.

One an encrypted connection is established, both peers work towards
establishing a canonical view of the entire directory tree and associated
metadata.  To do this, first a quick check is done to see if the client already
has a correct version of the tree.  Both clients send the SHA1 of the entire
tree (the proper generation of the SHA1 is explained in the previous section)
in a message.

```json
{
  "type": "listing_hash",
  "sha1": "e90f88f8053f4a2c0134f5fd71907fb9c12127b0",
  "last_sync": 1379220847
}
```

Note that if a client has just started it may not have a complete picture of
its directory contents.  It will not send a listing_hash until it has
completely indexed the files it already has.

If the hashes from both messages match, then the trees are synced and no further
synchronization is necessary.

If the hash does not match, then the behavior depends on the sync mode.  If it
is unidirectional (one client is read-only and read-write), only the server
sends the "listing" message.  Otherwise both client and server send the message
simultaneously.

The "listing" message contains the full directory tree as well as list of
deleted files and the time they were deleted.  The full rationale for the need
for tracking deleted files is explained in a later section.

```json
{
  "type": "listing",
  "files": [
    {
      "path": "photos/img1.jpg",
      "sha1": "602aba74d093e7893e87c4ba4295021937087bc4",
      "mtime": 1379220393,
      "size": 2387629
    },
    {
      "path": "photos/img2.jpg",
      "sha1": "dbe2e1f6f295102b0b93d991ab4508979aa9433e",
      "mtime": 1379100421,
      "size": 6293123
    },
    {
      "path": "photos/img3.jpg",
      "dtime": 1383030498,
    }
  ]
}
```

In unidirectional mode, the file tree is now synchronized and the client is
fully informed as to which files it needs to request.  The rest of this section
deals with merging the trees in bidirectional mode.

If a conflict arises, the file with the newest time wins.  If both have the
same time, the largest file wins.  If both have the same time and size, an
ASCII string comparison (strcmp) of the file hashes should be done and the file
with the lesser hash wins.

Deleted files win if the dtime (deletion time) is newer than the mtime of the
file in question.  If both times match, the deletion loses.

Note: Too increase efficiency, clients may cache the correct file listing for
each known peer so that it does not need to be redetermined on subsequent
negotiations.


Retrieving files
----------------

Files should be received in a random order so that if many peers are involved
with the share the files spread as quickly as possible.

If either peer wishes to retrieve the contents of a file, it sends the
following message:

```json
{
  "type": "get",
  "path": "photos/img1.jpg",
  "range": [0, 100000]
}
```

The "range" parameter is optional and allows the client to request only
certain bytes from the file.

The other peer responds with the file data.  This will have a binary payload, as explained earlier:

```
!100000!{"type": "file_data","path":"photos/img1.jpg", ... }
JFIF.123l;jkasaSDFasdfs...
```

A full look at the JSON payload:

```json
{
  "type": "file_data",
  "path": "photos/img1.jpg",
  "mtime": 1379223577,
  "ctime": 1379223570,
  "mode": 0600,
  "sha1": "fd5b138f7e42bd28834fb7bf35aa531fbee15d7c"
}
```

The message also contains additional metadata so that the file can be recreated
as closely as possible.  Mode bits can be translated between operating systems
at the client's discretion.

The sender should verify that the file's mtime hasn't changed since it was last
added to its database, so that the SHA1 can be updated.  For small files, the
entire file should be read into memory before being sent, so that the SHA1 can
be verified.

The receiver should write to a temporary file, perhaps with a ".!clearsky"
extension until, it has been fully received.  The SHA1 hash should be verified
before replacing the original file.  On unix systems, rename() should be used
to overwrite the original file so that it is done atomically.

Remember that the protocol is asynchronous, so clients may issue multiple
"get" requests so that the responses will be pipelined.  This behavior
will cause a large speedup on small files when latency is high.


File change notification
------------------------

Files should be monitored for changes on read-write shares.  This can be done
with OS hooks, or if that is not possible, the directory can be rescanned
periodically.

The hash of the file should be regenerated.  If it matches, the mtime should be
checked one last time to make sure that the file hasn't been written to again
while waiting for the file.

Notification of a new or changed file looks like this:

```json
{
  "type": "replace",
  "path": "photos/img1.jpg",
  "sha1": "602aba74d093e7893e87c4ba4295021937087bc4",
  "mtime": 1379220393,
  "size": 2387629
}
```

Notification of a renamed file looks like this:
```json
{
  "type": "rename",
  "old_path": "photos/img5.jpg",
  "path": "photos/img4.jpg",
  "sha1": "49ef4c1f9273718b2421b2c076f09786ede5982c",
  "mtime": 1379732734,
  "size": 2259148
}
```

Note that a "rename" is technically a delete and a 

Notification of a deleted file looks like this:

```json
{
  "type": "delete",
  "path": "photos/img3.jpg",
  "dtime": 1379224548
}
```

It is the job of the detector to notice renamed files (by SHA1 hash).  In order
to accomplish this, a rescan should look at the entire batch of changes before
sending them to the new client.

The receiver of the files should check the destination file before replacing it
to see if it has changed.  If so, it should follow the usual conflict
resolution rules as explained earlier.


Deleted files
-------------

Special care is needed with deleted files to ensure that the user always gets
expected behavior.

A list of deleted files and the time they were first noticed to be missing must
be tracked until the file stops being reported by all known clients.

If the exact deletion time is unknown, the oldest possible time it could have
been deleted is used.  For example, if the client is not running when the file
is deleted, the time that the last successful scan was started is used.
Additionally, if a client notices that a file is missing during a scan, it
should use the start time of the previous scan as the deletion time for that
file.


Consider the following scenarios:

Client A and B both have a file.  Client A deletes it.

Case 1: Both clients are running at that time

Client A notices the file is missing, and notifies B.  B deletes the file.  The
next time A and B sync reconnect, A notices that B no longer has the file and
stops tracking it.

Case 2: Only A is running

Client A notices the file is missing and saves the file in its deleted files
list.  The next time B starts, it is notified of the deleted file during file
tree synchronization and file is deleted.  The next reconnect the deleted file
can stop being tracked.

Case 3: Only B is running

When client A is started it notices that the file was deleted.  It sets the
deletion time to the last time it had seen the file in a scan, which is
nevertheless newer than the mtime of the time.  It connects to B and the
deleted file wins in tree sync.  Things then proceed like case 1 and 2.

Case 4: Neither is running

This is identical to case 3.


Checking for missing shares
---------------------------

Each directory should have a hidden .ClearSkiesID file which is not synced but
is used to check if a drive is not mounted or a removable drive is not present.
The file should contain the Share ID.  If this file is not present, the client
should not attempt to do any synchronization, instead showing an error state
for the share.


Archival
--------

When files are changed or deleted on one peer, the other peer may opt to save
copies in an archival directory.  If an archive is kept, it is recommended that
the SHA1 of these files still be tracked so that they can be used for
deduplication in the future.

Clients may opt to limit the archive to a certain size, or offer a friendly way
to navigate through the archive.


Deduplication
-------------

The SHA1 hash should be used to avoid requesting duplicate files when already
present in the local share.  Instead, a copy of the local file should be used.


Base32
------

Base32 is used to encode keys for ease of manual keying.  Only uppercase A-Z
and the digits 2-9 are used.  Strings are taken five bits at a time, with
00000 being an 'A', 11001 being 'Z', 11010 being '2', and '11111' being '9'.

Human input should allow for lowercase letters, and should automatically
translate 0 as O.



Subtree copy
------------

A client may support the ability to only checkout a single subdirectory of a
share.  This does not require peer cooperation or knowledge.

In order to make this efficient, the client should keep a cached copy of the
entire tree so that the server doesn't need to send a complete copy of the tree
at connection time.


Partial copy
------------

Clients may opt to implement the ability to not sync some folders from the
peer.

Like the subtree copies, the client should keep a cached copy of the metadata
for the entire tree for efficiency reasons.


Streaming
---------

Clients may optionally support not keeping a local copy of the files at all,
and instead stream the file contents live, perhaps as a FUSE filesystem,
directly integrated into a music player as a plugin, or on a mobile device.
The clients can keep a small local cache.

It should also be possible to stream writes back to the server.  The client
would need to keep a queue of outgoing files on local storage while waiting for
the server.


Rsync Extension
---------------

Official feature string: "rsync".

The rsync extension increases wire efficiency by only transferring the parts of
files that have changed.  It is an optional extension, to support simple
clients.

The behavior of the algorithm works similar to the "rdiff" command in unix,
where the "signature", "delta", and "patch" steps are done separately.

For file transfer, if a local file is already present and a delta is desired,
instead of issuing a "get" request, a "rsync.signature" request with a binary
payload can be sent:

```json
{
  "type": "rsync.signature",
  "path": "photos/img1.jpg"
}
```

The server then responds with an "rsync.patch" message, with a binary payload of the actual patch generated by the "delta" command:

```json
{
  "type": "rsync.patch",
  "path": "photos/img1.jpg",
  "mtime": 1379223577,
  "ctime": 1379223570,
  "mode": 0600,
  "sha1": "fd5b138f7e42bd28834fb7bf35aa531fbee15d7c"
}
```

The client then uses the patch and the old file to create a temporary file,
which is then used to overwrite the old file after verification of SHA1 sum, as
normal.


Rsync Listing Extension
-----------------------

Official feature string: "rsync_tree".

The rsync algorithm can also used to exchange the directory tree.  The
"listing_hash" message is exchanged as usual.  Then the rest of the operations
operate on a textual representation of the keys.  Since JSON does not guarantee
the order of keys, a different representation is necessary.

The data will be written as text, newline separated, with the following fields
"path", "sha1", "mtime", "size", in that order.  Once all files have been
written, an extra newline represents the end of the listing.  Deleted files are
then listed, with "path" and "dtime" pairs, also newline separated.  A final
extra newline ends the deleted files list.  Anything after the deleted list
should be ignored for forwards compatibility.

If a path string contains any bytes outside the range of 0x00-0x7f, or contains
a newline (character 0x0a), it should be represented as UTF8.  This result is
then base64 encoded.  If the base64 encoded added newlines, they should be
removed).  ASCII paths are prefixed with "path:" and base64 paths are prefixed
with "base64:".

Implementors note: Is it necessary to normalize the strings (using NFD or NFC)
in order to be compatible with Windows?

Here is an example text representation of a file tree:

```
path:photos/img1.jpg
602aba74d093e7893e87c4ba4295021937087bc4
1379220393
2387629
base64:aW1hZ2VzL2VzcGHDsW9s4oCOLmpwZwo=
dbe2e1f6f295102b0b93d991ab4508979aa9433e
1379100421
6293123

path:photos/img3.jpg
1383030498
```

Then client first sends a "rsync_tree.signature".  The actual signature is a
binary payload.

```json
{
  "type": "rsync_tree.signature"
}
```

The server responds with a "rsync_tree.patch".  Once again, the patch is a
binary payload.

```json
{
  "type": "rsync_tree.patch"
}
```

The client then applies the patch to its representation of the tree that was
sent originally, and decodes the ASCII representation, and then finally applies
the conflict resolution algorithm as normal.

Note that in two-way sync that both peers send the initial signature at the
same time.


Gzip Extension
--------------

Official feature string "gzip".

The gzip extension compresses the wire protocol.  It uses the deflate algorithm
with the zlib header format, as defined in [RFC 1950](http://tools.ietf.org/html/rfc1950).

Once the connection is encrypted all future messages will be compressed.  Each
message is prefixed by its length in ASCII, followed by a colon, followed by
the compressed data.

Note: While this message delimitation and encoding method is less efficient
than is possible, it is quite simple, and the gains from compression will be
from the larger JSON and binary messages will more than make up for the loss of
efficiency in small messages.


Computer resources
------------------

This section is a set of recommendations for implementors and are not part of
the protocol.

The period between directory scans should be a multiple of the time it takes to
do rescans, for example, scans may be done every ten minutes, unless it takes
more than a minute to run a scan, in which case the scan won't be run until ten
times the time it took to run the scan.  This guarantees that scanning overhead
will be less than 10% of system load.

The client should run with low priority.  It should let the user pause sync
activity.

The client should and give battery users the option to not sync while on
battery.

Clients should implement rate limiting, as sync is intended as something that
will run in the background without interfering with normal usage.

Clients should also consider that many ISPs limit the amount of bandwidth that
can be consumed in a month, and software limits should be used to ensure that
the cap isn't exceeded.  At a minimum tracking the amount of bandwidth consumed
can help users determine if they will cause an overage.

The client should debounce files changes so that files that it can stop syncing
a file that is changed too frequently.

The client should not lock files for reading while syncing them so that the
user can continue normal operation.

The client should give the users a rough estimate of the amount of time
remaining to sync a share so that the user can manually transfer files through
sneakernet if necessary.

Users may be relying on your software to back up important files.  You may want
to alert the user (on both computers) if the share has not synced with its peer
if has been longer than certain threshold (perhaps defaulting to a week).

While it is not the designed use case of this protocol, some shares may have
hundreds or thousands of peers.  In this case it is recommended that
connections only be made to a few dozen of them, chosen at random.
