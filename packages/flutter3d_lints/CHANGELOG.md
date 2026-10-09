## 1.0.0-rc.1

- **Code written against 0.8 is told what 1.0 changed, at each use.** Two
  more warnings come from the migration table:
  - `flutter3d_migrate` has a quick fix. It rewrites a deprecated capability
    getter on a `GraphicsDevice` into `features.has(...)` or `limits.…`,
    and turns `implements X` into `with X` on a `base` class, for the types
    1.0 made `base mixin class`es.
  - `flutter3d_migrate_by_hand` links the guide's line for a change a person
    has to make.

  Both use the resolved code, so a class of your own with a
  `supportsWireframe` is left alone. `dart fix` does not apply a plugin's
  fixes in bulk, so `dart run flutter3d_lints:migrate <project>` applies
  all of them across a project, puts a TODO above each use left for a
  person, and hides on a flutter3d import a name 1.0 started exporting
  that the project declares itself. `flutter3d_build:migrate` runs it.

- **A plugin's simulation code is held to the engine's rules.** Four
  analyzer rules, shipped as an analysis server plugin and enabled by
  listing the package under `plugins:` in `analysis_options.yaml`:
  `step_reads_no_clock`, `step_takes_seeded_random`,
  `step_uses_portable_math` and `step_prefixes_dart_math`. They are the
  rules `tool/structure.dart` holds this repository's packages to, put in
  the editor of anybody writing a step, because a replay is the same run
  only while every step computes the same thing on every machine.

- **Stronger than a text scan where a resolver can say more.** A
  transcendental is reported by what it resolves to, so a call through any
  prefix of `dart:math`, or through an unprefixed import, is found, and a
  class of the author's own named `Random` is not. A comment or a string
  that names a forbidden call is not reported.

- **Warnings, so enabling the plugin enables them.** Each can be turned off
  by name under `diagnostics:`, or silenced for a file that runs once a
  frame rather than in the step with
  `// ignore_for_file: flutter3d_lints/<rule>`.
