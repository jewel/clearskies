Rainy Day Extension
===================

The rainy day extension is an extension that provides peer-to-peer backup or
archival amongst a large group of peers.  It's official feature string is
"rainy_day".

* karmacounter or karmatracker server
  * given a ton of control over operation
  * there is more than one karmacounter
  * peers trust karmacounter to a reasonable level
  * karmacounter tunings should be communicated to peers
* 4MB chunks (smaller files count against karma)
* user can choose replication level
* respect bandwidth caps
* upload/download ratio can be tuned
* peer can choose replication level and bandwidth
* can RAID-style XOR improve the amount stored?

* peers are as dumb as possible to make this simple to implement
