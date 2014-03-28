Database Extension
==================

This extension is an official extension that adds the ability to have a
distributed key-value store that is synchronized between two or more devices.
The official extension string is "database".


Access Levels
-------------

The database extension has two access levels:

1. `read_write`.  These peers can change or delete data.

2. `read_only`.  These peers can read all data, but cannot change it.

A database can have any number of all the peer types.

All peers can spread data to any other peers.  Said another way, a read-only
peer does not need to get the data directly from a read-write peer, but can
receive it from another read-only peer.  Digital signatures are used to ensure
that there is no foul play.


Database Layout
---------------

The database is a key-value store.  Each key is a string.  The corresponding
values are JSON.

The key-value pair and some associated bookkeeping metadata are together called
a "record".  Here are the associated fields:

* `key`.  The user-chosen key for the file, a string.
* `value`.  The user-chosen value, JSON.
* `uuid`.  A unique 128-bit ID, chosen at random.
* `last_updated_by`.  An 128-bit unique ID of the last person to write to the
  record.
* `last_updated_rev`.  An integer representing the local counter of writes on
  the peer in the `last_updated_by` field.
* `update_time`.  Timestamp when the record was last updated.  Transmitted in
  ISO 8601 format.
* `itc`.  An Interval Tree Clock, stored as a variable length binary string,
  using the binary encoding described in [the associated
  paper](http://gsd.di.uminho.pt/members/cbm/ps/itc2008.pdf).  Transmitted as
  base64.
* `deleted`.  A boolean flag representing if the record has been deleted.
  Transmission optional when false.

Each of these fields will be explained in more detail in the following sections.


Record Changes
--------------

When a record is changed on a peer, the change is sent to all connected peers
for the club.

Here is an example update for a hypothetical photo sharing application:

```json
{
  "type": "database.update",
  "key": "photo-1234",
  "value": {
    "camera": "NIKON ...",
    "taken": "..."
  },
  "uuid": "9223bf8014507dca629123485dc3a207",
  "last_updated_by": "b934d9de020109fde790cd39acce73fc",
  "last_updated_rev": 15,
  "update_time": "2014-02-23T23:45:39Z",
  "itc": TODO
}
```

This is a signed message when a read-write peer is sending to a read-only peer.
(It's not necessary to sign when sending to between two read-write peers.)

Read-only peers should permanently store both the message and its signature so
that they can repeat it at a later time to other peers.

The receiver of an update should look at its database to see if the update is
already present.  If not, it should repeat the message to all of its peers
(except the peer that just barely sent it the message).

It is legal to change the `key` on a record.  To facilitate this, the `uuid`
should be used to identify records.   (The `key` should still be unique,
however.)


Requesting Updates
------------------

When connecting to a peer for the first time and on subsequent connections,
it's necessary to load all records that have been updated since the last
connection.

In order to facilitate this, each peer keeps its own revision counter.  This is
a 32-bit integer that starts with one.  When a record change originates
locally, the revision counter is incremented by one and its value is written to
the `last_updated_rev` field.  The `last_updated_by` field is set to a unique
ID for the peer.

The local revision number does *not* increment when writing someone else's
changes to the database, only changes that originate locally.  Otherwise two
peers will start an endless update loop.

The maximum value for the revision counter is 2^32-1.  It then wraps back to
one.  When this happens, a new local ID number should be generated.  For this
reason, this local ID number should not be the peer ID from the core protocol,
but a separate ID.

For clarity, the terms "client" and "server" will be used to describe the peer
requesting the updates and responding with the updates, respectively.  Note
that in practice this will be happening simultaneously in both directions.

When a client connects, it asks the server for any new updates, using the
highest known revision number for each peer in the club:

```json
{
  "type": "database.get_updates",
  "since": {
    "dd25d7ae1aaba6b44a66ae4ae04d21c9": 87,
    "7e9fcaceb65cb419363f553091dadc5e": 12,
    "19c620da0b2db5cdeb72027662829371": 182
  }
}
```

The highest known revision number can be found by scanning the entire database
and looking at the `last_updated_by` and `last_updated_rev` fields for each
record, but it is much more efficient to keep track of these values separately.

For illustrative purposes, here is an SQL query that could be used to find
these values:

```sql
SELECT last_changed_by, MAX(last_changed_rev) FROM example_db
GROUP BY last_changed_by
```

The server responds with zero or more `update` messages.  These can be found by
scanning the database and looking at the `last_updated_by` and
`last_updated_rev` fields.  They should be sorted by the `last_updated_rev`
value so that it is safe for the client to apply them in the order they are
received.  Also, any records with a `last_updated_by` value that was not part
of the `get_updates` message should also be included.

Once again, solely for illustrative purposes, here is an SQL query that could be
used to find the matching records:

```sql
SELECT * FROM example_db
WHERE last_changed_by = 'dd25d7ae1aaba6b44a66ae4ae04d21c9' AND last_changed_rev > 87
   OR last_changed_by = '7e9fcaceb65cb419363f553091dadc5e' AND last_changed_rev > 12
   OR last_changed_by = '19c620da0b2db5cdeb72027662829371' AND last_changed_rev > 182
   OR last_changed_by NOT IN (
     'dd25d7ae1aaba6b44a66ae4ae04d21c9',
     '7e9fcaceb65cb419363f553091dadc5e',
     '19c620da0b2db5cdeb72027662829371'
  )
ORDER BY last_updated_rev
```

Once a client sends a `get_updates` message, it is subscribed to all future
`update` messages that may be generated by the server on this connection.
(Clients may open more than one connection to a server, but only one should
be subscribed to updates.)

Note: It is imperative that records are sent and processed in order, with no
records skipped, or they will never be synced.


Conflicts
---------

Since offline operation is supported, it's possible that a record will be
changed on two peers at the same time.  Conflicts can also arise when a record
is changed concurrently on two connected peers.

There are two ways that conflicts are detected.  The first is when two records
with the same `key` are created on two different peers.  For example, the `key`
is used to represent file paths in the `directory` extension.  In this
scenario, two records with the same path but different `uuid` values can
appear.

The second source of conflict is when the same record is changed on two
different hosts.  To differentiate between a normal change and a conflicting
change,
[Interval Tree Clocks](https://github.com/ricardobcl/Interval-Tree-Clocks)
(ITCs) are used.  ITCs track just enough history of an object to be able to
determine if it descended from another.

There are a number of actions that can be taken on ITCs, namely `seed`,
`fork`, `peek`, `event`, `join`.  There is also a comparison operator, `leq`.
These are described in the
[paper](http://gsd.di.uminho.pt/members/cbm/ps/itc2008.pdf) and sample
implementations are available in the
[github project](https://github.com/ricardobcl/Interval-Tree-Clocks).

Applications need to decide what the most appropriate way to resolve the
conflict is for their dataset.  They can choose to merge the two records,
or separate one of them into a new `uuid`.  The default way to resolve
conflicts is to simply use the record with the largest `update_time`.  (Note
that this doesn't mean that it's safe to bypass the `itc` field in this case,
as the `itc` field's notion of causality trumps the value in the `update_time`
field.  This allows the system to behave rationally even in the presence of
incorrect system clocks.)


Manipulating the ITC field
--------------------------

When a record is first created, the `itc` should be set to the result of
calling `seed()`.

When a record is changed, `event` should be called, and the resulting ITC
should be written back to the record.

When a record is sent to another peer, `fork` should be called.  `fork` splits
the ITC into two new ITCs.  One of these should be stored back into the
database, and the other should be included in the message to the peer.

FIXME: This will cause problems with read-only peers not being able to replicate
due to signatures.  See
https://groups.google.com/d/msg/clearskies-dev/H-ORwSUMgWA/lma-ADQ9q2sJ

When a record is received, the ITC should be compared with what is present in
the local record, using the `leq` (less than or equal) function, which returns
a boolean.  The ITC from the incoming message will be called `new` and the
existing local ITC will be called old.

* If `new.leq(old)` and `old.leq(new)`, then the records are equal.  The
  incoming record can be discarded.
* If `new.leq(old)`, then the incoming record can be discarded, as the local
  record descends from it.  The ITC from the incoming record should be combined
  with the current record using `join`.
* If `old.leq(new)`, then the incoming record replaces the existing record.  The
  ITC values should be combined using `join`.
* If neither condition is true, then the records conflict.  Conflict resolution
  action will vary.  The resulting record should combine the ITC values with
  `join`.

TODO: There may be some errors in these ITC instructions as currently written.
Some minor changes may be necessary to use ITCs effectively.  The author intends
to do more research and update this section.


Deleted Records
---------------

Special care is needed with deleted record to ensure that "ghost" copies of
records don't reappear unexpectedly.

The solution chosen by ClearSkies is to track deleted records indefinitely.
Consider the following example of what would happen if these records were not
tracked:

1. Peers A, B, and C know about a record.
2. Only peers A and B are running.
3. The record is deleted on A.
4. B also deletes its record.
5. A disconnects.
6. C connects to B.  Since C has the record and B does not, the record
   reappears on B.
7. A reconnects to B.  The record reappears on A.


Recommendations
---------------

While it is not the designed use case of this protocol, some clubs may have
hundreds or thousands of peers.  In this case, it is recommended that
connections only be made to a few dozen of them, chosen at random.  The
database will still propagate through the club.


Known issues
------------

These issues will be addressed before the spec is finalized:

* A malicious read-only peer can cause the database to get out of sync by
  choosing to not relay some "update" messages.  We can fix this by having a
  "trusted" attribute for each database entry, and not setting it until we
  actually hear from a read-write peer.

  It would be nice if each update could include a reference to the previous
  update, but that won't work since the history that a read-only peer will have
  could be non-linear.

  Another possibility would be to use an inverse bloom filter (like gnunet),
  instead of the `last_updated_by` and `last_updated_rev` fields.
