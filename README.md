ClearSkies
==========

ClearSkies is a sync program similar to DropBox, except it does not require a
monthly fee.  Instead, you set up shares between two or more computers and the
sharing happens amongst them directly.

ClearSkies is inspired by BitTorrent Sync, but it has an open protocol that can
be audited for security.

This repository contains the protocol documentation as well as an in-the-works
proof-of-concept implementation.  The proof-of-concept implementation is open
source and free software, under the GPLv3 (see the LICENSE file for details.)


The Protocol
------------

The ClearSkies protocol has been documented and is in a draft state.  It can be
found in the `protocol/` directory.  `protocol/core.md` is a good starting
place.

The protocol features:

* Simple-to-share access codes
* Read-write sync
* Read-only sharing
* Encrypted backup sharing to an untrusted peer
* Encrypted connections
* Shallow copy (do not sync certain files from peer)
* Subtree copy (only sync certain directories from peer)
* Streaming support
* Rsync file transfer (extension)
* Gzip compression (extension)
* Media streaming (future extension)
* Photo thumbnails (future extension)


The Proof-of-Concept
--------------------

The proof-of-concept



More information
----------------

* [jewel's blog](http://stevenjewel.com).
