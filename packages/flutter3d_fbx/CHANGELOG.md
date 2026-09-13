## 0.6.0

* **In the workspace at the set's own number, and deliberately not on
  pub.dev.** A new package, the same reason `flutter3d_rig`/`flutter3d_cloth`
  carry this number unpublished: a pubspec that names every workspace
  package names one tree, whether or not every named package has gone out
  yet.
* **The skeleton, not the reader.** `FbxDecoder implements ModelDecoder`,
  recognising an FBX file by its magic and refusing to decode one — `fmt-29d`'s
  own row: a package for `fmt-24`'s binary/ASCII 7.x reader and `fmt-25`'s
  skins and animation to land in, rather than a decision those rows would
  otherwise have to make first.
