Code Spreading Extension
=======================

This is an optional protocol extension.  The official extension string is
"code_spread".  Extension negotiation is covered in the core protocol
documentation.

This extension makes it possible for access codes to be spread amongst all
peers for a share, instead of only residing at the original creator.  This is
useful when a single access code is used to grant access to a share that will
be used by a group of people over a long period of time, such as in a work
environment.


Spreading Access Codes
----------------------

Long-lived access codes are shared with other peers so that the originating
peer does not need to stay online.

Access codes should only be given to peers with the same or higher security
level as the level the code grants.  For example, a read-only code created on a
read-write peer should spread to all read-write peers, and all read-only peers.
A read-only code created on a read-only peer should also spread to all
read-only and read-write peers.  A read-write code can only be created on a
read-write peer and spread to other read-write peers.

Since access codes are short and created rarely, all known access codes are
sent when the connection is first opened.

Access codes should be kept locally in a database.  Each record has a "utime"
timestamp and should only be replaced with a record with a newer timestamp.  To
stop read-only peers from being able to fill up the hard drive of other peers,
software may rate-limit access code updates.

Access codes can be revoked and single-use access codes are marked as used.
They should not be removed from the database until they expire, if time limited,
otherwise they should be kept indefinitely.

Passphrases are not stored verbatim but instead the SHA256(SHA256(...)) is
stored.  Note that this is a 256-bit access code instead of the usual 128-bit
codes.

When first connected to a peer, all known access codes should be sent.
Thereafter, only database updates need to be sent.  Updates do not need to be
relayed.

The "code_spread.list" message is used for the initial list, and subsequent
updates send an "code_spread.update".  Here is an example message, which shows
an access code of each type:


```json
{
  "type": "code_spread.update",
  "codes": [
    {
      "code": "a0929405c4ff5a96ffeb8cbe672c82d4",
      "one_time": true,
      "created": 1379735175,
      "expiration": 1379744200,
      "utime": 1379735175
    },
    {
      "code": "e47c0685fe4bad29cdc0a7bdbd5335cb",
      "created": 1379744627,
      "expiration": false,
      "utime": 1379744627
    },
    {
      "code": "ed384f58875d01e242293142eed75a7a",
      "created": 1379741016,
      "expiration": false,
      "revoked": true,
      "utime": 1379744623
    },
    {
      "code": "61a08703a6a4c774cad650afaedd9c10",
      "created": 1379744460,
      "one_time": true,
      "used": true,
      "expiration": false,
      "utime": 1379744616
    },
    {
      "code": "19ababf69f21cf018e846bb90ecac80cddfa532c5aae97acc99172b5be529fb7",
      "created": 1379744616,
      "one_time": true,
      "expiration": 1379744611
      "utime": 1379744616
    }
  ]
}
```

