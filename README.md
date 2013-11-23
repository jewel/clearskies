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
found in the `protocol/` directory.
`[protocol/core.md](https://github.com/jewel/clearskies/blob/master/protocol/core.md)`
is a good starting place.

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


The Software
------------

The software in this repository is a proof-of-concept of the protocol, written
in ruby.  It (currently) consists of a background daemon and a command-line
interface to control that daemon.


Status
------

The software is currently barely functional, in read-write mode only.  It is
not yet ready for production use.  IT MAY EAT YOUR DATA.  Only use it on test
data or on data that you have backed up someplace safe.


Installation
------------

It is currently only tested on Linux.  (It may also work on OS X and Windows.)

If you already have a working ruby 1.9 or 2.0:

```bash
gem install rb-inotify ffi
```

Otherwise, installing dependencies on Ubuntu:

```bash
apt-get install libgnutls26 ruby1.9.1 librb-inotify-ruby1.9.1
```

Clone this repo:

```bash
git clone https://github.com/jewel/clearskies
```


To start and share a directory:

```bash
cd clearskies
./clearskies start # add --no-fork to run in foreground
./clearskies share ~/important-stuff --mode=read-write
```


This will print out a "SYNC" code.  Copy the code to the other computer, and
then add the share to begin syncing:

```bash
./clearskies attach $CODE ~/important-stuff
```


Contributing
------------

If you are a professional cryptographer with interest in this project, any
feedback on the protocol is welcome.

Other help is also welcome.  You can email jewel at clearskies@stevenjewel.com
for discussion that doesn't seem to fit well in the context of a github issue.


More Information
----------------

* [jewel's blog](http://stevenjewel.com)
