File Sync extension
===================


FIXME Describe how record updates should be delayed until the associated file
contents have been received by the peer.

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


FIXME: Add negative response for "get" if the file isn't present.


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
