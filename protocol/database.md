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
* `vector_clock`.  A [vector clock](http://en.wikipedia.org/wiki/Vector_Clock)
  for tracking causality for the file.  (This is how conflicts are detected.)
* `deleted`.  A boolean flag representing if the record has been deleted.

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
  "vector_clock": {
    "b934d9de020109fde790cd39acce73fc": 44,
    "d38a0af145c48b75289e72985e3cc50a": 35,
    "c35be68aadc0e208b6c71f7be77f2975": 43
  }
}
```

This is a signed message when a read-write peer is sending to a read-only peer.
(It's not necessary to sign when sending to between two read-write peers.)

Read-only peers should permanently store both the message and its signature so
that they can repeat it at a later time to other peers.

The receiver of an update should look at its database to see if the update is
already present.  If not, it should update the vector clock (as will be
explained later) and then repeat the message to all of its peers.  As an
optimization, implementations shouldn't repeat the message back to the peer
that just sent it.

It is legal to change the `key` on a record.  To facilitate this, the `uuid`
should be used to identify records.   (The `key` should still be unique,
however.)


Requesting Updates
------------------

When connecting to a peer for the first time and on subsequent connections,
it's necessary to load all records that have been updated since the last
connection.

In order to facilitate this, each peer keeps its own revision counter.  This is
a 64-bit integer that starts with one.  When a record change originates
locally, the revision counter is incremented by one and its value is written to
the `last_updated_rev` field.  The `last_updated_by` field is set to the peer
ID.

The local revision number does *not* increment when writing someone else's
changes to the database, only changes that originate locally.  Otherwise two
peers will start an endless update loop.

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
change, [vector clocks](http://en.wikipedia.org/wiki/Vector_clock) (VCs) are
used.  VCs track just enough history of a record to be able to determine if one
change to the record descended from another, or if the two changes happened
concurrently (or while one peer was disconnected).

Vector clocks are represented on the wire as a JSON object, with the peer ID as
the key and the clock number as a 64-bit integer, as can be seen in the
`vector_clock` field of the earlier `database.update` example:

```json
{
  "vector_clock": {
    "b934d9de020109fde790cd39acce73fc": 44,
    "d38a0af145c48b75289e72985e3cc50a": 35,
    "c35be68aadc0e208b6c71f7be77f2975": 43
  }
}
```

Note that the clock numbers in the vectors are not related to the revision
number from the previous section.

Vector clocks are updated according to the following rules:

1. At first all values are zero.

1. When a peer has a local change event, it updates its logical clock by one.

1. As part of sending a record to another peer, it updates its logical clock by
   one.

1. When a peer receives a record, it updates its logical clock by one and then
   updates each member to be the max of the current vector and incoming vector.

Just because the vector clock is changed when a record is received, doesn't
mean that the `last_changed_` fields or `update_time` should also be changed.

When a record is received, the VC should be compared with what is present in
the local record.  In the following list, the incoming VC will be called
`incoming`, and the existing local record will be called `current`.  Imagine we
have a comparison function called `before`.

* If both `incoming.before(current)` and `current.before(incoming)`, then the
  records are equal.  The incoming record can be discarded.
* If `incoming.before(current)`, then the incoming record can be discarded, as
  the local record descends from it.
* If `current.before(incoming)`, then the incoming record replaces the existing
  record, as the local record is outdated.
* If neither condition is true, then the records conflict.  Conflict resolution
  action will vary, as will be explained in more detail.  The resulting record
  should merge the two VCs as described above.

Applications need to decide what the most appropriate way to resolve the
conflict is for their dataset.  For example, they can choose to merge the two
records, or separate one of them into a new `uuid`.  The default way to resolve
conflicts when the application doesn't specify otherwise is to simply use the
record with the largest `update_time`.  (Note that this doesn't mean that the
largest `update_time` always wins even when there is no conflict, since the VC
will determine which event happened first even if a peer has a widely
inaccurate clock.)


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
