Read-Only Manifest Extension
============================

This is an optional protocol feature.  The official feature string is
"read_only_manifest".  Feature negotiation is explained in the core protocol
documentation.

This extension makes it possible for a read-only peer to give a manifest of its
files to untrusted peers (see the "untrusted" extension), other read-only
peers, and even read-write peers.


Read-Only Manifests
-------------------

A read-only peer cannot change files, but needs to prove to other read-only
peers that the files it has are genuine.  To do this, it saves the read-write
manifest and signature to disk whenever it receives it.  The manifest and
signature should be combined, with a newline separating them, and a newline
after the signature.

The read-only peer builds its own manifest from the read-write manifest, called
a read-only manifest.  When it does not have all the files mentioned in the
manifest, it includes a bitmask of the files it has, encoded as base64.

If there are two diverged read-write peers and a single read-only peer, there
will be multiple read-write manifests to choose from.  The read-only peer will
add both read-write manifests, with associated bitmasks, to its read-only
manifest.

Similar to the "version" of the read-write database, read-only clients should
keep a "version" number that changes only when its files change.  (Since it is
a read-only, a change would be due to something being downloaded.)

The read-only manifests do not need to be signed.  Here is an example, with the
read-write manifest abbreviated with an ellipsis for clarity:

```json
{
   "type": "read_only_manifest.manifest",
   "peer": "a41f814f0ee8ef695585245621babc69",
   "version": 1379997032,
   "sources": [
     {
       "manifest": "{\"type\":\"manifest\",\"peer\":\"489d80...}\nMC4CFQCEvTIi0bTukg9fz++hel4+wTXMdAIVALoBMcgmqHVB7lYpiJIcPGoX9ukC\n",
       "bitmask": "Lg=="
     }
   ]
```


Manifest Merging
----------------

When building the read-only manifest from two or more read-write manifests, the
read-write manifests from each peer should be examined in "version" order,
newest to oldest.  A manifest should only be included if it contains files that
the read-only peer actually has on disk.  Once all the files the read-only peer
has have been represented, it includes no more manifests.

In normal operation where the read-write peers have not diverged, this merging
strategy means that the read-only manifest will only contain one read-write
manifest.
