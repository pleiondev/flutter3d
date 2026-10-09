# flutter3d_lints

Analyzer rules for code that runs inside a flutter3d fixed step. A plugin's
simulation code is held to what the engine's own is: no wall clock, no dice
the machine seeds, no transcendental whose answer is the platform's libm.

A replay is the same run only while every step computes the same thing from
the same state, on every machine. A server that verifies a submitted run
replays it through the same simulation, so one `DateTime.now()` in a
plugin's step is a run the server rejects months later. These rules say so
in the editor, the day the line is written.

## The rules

| Rule | Reports | Instead |
|---|---|---|
| `step_reads_no_clock` | `DateTime.now()`, `Stopwatch` | the step count and the step's `dt` from the `LoopContext` |
| `step_takes_seeded_random` | `Random()` with no seed, `Random.secure()` | a `GameRandom` the step was handed, or `Random(seed)` |
| `step_uses_portable_math` | `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log`, `pow` from `dart:math` | `Portable.sin` and the rest, from `flutter3d_sim` |
| `step_prefixes_dart_math` | `import 'dart:math';` with no prefix | `import 'dart:math' as math;` |

`sqrt` is allowed: IEEE 754 requires a correctly rounded square root, so
every platform gives the one right answer.

With a resolver the rules ask what a name is, not how it is spelled:
`m.sin(x)` under `import 'dart:math' as m;` is reported, and a class of your
own called `Random` is not. A comment or a string that names a forbidden
call is not a call and is not reported.

## Enabling it

The rules ship as an analysis server plugin (Dart 3.10 and later). List the
package under the top-level `plugins:` section of the `analysis_options.yaml`
at the root of your package or workspace:

```yaml
plugins:
  flutter3d_lints: ^1.0.0-rc.1
```

`plugins:` is a section of its own, not a key under `analyzer:`, and it is
read only from the root options file. Restart the analysis server after
changing it. The rules are registered as warnings, so listing the plugin
turns all four on; to turn one off:

```yaml
plugins:
  flutter3d_lints:
    version: ^1.0.0-rc.1
    diagnostics:
      step_prefixes_dart_math: false
```

They show in the editor and in `dart analyze` and `flutter analyze`.

## Code that is not a step

The rules are for code a fixed step runs. A plugin package usually also has
code that runs once a frame: a camera, a particle's drift, a sound's pitch.
That code may read the frame's clock and call `dart:math`, because nothing
replays it. Plugins cannot be scoped from a nested options file, so say it
in the file:

```dart
// ignore_for_file: flutter3d_lints/step_uses_portable_math
```

or on the one line:

```dart
final watch = Stopwatch()..start(); // ignore: flutter3d_lints/step_reads_no_clock
```

A file-wide ignore is a sentence about the file. Write beside it why the
file is not a step, as this repository's own exemption tables do for theirs.

## Migrating from 0.8

The plugin also reports code written against flutter3d 0.8 that 1.0
changed, from the migration table in `flutter3d_build`:

| Diagnostic | Reports | Fix |
|---|---|---|
| `flutter3d_migrate` | a deprecated capability getter on a `GraphicsDevice`; `implements X` where 1.0 made `X` a `base mixin class` | the quick fix rewrites it |
| `flutter3d_migrate_by_hand` | a use a person has to change, such as `GameLoop` | the message links the guide's line for it |

`dart fix` does not apply a plugin's fixes in bulk. To apply them all
across a project:

```bash
dart pub global run flutter3d_lints:migrate [--dry-run] path/to/project
```

It also puts a `// TODO(flutter3d-1.0):` above each use left for a person.
Where 1.0 exports a new name that your project already declares, it hides
the new one on the flutter3d import. `dart run flutter3d_build:migrate`
runs it as one step of the whole migration. The guide is at
<https://flutter3d.pleion.dev/reference/migrating-to-1.0/>.

## For tooling of your own

`package:flutter3d_lints/flutter3d_lints.dart` exports `scanSimulationCode`,
which takes a parsed or resolved `CompilationUnit` and returns the findings,
and `simulationRules()`, the rules as the analysis server takes them.

## This repository

The engine's own packages are held to the same rules by
`tool/structure.dart` (rules 7 and 34, "a step reaches for no clock and no
loose dice" and "a step asks no machine for an answer"), not by this plugin.
The structure scan is the first step of CI and runs before `pub get`, so it
reads text and needs no analyzer. `test/mirrors_structure_test.dart` reads
the structure tool's source and fails when the two lists disagree.
