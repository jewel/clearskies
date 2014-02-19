Database Extension
==================


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

