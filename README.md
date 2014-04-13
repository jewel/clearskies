ClearSkies
==========

ClearSkies is a sync program similar to DropBox, except it does not require a
monthly fee.  Instead, you set up shares between two or more computers and the
sharing happens amongst them directly.

ClearSkies is inspired by BitTorrent Sync, but it has an open protocol that can
be audited for security.

The protocol is layered in such a way that other applications can take advantage
of it for purposes other than file sync.


The Protocol
------------

The ClearSkies protocol has been documented and is in a draft state.  It can be
found in the `protocol/` directory.
[protocol/core.md](https://github.com/jewel/clearskies/blob/master/protocol/core.md)
is a good starting place.

The protocol features:

* Simple-to-share access codes
* Read-write sync
* Read-only sharing
* Encrypted connections
* Shallow copy (do not sync certain files from peer)
* Subtree copy (only sync certain directories from peer)
* Streaming support
* Rsync file transfer (extension)
* Gzip compression (extension)
* Encrypted backup sharing to an untrusted peer (future extension)
* Media streaming (future extension)
* Photo thumbnails (future extension)

The protocol is designed to be a common base for other sync programs, so that
they can interoperate with each other.  For example, a hypothetical
wifi-enabled MIDI piano could speak the protocol and thereby sync its saved
files to the owner's computer or tablet, without the piano manufacturer needing
to write any PC or tablet software.


Where's the code?
-----------------

We are focusing our effort on making a C++ implementation,
[clearskies_core](https://github.com/larroy/clearskies_core).  The C++ library
will be portable to a wide variety of operating systems, including Windows,
Android and iOS.

The C++ daemon is being built for Android in [this
repository](https://github.com/cachapa/clearskies_core_android).

There is a [proof-of-concept](https://github.com/jewel/clearskies-ruby) of the
protocol that is written in ruby.  It is currently out-of-date in relation to
the latest protocol changes.

There is a [python control library](https://github.com/shish/python-clearskies)
and also a [Desktop GUI](https://github.com/shish/clearskies-gui).

There is an effort to get the ruby proof-of-concept to run under jruby on
Android in [this repository](https://github.com/onionjake/clearskies-ruboto).

Debian/Ubuntu packages of the ruby proof-of-concept are also
[available](https://github.com/rubiojr/clearskies-packages).


Security
--------

The software does not attempt to provide anonymity.  Access code sharing is
designed to reduce the impact of surveillance by using one-time codes by
default, and using perfect forward secrecy on the wire.

Setup of a share is vulnerable to an active man-in-the-middle attack if the
channel used to send the access code is insecure.

For example, if Bob sends Alice an access code over SMS, Eve can try to connect
to Bob before Alice does.  Alice will not be able to connect to the share.  Eve
can even create another share and issue the same access code to fool Alice into
thinking she has connected to Bob.

It is believed that security-conscious users will automatically avoid this
problem by sharing the access codes over secure channels.


Contributing
------------

If you are a professional cryptographer with interest in this project, any
feedback on the protocol is very welcome.

A major area that needs work is creating GUIs for each platform, such as GTK,
Cocoa, QT, Android, iOS, browser-based, and a Windows program.  GUIs do not
need to be written in any particular language, since they can control the
daemon using a simple JSON protocol, which is documented in
`protocol/control.md`.

Issues and pull requests are welcome.

The project mailing list is on [google
groups](https://groups.google.com/group/clearskies-dev).  (It is possible to
participate via email if you do not have a google account.)
