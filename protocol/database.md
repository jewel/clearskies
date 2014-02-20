Database Extension
==================

This extension is an official extension that adds the ability to have a
distributed key-value store that is synchronized between two or more devices.
The official extension string is "database".



Access Levels
-------------

The core protocol supports peers of two types:

1. `read_write`.  These peers can change or delete data.

2. `read_only`.  These peers can read all data, but cannot change it.

A database can have any number of all the peer types.

All peers can spread data to any other peers.  Said another way, a read-only
peer does not need to get the data directly from a read-write peer, but can
receive it from another read-only peer.  Digital signatures are used to ensure
that there is no foul play.




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


Recommendations
---------------

While it is not the designed use case of this protocol, some clubs may have
hundreds or thousands of peers.  In this case, it is recommended that
connections only be made to a few dozen of them, chosen at random.  The data
will propagate through the club.
