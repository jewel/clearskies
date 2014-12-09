

64-bit Integers in JSON
-------------------

Integers in the JSON messages are usually 32-bit.  However, there are a few
places where a 64-bit integers are needed.  Javascript has a limitation as to
how much precision can be stored in an integer (since it uses floating-point
numbers everywhere), but JSON itself has no such limitation.  For example:

```json
{
  "path": "video-of-unusual-size.mp4",
  "size": 3762440519426216896
}
```


Datetime Values
---------------

Datetime values are represented in JSON according to ISO 8601, as strings.
Because this is a synchronization protocol, it's important to be able to
represent timestamps with nanosecond precision so that they can be
perfectly synchronized on both ends.

For example:

```json
{
  "path": "devious plan.txt",
  "mtime": "2014-03-30T12:35:29.113243778Z"
}
```
