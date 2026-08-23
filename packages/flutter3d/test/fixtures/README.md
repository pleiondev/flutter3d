# Test fixtures

Models the tests read and no application ships.

`hero.glb` lived in `apps/flutter3d_demo_platformer/assets/models/` until it did not: the
platformer stopped using it — the runner is `penguin.glb` — but the directory is
declared whole in that game's pubspec, so 424 KB of rigged character went into
every download of a game that never drew it. Two engine tests do draw it, which
is why it is here rather than deleted:

* `packages/flutter3d/test/hero_skin_sharing_test.dart` — four skins over one
  armature, which is the case that shipped broken twice;
* `packages/flutter3d_cpu/test/hero_frame_test.dart` — the same rig rendered,
  which is what caught the node scale.

Nothing in this directory is declared in any `pubspec.yaml`, and that is the
point: a test reads it off the disk with `File`, and a player never downloads it.

**Animated Platformer Character** by **Quaternius**, CC0 1.0 —
<https://poly.pizza/m/kKtL4zvS3n>. Public domain, so no attribution is owed;
recorded because a file with no provenance is how this repository got its one
release blocker.
