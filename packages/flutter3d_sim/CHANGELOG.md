## 0.4.2

* **A brush can say how it casts, not only whether.** `shadowCasting` in the
  document is one of `on`, `off`, `doubleSided` or `shadowsOnly` — the engine
  has had four modes since `ShadowCastingMode` was written and the format had
  two, so the two it could not ask for were the two it most needed: both faces
  recorded, for a wall one brush thick whose lit side and dark side are a
  metre apart, and a proxy that casts without being drawn. `Brush.castsShadow`
  is now the two-state view of `Brush.shadowCasting` and goes on meaning what
  it meant, an unknown word is refused with the four in the message, and a
  document that said nothing goes on saying nothing. Surfaces are batched by
  the mode rather than by the boolean, because a batch is the smallest thing
  that can answer.
* **A breach keeps the baked light on the walls it did not touch.**
  `Breaches.origins` says which authored brush each current brush was cut out
  of, and `BrushGeometry.build(origins:)` uses it to find the planned face a
  piece's face is part of and measure its place inside it —
  `LightmapLayout.uvOfPoint` and `isOnPlane` are that arithmetic. Before it,
  redrawing a level after one hole meant no atlas at all and every wall in
  every room fell back to flat ambient at once. The faces the blast itself
  made take the neutral texel, which is the one part of a breached wall
  nothing ever baked.
* **A level can ask to be reflected.** `EntityTypes.reflectionProbe` is the
  format's word for a point a room is reflected from, and
  `ReflectionProbeKind` is the kind that validates one: `radius`,
  `intensity`, `faceSize`, `levels`, `near` and `far` are all optional and
  each is refused where the renderer would otherwise assert on it at load.
  The two planes are resolved against the probe's own defaults before either
  is judged, so a document naming only a near plane past two hundred metres is
  refused here rather than at load: the far plane it did not name is still a
  far plane. Pure data to the simulation — nothing spawns and nothing is
  revealed — and
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
