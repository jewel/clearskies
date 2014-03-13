ClearSkies Daemon Control
=========================

This document defines the protocol used to control the clearskies daemon.
It is intended to be used for those who wish to implement alternate user
interfaces for the official daemon.  Other implementations are welcome to also
adapt it if desired.

This protocol is incomplete.  This draft covers version 1 of the protocol, but
more message types will be added without bumping the version.

By default, the daemon listens for connections on the unix socket residing at
$XDG_DATA_HOME/clearskies/control.


Wire protocol
-------------

The wire protocol consists of JSON messages, with all newline characters
removed.  Note that a string that contains a newline can still be sent; only
newlines created by pretty printing that must be removed.

Messages are synchronous and are responded to in order.  The response is also a
JSON message.  Messages may be pipelined, that is to say, a second message may
be sent to the server before the response to the first request has been
received.

For forwards compatibility, unrecognized keys should be ignored.  Unrecognized
messages should be given 

All example JSON messages in this document will have newlines added for
legibility, even though they must be sent over the wire without them.


Handshake
---------

On connection, the server will send a handshake message that will specify the
protocol version it is speaking.

```json
{
  "service": "ClearSkies Control",
  "software": "bitbox 1.37.1",
  "protocol": 1
}
```

The client then begins sending commands and waiting for responses.


Commands
--------

A command will have a "type" key.  Options to the command will be given as
other commands.  For example:

```json
{
  "type": "create_share",
  "path": "/home/catfat/Documents"
}
```

If the protocol is extended by an implementation, it should prefix its custom
commands with a period, followed by a javaesque reverse domain namespace, like
".com.github.jewel.messaging.chat_message"

Responses do not have any required keys.  If a command is executed successfully
and does not return any data, an empty JSON object will be given:

```json
{}
```

If an error occurs while attempting to execute a command, the response will
have an "error" key, and the associated value will contain a machine-readable
error condition.  A human-readable message should also be included.

```json
{
  "error": "EPERM",
  "message": "Permission denied to '/home/catfat/Documents'"
}
```


Daemon Control Commands
-----------------------

The daemon can be instructed to shutdown with the "stop" command.

Syncing can be suspended with the "pause" command and started again with the
"resume" command.

The "status" command gives information about conne

```json
{
  "paused": false,
  "tracking": true,
  "nat_punctured": true,
  "upload_rate": 12834,
  "download_rate": 1049292
}
```

The upload_rate and download_rate are in bytes per second.


Share Management Commands
-------------------------

Creating a new share is done with "create_share":

```json
{
  "type": "create_share",
  "path": "/home/fatcat/Documents"
}
```

Listing all shares is done with "list_shares".  The response looks like:
```json
{
  "shares": {
    "/home/fatcat/Documents": {
      "files": 350,
      "synced": false,
      ...
    }
  }
}

FIXME More to add in this section


Future
------

This document will be added to without bumping the protocol to version 2 until
it is actually being used by non-official clients or it covers all features.

Some of the obvious improvements are:

* listing peers
* listing remote file trees on peers
* streaming files from remote peers
* changing configuration options
* getting month-to-date bandwidth statistics
