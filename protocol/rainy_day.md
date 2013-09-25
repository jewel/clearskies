Rainy Day Extension
===================

The rainy day extension is an extension that provides peer-to-peer backup or
archival amongst a large group of peers.  It's official feature string is
"rainy_day".

This file currently contains my personal notes on what the feature might
entail, it will be fleshed out at a later date.

* karmacounter or karmatracker server
  * given a ton of control over operation
  * there is more than one karmacounter, it's not expected to be global
  * peers trust karmacounter to a reasonable level
  * karmacounter tunings should be communicated to peers
  * karmacounter may let users self-segment; a family can back up to only each
    other without having to set up their own karmacounter

* 4MB chunks (smaller files count against karma equal to a single chunk)
* user can choose replication level
* respect bandwidth caps
* upload/download ratio can be tuned
* peer can choose replication level and bandwidth
* can RAID-style XOR improve the amount stored?

* peers are as dumb as possible to make this simple to implement, all
  complexity is in the karmacounter

* peers should be able to switch karmacounters without discarding all the data
  from the previous counter.  Perhaps IDs should be constant.  This will allow
  people to move to a new counter if the old one goes down without having to
  reupload all their files.

  Also old files shouldn't be removed right away, but should slowly be replaced.

* peers should track all the places it has uploaded its data so that it can
  restore without the karmacounter if necessary.  After 48 hours of a
  karmacounter being down peers should fail to an open state so that restores
  are still possible.

  * this doesn't make sense.  If the user still had the list of where the data
    was kept, he probably hasn't lost his own data yet.  Instead there would
    need to be a way to retrieve it directly from the peers with only a
    passphrase.

* peers can transfer sideways.  That way someone who wants a 3x replication
  level but only has a little upload bandwidth can just upload once, and then a
  different peer can replicate it for them to more peers.

* optional deduplication.  Users may opt in to deduplication, which will make a
  backup of something like the entire operating system require very 

* can be used to make sure sync works for someone with two devices where both
  aren't always on

* this could possibly be used as an archival solution for businesses where a
  local copy isn't even kept, and payment is given to the karmacounter who passes
  a portion of the money on to the peers

  * a paid backup service would also be possible
