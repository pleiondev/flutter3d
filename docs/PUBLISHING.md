# Publishing

Everything here is ready to publish and **nothing is published**. This file is
the difference between those two sentences.

## What is decided

* **Licence: MIT**, `Copyright (c) 2026 Dmitrii Zolotov`. One `LICENSE` at the
  root and a copy in every package, because pub wants the file inside the
  archive.
* **All twenty packages go**, including the three genre packages
  (`flutter3d_game_shooter`, `flutter3d_game_platformer`, `flutter3d_game_racing`),
  `flutter3d_conformance` and `flutter3d_boundaries`. The names were checked
  against pub.dev and all twenty are free — verified against `http`, `provider`
  and `vector_math`, which answer 200, so a 404 means the name really is
  unclaimed rather than the check being broken.
* **`publish_to: none` stays until somebody decides to publish.** It is the one
  line between "prepared" and "on the internet", and removing it is deliberately
  not part of the preparation.

## What is prepared

* `LICENSE`, `CHANGELOG.md` and `README.md` in all twenty packages.
* `repository:` pointing at the GitHub remote in every pubspec.
* **Sibling dependencies are version constraints, not paths.** `pub publish`
  refuses a path dependency, and a workspace resolves `flutter3d_hardware:
  ^0.1.0` from the checkout anyway — so the same line works for a developer and
  for the server. This is why `flutter pub get` still works with nothing on
  pub.dev.
* `tool/publish_check.sh` runs `pub publish --dry-run` for every package, with
  `publish_to` temporarily removed, and puts the line back. CI runs it, so a
  package that loses its licence or grows a path dependency is caught on the day
  rather than on publishing day.

## The order, when the day comes

Dependencies first, or pub rejects a package whose sibling is not up yet:

1. `flutter3d_hardware`, `flutter3d_shaders`, `pad_input`, `pointer_lock`
2. `flutter3d_conformance`, `flutter3d_boundaries`
3. `flutter3d`
4. `flutter3d_impeller`, `flutter3d_webgl`, `flutter3d_cpu`,
   `flutter3d_particles`, `flutter3d_physics`
5. `flutter3d_game`, `flutter3d_audio`
6. `flutter3d_bridge`, `flutter3d_ui`
7. `flutter3d_session`
8. `flutter3d_game_shooter`, `flutter3d_game_platformer`, `flutter3d_game_racing`

Each step is: remove `publish_to: 'none'`, commit, `dart pub publish`.

## Not done, and deliberately

* **The applications are not packages.** `apps/` keeps its path dependencies and
  its `publish_to: none`; three demo games and an editor are things to clone, not
  things to depend on.
* **No `example/` in most packages.** pub scores a package higher with one, and
  an example nobody runs is worse than none — `packages/pad_input/example` exists
  because its tests are the only ones that drive the tool a controller is
  accepted with. The others are demonstrated by `apps/`, which the READMEs point
  at.
