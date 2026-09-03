## 0.4.2

* **A level can ask to be reflected.** `EntityTypes.reflectionProbe` is the
  format's word for a point a room is reflected from, and
  `ReflectionProbeKind` is the kind that validates one: `radius`,
  `intensity`, `faceSize`, `levels`, `near` and `far` are all optional and
  each is refused where the renderer would otherwise assert on it at load.
  Pure data to the simulation — nothing spawns and nothing is revealed — and
  a word a game has to put in its own vocabulary, so a game without probes
  reads the entity as unknown rather than growing a reflection it did not
  ask for.

## 0.4.1

* **Lightmaps.** `LightmapLayout` unwraps every visible brush face onto a
  planar atlas from the level alone, so the baker and the geometry agree
  without a table; `LightmapBaker` bakes the light the walls throw on each
  other by gathering — direct light with shadows through the level's own
  collision world, then bounces along cosine-weighted rays — seeded by the
  texel, so two bakes are the same bytes. `Lightmap` stores RGBM in RGBA8
  with a hash of the brushes, lights and materials, and
  `dart run flutter3d_sim:bake_lightmap` writes `<level>.lightmap.bin`.
  `BrushGeometry.build(lightmap:)` hands every vertex its second coordinate.
* **Jump links.** `NavGrid.bake(jumps:)` finds the gaps and ledges a
  `JumpReach` clears; a `FlowField` filters them by its own body's reach with
  the body's width added, relaxes them backwards at their distance plus two
  cells so a walk of equal length wins, and `jumpAt` says when the next step
  is a jump. `Navigation.jumpAhead` and `ActorSystem` take off through the
  controller's buffered request on the take-off cell.
* `Mind.heading`, for turning to face the way the field said.

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
