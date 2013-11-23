Untrusted Extension
===================

This is an optional protocol feature.  The official feature string is
"untrusted".  Feature negotiation is covered in the core protocol
documentation.

This extension adds a new peer type, "untrusted", which only has access to
encrypted versions of the files.

A new "untrusted" PSK needs to be generated for the share.

FIXME How is the new PSK spread to other peers?  One place would be special
metadata on the root directory entry, but we don't have directory entries yet.

Some additional metadata is added for each file in the collection.  Per the
core spec, peers that don't have the "untrusted" extension will ignore these
attributes.  The first is a random 128-bit ID that never changes once added,
even if the file contents change, under the name of "untrusted.id".  The other
is an encryption key, in the "untrusted.key" field.

The key field holds an 128-bit encryption key and a 128-bit Initialization
Vector (IV), in that order.  The key is used to encrypt files when being sent
to untrusted peers.  They are predetermined so that all peers agree on how to
encrypt the file.



Untrusted Peers
---------------

Untrusted peers are given encrypted files, which they will then willingly send
to peers of all other types, including other untrusted peers.  Its behavior is
similar to how read-write and read-only peers interact when the
read_only_manifest extension is present.

What follows is a high-level overview of the entire operation of an untrusted
peer.  Detailed descriptions of each process are in later sections.

The peer's encrypted manifest is combined with a list of all relevant file IDs,
this is known as the untrusted manifest.  The result is then signed with the
read-only RSA key.

This manifest is sent to untrusted peers.  The untrusted peer stores the
manifest and then asks the read-only peer for each file, which is then saved to
disk.

When an untrusted peer connects to another untrusted peer, it sends an
untrusted manifest, which is built using one or more encrypted manifests, each
with a bitmask.

The SHA256 of the file isn't known until the file is encrypted, which doesn't
happen until the file is requested by an untrusted node.  Once calculated,
peers should store the hash value and include it in future file listings.

Untrusted peers can be given a cryptographic challenge by read-only and
read-write peers to see if they are actually storing files they claim to be
storing.


Untrusted Manifests
-------------------

Manifests are negotiated with the "get_manifest" and "manifest_current" messages
as usual.

A read-only or read-write peer will encrypt its manifest with the read-only
PSK, as described in the "File Encryption" section below, and the result is
base64 encoded.  This is encrypted with the read-only manifest is encrypted
with the read-only PSK and base64 encoded.  This is combined with the peer ID
and "version", as well as a list of all the file IDs and their sizes.  If the
SHA256 of the encrypted file is known, it should be added to the file.  Note
that the file list should only include files actually present on the peer, and
all deleted files.

The message is signed with the read-write or read-only RSA key (as appropriate
for the peer).

```json
{
  "type": "untrusted.manifest",
  "peer": "989a2afee79ec367c561e3857c438d56",
  "version": 1380082110,
  "manifest": "VGhpcyBpcyBzdXBwb3NlZCB0byBiZSB0aGUgZW5jcn...",
  "files": [
    {
      "id": "8adbd1cdaa0200747f6f2551ce2e1244",
      "utime": 1379220476,
      "size": 2387629
    },
    {
      "id": "eefacb80ad05fe664d6f0222060607c0",
      "utime": 1379318976,
      "size": 3932,
      "sha256": "220a60ecd4a3c32c282622a625a54db9ba0ff55b5ba9c29c7064a2bc358b6a3e"
    }
  ]
}
```

The manifest sent from an untrusted peer includes any manifests necessary to
prove that the files it has are legitimate and a bitmask:

```json
{
  "type": "untrusted.manifest",
  "peer": "7494ab07987ba112bd5c4f9857ccfb3f",
  "version": 1380084843,
  "sources": [
    {
      "manifest": "{\"type\":\"manifest\",\"peer\":\"989fac...}\nMC4CFQCEvTIi0bTukg9fz++hel4+wTXMdAIVALoBMcgmqHVB7lYpiJIcPGoX9ukC\n",
      "bitmask": "Lg=="
    }
  ]
}
```

This should follow the same manifest merging algorithm explained in an earlier
section.

The list of files is merged using the tree merging algorithm also as explained
earlier.

File change updates work in a similar manner to how they work between
read-write and read-only peers.  Here is a regular update from the earlier
section:

