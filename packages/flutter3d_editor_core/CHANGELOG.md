## 0.1.0

The headless half of the editor leaves the application.

* **The document layer is a package, and the reason is that nothing could
  depend on it.** `Editing`, `Handle`, `Picking`, `Placeable`, `Looks`, `OpenKind`,
  `Template` and `scaffold` were eight files in `apps/flutter3d_editor/lib/src`
  that named Flutter nowhere at all. Anything else that wanted them — a
  command-line linter for a level, a tool an agent speaks to, a service that
  validates an uploaded level before a player loads it — had to depend on an
  application, which `no package depends on an application` forbids and which
  pub cannot express in the first place: an application is not published, so
  such a dependency is true only inside this checkout.

* **Plain Dart, and the boundary is checked rather than described.** The eight
  files import `flutter3d_sim` rather than `flutter3d_game`, because every type
  the document is made of — `Level`, `Brush`, `LevelLight`, `EntityDef`,
  `EntityRegistry`, `LevelValidator`, `LevelIssue` — has been in the simulation
  since it stopped needing Flutter. `the simulation names no Flutter` in
  `tool/structure.dart` reads this package's `lib/` and `test/` and fails on the
  first `package:flutter/`, `package:flutter_test/` or `dart:ui`. It is the same
  rule `flutter3d_sim` has carried since its own split, generalised over a list
  of packages rather than copied into a thirty-first — and it keeps its name,
  which two documents and a site page quote.

* **What did not come.** `fly_camera.dart` stayed in the application because it
  reaches `package:flutter3d` for a camera, and `documents.dart` stayed because
  reading a file off a disk is the one thing a headless core has no business
  doing. Four test files came with the code and run under `dart test`; the two
  that hold the shipped templates against the genre packages stayed with the
  assets they read.
