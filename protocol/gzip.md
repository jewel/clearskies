Gzip Extension
==============

This is an optional protocol feature.  The official feature string is "gzip".
Feature negotiation is covered in the core protocol documentation.

The gzip extension compresses the wire protocol.  It uses the deflate algorithm
with the zlib header format, as defined in 
[RFC 1950](http://tools.ietf.org/html/rfc1950).

Once the connection is encrypted all future messages will be compressed.  Each
message is prefixed by its length in ASCII, followed by a colon, followed by
the compressed data.

Note: While this message delimitation and encoding method not the most
efficient, it is quite simple, and the gains from compression of the
larger JSON and binary messages will more than make up for the loss of
efficiency in small messages.