```json
{
  "type": "untrusted.update",
  "file": {
    "path": "photos/img1.jpg",
    "utime": 1379220476,
    "size": 2387629
    "mtime": [1379220393, 123518242],
    "mode": "0664",
    "sha256": "cf16aec13a8557cab5e5a5185691ab04f32f1e581cf0f8233be72ddeed7e7fc1",
    "id": "8adbd1cdaa0200747f6f2551ce2e1244",
    "key": "5121f93b5b2fe518fd2b1d33136ddc3361fd9c18cb94086d9a676a9166f9ac52"
  }
}
```

The entire message and its signature (separated by a newline), are encrypted
with the read-only PSK and put into a similar message containing the ID, size,
and sha256 of the encrypted contents (if known).  This message should be signed.

```json
{
  "type": "untrusted.update",
  "proof": "Z29vZCBncmllZiwgbW9yZSBmYWtlIGRhdGEuI...",
  "file": {
    "id": "8adbd1cdaa0200747f6f2551ce2e1244",
    "utime": 1379220476,
    "size": 2387629
  }
}
```

File moves do not require special handling (they are just sent with type
"update"), since the file ID is unique and only the encrypted metadata changed.

File deletes are handled as an "update" where the "deleted" member is set to
true.

Just like with read-write and read-only file changes, the change messages
should be appended to the copy of the manifest including their signatures.


Deduplicating on Untrusted Peers
--------------------------------

Since untrusted peers do not have access to the unencrypted SHA256, the
read-only and read-write peers need to help the untrusted peers know which file
IDs match, and when those file IDs stop matching.  A "matches" member is added
to the untrusted manifest on all but the first duplicate file (where "first" is
considered to be the file ID that is lowest when the hex value is sorted with
strcmp).

```json
{
  "type": "untrusted.manifest",
  "peer": "989a2afee79ec367c561e3857c438d56",
  "version": 1380082110,
  "manifest": "VGhpcyBpcyBzdXBwb3NlZCB0byBiZSB0aGUgZW5jcn...",
  "files": [
    {
      "id": "8adbd1cdaa0200747f6f2551ce2e1244",
      "utime": 1379220476,
      "size": 2387629
    },
    {
      "id": "eefacb80ad05fe664d6f0222060607c0",
      "utime": 1379318976,
      "size": 3932,
      "sha256": "220a60ecd4a3c32c282622a625a54db9ba0ff55b5ba9c29c7064a2bc358b6a3e"
    },
    {
      "id": "dd711c53e77e793bb77555a53a5feb84",
      "utime": 1379221088,
      "matches": "8adbd1cdaa0200747f6f2551ce2e1244"
    }
  ]
}
```


File Encryption
---------------

Encryption should be done with AES128 in CTR mode (CTR mode is seekable).  The
first sixteen bytes of the file are "ClearSkiesCrypt1".  A random encryption
key is chosen.  This is XOR'd with the encryption key and written as the next
16 bytes of the file.  The following 16 bytes in the file should be the
initialization vector (IV).  Then the encrypted data is written.  The last 32
bytes in the file should be the SHA256 of the file.


Untrusted Proof of Storage
--------------------------

Untrusted peers can be asked to prove that they are storing a file.  This is
I/O intensive for both peers, so some steps should be taken to reduce
unnecessary verification.  If there are read-write peers present on the
network, read-only peers should not perform any verification.  By default, the
rate of verification should be extremely low, perhaps a single file per day.

Software may support user-initiated full verifications.

A random file is chosen and a 32-byte random sequence is generated.  This is
sent to the untrusted peer.

The read-write peer then asks for file verification with a *signed* message:

```json
{
  "type": "untrusted.verify",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "prefix": "3d820dcc0ecad651e87fc84bb688bf7e6c7ee019ba47d9bdaaf6bc4bed2b9620"
}
```

The untrusted peer concatenates the 32-bytes and the entire contents of the
file and sends back the result:

```json
{
  "type": "untrusted.verify_result",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "result": "fff8acd78f7528c143cb5a6971f911d3869368cbc177f3f4404d945c6accc08d"
}
```

The read-write peer then uses the prefix and IV to recreate the experiment and
validate that resulting hash is correct.  If the hash is not correct, software
may notify the user, or it could change the file_id and encryption key for that
file so that the untrusted node re-downloads an undamaged version.

If an untrusted peer is overloaded, it may choose to ignore the proof-of-storage
request.  It may also send back a busy message:

```json
{
  "type": "untrusted.verify_busy",
  "file_id": "a0929405c4ff5a96ffeb8cbe672c82d4",
  "retry_in": 600
}
```

