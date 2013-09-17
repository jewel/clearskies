ClearSkies
==========

ClearSkies is a sync program similar to DropBox, except it does not require a
monthly fee.  Instead, you set up shares between two or more computers and the
sharing happens amongst them directly.

ClearSkies is inspired by BitTorrent Sync, but is has an open protocol, that
can be audited for security.

This repository contains the protocol documentation as well as an in-the-works
reference implementation.  The reference implementation is open source and free
software.


Core Protocol Features
----------------------

* Simple key sharing (pre-shared key)
* Read-write sharing
* Read-only sharing
* Encrypted backup sharing to an untrusted peer
* Encrypted connections
* Shallow copy (do not sync certain files from peer)
* Subtree copy (only sync certain directories from peer)
* Streaming support


Core Protocol Extensions
------------------------

* Rsync file transfer
* Gzip compression


Future Extensions
-----------------

* Media streaming (audio and video)
* Picture gallery
