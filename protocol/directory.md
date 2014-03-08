Directory Extension
===================

This extension is an official extension that adds the ability to synchronize
a directory across multiple devices.  The official extension string is
"directory".

This extension depends on having the ["database"](database.md) extension
present.  It associates each database record with a file.


Database fields
---------------

The "key" value in the database is the file path.  It is a relative path, with
a leading slash.  Entries in the database without a leading slash should be
allowed, but ignored, as they are allowed for extensions or for future
features.  All slashes should be forward slashes, "/".

The database value should be a JSON object.  Two fields are required:

 * `size` - file size in bytes
 * `sha256` - SHA256 of file contents

There are more fields that are optional.  If an implementation does not support
them, values that were originally set by other peers should not be erased.

 * `mtime` - Timestamp when file was last modified
 * `unix_mode` - Unix mode bits, as an octal number

Directories should also have entries in the database, including the share's
root directory, "/".  The `size` and `sha256` entries should be null for
directory entries.

Extensions may add other per-file fields.  For example, a hypothetical "music"
extension might add a field to store the artist, title, and duration of a song
file.  These fields should be ignored if not understood, but preserved in the
database for other clients' benefit.  Custom fields should be named using the
same naming scheme as extensions as explained in the core protocol.  For
example, if IBM had made the music extension, the field would be
".com.ibm.music.duration".  (Note that the `gzip` extension will compress long
identifiers down to an efficient representation.)


Windows Compatibility
---------------------

Software running on an operating system that doesn't support all the characters
that unix supports in a filename, such as Microsoft Windows, must ensure
filenames with unsupported characters are handled properly, such as '\', '/',
':', '*', '?', '"', '<', '>', '|'.  The path used on disk can use URL encoding
for these characters, that is to say the percent character followed by two hex
digits.  The software should then keep an additional internal attribute that
tracks the original file path, and continue to interact with other peers as if
that were the file name on disk.

In a similar manner, Windows software should preserve unix mode bits.  A
read-only file in unix can be mapped to the read-only attribute in Windows.
Files that originate on Windows should be mapped to mode '0600' by default.

Windows clients will also need to transparently handle multiple files with the
same name but different case, such as Secret.txt and secret.txt.  It could
decide to map the second to _Secret.txt on disk, for example.


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
been completely scanned, since checksumming existing files can take quite a
while.  The scan should capture the entire list of files before checksumming
any of them, which will allow change tracking to work almost immediately.


File Change Notification
------------------------

Files should be monitored for changes when the user has read_write access
level.  This can be done with OS hooks, or if that is not possible, the
directory can be rescanned periodically.

File changes should be debounced, meaning that the software should wait a small
period of time (a second or two) to see if the file is further changed before
sending the update.  If it is changed during the interval, the software should
wait still longer.

The file entry is changed in the database and the change is replicated to other
peers as explained in the database extension, using the "database.update"
message.

It is the job of the detector to notice moved or renamed files whenever
possible.  In order to accomplish this, a full rescan should look at the entire
batch of changes before sending them to the other peer.


File Presence
-------------


