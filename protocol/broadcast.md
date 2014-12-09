LAN Broadcast
=============

This is part of the core clearskies protocol.  It specificies how to find peers
on the local network.

Peers are discovered on the LAN by a UDP broadcast to port 60106.  The
broadcast contains the following JSON payload:

```json
{
  "name": "ClearSkiesBroadcast",
  "version": 1,
  "id": "adf6447b553841835aaa712219e01f10486fd1003b1324e94de59f5646b060f3",
  "peer": "2a3728dca353324de4d6bfbebf2128d9",
  "myport": 40121
}
```

The ID is the key ID or access ID that the software is aware of.

The Broadcast message is versioned separately.  For example, the overall
protocol might go to version 2 but the Broadcast will stay at version 1 (if it
hasn't changed).

Broadcast should be sent on startup, when a new club is added, when a new
network connection is detected, when a new access id is created, and every
minute or so afterwards.
