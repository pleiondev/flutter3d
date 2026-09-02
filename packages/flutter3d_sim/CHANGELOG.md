## 0.4.0

* First release. It is `flutter3d_game`'s inside, moved out whole: the fixed
  step, the entity store, the level format and its validator, saves, demos and
  the rewind buffer, world logic, actors, navigation, the camera rig and the
  maths. Nothing changed behaviour; the imports moved and the package boundary
  is new.
* **Plain Dart, and that is the reason it exists.** A server that verifies a
  submitted run has to replay it through the same simulation the player ran,
  and a Flutter SDK in that container is a blocker rather than an
  inconvenience. `flutter3d_game` keeps the eight files that reached Flutter —
  the touch and keyboard widgets, the `MediaQuery` read, the diagnostics sink —
  and re-exports this package, so no existing program changes a line.
* The boundary is a check, not a comment: `the simulation names no Flutter` in
  `tool/structure.dart` scans `lib/`, `test/` and `bin/`.
* `StateDigest` and `DigestTrace` come with it — a 32-bit digest over the bits
  of a snapshot, computed the same way in a browser as in the VM, and a
  checkpoint trace that names the first step two runs disagree at.
* `dart run flutter3d_sim:bake_visibility` moves here from `flutter3d_game`,
  where it had never needed Flutter either.