Once connected, a peer should send a listing of what files it already has.
Since a full listing would be large, and a bitmask not possible, a
[bloom filter](http://en.wikipedia.org/wiki/Bloom_Filter) is used to tell the
peer which files are present.  Bloom filters trade the possibility of false
positives for space efficiency, which in the case of clearskies translates to
saved bandwidth.

A bloom filter sets one or more bits for each file.  The number of bits set per
file is called the `k` value.  Since the SHA256 of the file is already
computed, no further hashing is necessary.  The first 32-bits of the SHA256
checksum is used to set the first bit, the second 32-bits used to set the
second bit, etc.  This means that `k` can be between 1 and 8.

The sender can choose what size of bloom filter it would like to use.  This can
be tuned based on how many files there are total and how many are present
locally.  Additionally, the sender can tune its `k` value as it desires.

Once a size is chosen, it is used as a modulus to map the parts of the SHA256
to different bits in memory.  For example, assume a filter of 1000 bits is
chosen, with a `k` value of two and a SHA256 hash of
"c16987a16bc7f7dd45e341b855171e8d5c6577a70febd408fbe6d2a194c18224".  To add
this file to the filter, the first 32-bits of the SHA256 hash modulus 1000 is
taken to find the first bit to set.  This would be 0xc16987a1 % 1000 = 689.
Bit 689 is set to 1.  For the second 32-bits, it's 0x6bc7f7dd % 1000 = 229.

The bloom filter is sent using a `directory.bloom_filter` message:

```json
{
  "type": "FINISH_ME"
}
```

FIXME The description of how to build and query the bloom filter probably
belongs in its own file.


In order to avoid recalculating the entire bloom filter with each new
connection, a counting bloom filter can be kept in memory.  This can then be
compressed down to a normal bloom filter for transmittal.

Simple implementations do not need to implement the bloom filter and instead
should send a value of `0xff`.  This tells its peer to probe for files it needs
using trial and error.  The value of `0x00` means not to ask for any files,
unless overridden by a `directory.present` message (explained in the next
section).


Changes to File Presence
------------------------

FIXME write this section.  Perhaps it belongs above the bloom filter section.

Retrieving Files
----------------

Files should be asked for in a random order so that if many peers are involved
with the directory, the files spread as quickly as possible.

In this section, "client" and "server" are used to denote the peer receiving
and peer sending the file, respectively.

When the client wishes to retrieve the contents of a file, it sends the
following message:

```json
{
  "type": "directory.get",
  "sha256": "ceab2535bac962a9c9ec8a8ba98145fdb11bb077eaa05d87088688f7524dcb47",
  "range": [0, 100000]
}
```

File data is always requested by SHA256 checksum, not by path.

The "range" parameter is optional and allows the client to request only certain
bytes from the file.  The first number is the start byte, and the second number
is the number of bytes.

The server responds with the file data.  This will have a binary payload of the
file contents (encoding of the binary payload is explained in the "Wire
Protocol" section of the core protocol):

```
!{"type":"directory.data","sha256":"ceab25635...", ... }
100000
JFIF.123l;jkasaSDFasdfs...
0
```

A better look at the JSON above:

```json
{
  "type": "directory.data",
  "sha256": "ceab2535bac962a9c9ec8a8ba98145fdb11bb077eaa05d87088688f7524dcb47",
  "range": [0, 100000]
}
```

The receiver should write to a temporary file, perhaps with a ".!clearsky"
extension, until it has been fully received.  The SHA256 checksum should be
verified before replacing the original file.  On unix systems, rename() should
be used to overwrite the original file so that it is done atomically.

A check should be done on the destination file before replacing it to see if it
has been changed locally without the changes being noticed.  If so, the normal
conflict resolution would apply.

Remember that the protocol is asynchronous, so software may issue multiple
"get" requests in order to receive pipelined responses.  Pipelining will cause
a large speedup when small files are involved and latency is high.

If the client wants to receive multiple files concurrently, it should open up
another connection to the peer.

The server may choose to respond to multiple "get" requests out of order.

If a file does not exist on the server (perhaps because it has yet to be
downloaded from a third peer), the server should respond with a
`directory.not_present` message:

```json
{
  "type": "directory.not_present",
  "sha256": "ceab2535bac962a9c9ec8a8ba98145fdb11bb077eaa05d87088688f7524dcb47"
}
```

The server should respond to requests for files that it is unable to serve with
a `directory.get_error` message:

```json
{
  "type": "directory.get_error",
  "sha256": "ceab2535bac962a9c9ec8a8ba98145fdb11bb077eaa05d87088688f7524dcb47",
  "message": "Permission denied"
}
```

When a client receives an error from the server, it should not request the file
again for an extended period of time, at least several hours.


Conflicts
---------

If a file is changed on two peers at the same time, or changed on two peers
while at least one of those peers was offline, a conflict will occur.  See the
conflict portion of the database extension for an overview of how conflicts are
detected.

To resolve the conflict, the file with the record with the latest `update_time`
is kept automatically, so that the user can continue to work without
disruption.  The other file (hereafter called the loser) is preserved in the
same directory with a new name.  If a conflict is detected in `foo.txt`, the
loser will be named `foo.CONFLICT.$random.txt`, where `$random` is a random
eight character alphanumeric.

The loser's metadata should include the `conflict_source` field, which
references the `uuid` of the original record.  This is so that GUIs can add
additional helpers for resolving conflicts if desired.  Also, read-only peers
can choose not to sync conflict files, since the conflict can not be resolved
from those peers.

The loser's record should be added to the database and propagated to other
peers, just like any other file.  This lets the user resolve the conflict from
any device instead of just from the device that happened to detect the
conflict.


Local file changes
------------------

Since database changes will be synced before the underlying files, some extra
work is needed to give a seamless experience.  When a database entry is
replaced, a temporary copy of the previous contents should be kept locally.
That way, if the file is changed locally before the new version can be
downloaded, there is enough information to create a new file entry.  (This
would result in a conflict being created once the remote file has finally
downloaded.)


Archival
--------

When files are changed or deleted on one peer, the other peer may opt to save
copies in an archival directory, which may be the system recycle bin.  If an
archive is kept, it is recommended that the SHA256 of these files is still
tracked so that they can be used for deduplication in the future.


Deduplication
-------------

The SHA256 checksum should be used to avoid requesting duplicate files when
already present somewhere else in the local directory.  Instead, a copy of the
local file should be used.


Ignoring Files
--------------

Software may choose to allow the user to ignore files with certain extensions
or that match a pattern.  These files won't be sent to peers.


Subtree Copy
------------

Software may support the ability to only sync a single subdirectory.
This does not require peer cooperation or knowledge.


Partial Copy
------------

Software may opt to implement the ability to not sync some folders or files
from the peer.

The software may let the user specify extensions not to sync, give them the
ability to match patterns, or give them a GUI to pick files or folders to
avoid.


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
remaining to sync a directory so that the user can manually transfer files
through sneakernet if necessary.

Users may be relying on the software to back up important files.  The software
may want to alert the user if the directory has not synced with its peer after
a certain threshold (perhaps defaulting to a week).

Software can rescan files from time-to-time to detect files that cannot be read
from disk or that have become corrupted, and replace them with good copies from
other peers.

Software should detect when a directory is on a removable device, and put the
directory in a soft error state when the device is not present.  (As opposed to
deleting all the files in the corresponding directory on the peers!)

Similarly, if the root directory that was shared is missing, the software
should go into an error state instead of treating this as a deletion.  (A
common reason this can happen is that a secondary mount point might not be
mounted.)

Software may choose to create read-only directories, and read-only files, in
read-only mode, so that a user doesn't make changes that will be immediately
overwritten.  It could detect changes in the read-only directory and warn the
user that they will not be saved.
