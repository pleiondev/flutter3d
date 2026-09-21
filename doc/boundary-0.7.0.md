# Which packages there are — decisions for the 0.7.0 release

0.5.0 was about which types a game may extend. 0.7.0 is about which packages
exist. Between 0.6.0 and this release seven packages were folded into others,
four published names stopped having any code behind them, and fourteen packages
go to pub.dev for the first time. An importer of 0.6.0 changes import lines and
little else; this document is the list of which lines.

The merges were decided by Dmitrii on 2026-09-13 and 2026-09-15 and are argued
in `docs/package-architecture-review.md` and `doc/package-merge-plan.md`. The
release itself, what goes on which number and when it is published, was decided
on 2026-09-19.

## Names that end

Published on pub.dev at 0.6.0, and no longer in the tree. Each is marked
`discontinued` with a `replaced_by` on the day 0.7.0 is published. pub.dev
takes one replacement per name, which is the third column; where the code went
two ways the fourth says so.

| Name | Folded in | `replaced_by` | Where its code is |
|---|---|---|---|
| `flutter3d_backend` | `d18dc0c6` | `flutter3d_app` | `openDevice` and `presentFrame`, behind the same conditional export |
| `flutter3d_screens` | `adde9300`, then `5b1be3be` | `flutter3d_game` | went into `flutter3d_session` first, and followed it |
| `flutter3d_session` | `5b1be3be` | `flutter3d_app` | split. `SceneSurface`, `FrameClock`, `FrameTimingLog`, `WidgetSurface`, `LevelLoader` and storage are in `flutter3d_app`; `RunSession`, the run timeline and the game's screens are in `flutter3d_game` |
| `flutter3d_bridge` | `5b1be3be` | `flutter3d_game` | `ActorVisuals`, `FixtureVisuals` and sound occlusion; loading a level into a scene went to `flutter3d_app` |

"Before 1.0, published names may freely go `discontinued` with `replaced_by`;
everything ships in one 0.7.0 release" is the decision, from the review's §8.

## Names that were never published

Nothing to do on pub.dev for these. They were workspace packages that a caller
outside the repository could not have depended on.

| Name | Folded in | Now |
|---|---|---|
| `flutter3d_geometry`, `flutter3d_formats`, `flutter3d_fbx` | `917dc95d` | `package:flutter3d_core/geometry.dart` and `package:flutter3d_core/formats.dart` |
| `flutter3d_particles_core` | `b3aaa2e0` | `flutter3d_particles`, which is plain Dart as a result |
| `flutter3d_rig`, `flutter3d_render_job` | `e765e0a7`, `623f32a7` | `flutter3d_model_core` |
| `flutter3d_render_mcp` | `5ee894e9` | `flutter3d_sim_mcp`, as `DiagnosticMcpServer` beside `SimMcpServer` |
| `flutter3d_twin` | `795487b5` | out of the repository. Digital twins are built above the engine, in a project of their own |

Not accepted, and so not in the table: folding `flutter3d_mesh` into
`flutter3d_model_core`, and deleting `flutter3d_net_webrtc`.

## Names that begin

Fourteen packages are published for the first time, and all of them at 0.7.0:
`flutter3d_core`, `flutter3d_mesh`, `flutter3d_model_core`,
`flutter3d_model_mcp`, `flutter3d_sim_mcp`, `flutter3d_net`,
`flutter3d_net_webrtc`, `flutter3d_stereo`, `flutter3d_lab`,
`flutter3d_mcp_kit`, `flutter3d_build`, `flutter3d_editor_widgets`,
`flutter3d_game_strategy` and `flame_flutter3d` — the last of them added to
the workspace after this document was first written, and a bridge to a
second engine rather than a genre or an internal split like the rest of the
list.

Four of them carried 0.1.0, 0.1.1 or 0.3.0 in the tree. A first publication at
0.7.0 skips numbers nobody outside ever saw, and buys the thing the shelf is
for: one number names one tree. `^0.7.0` on any `flutter3d_*` package resolves
against every other.

## What keeps its own number

`pad_input` and `pointer_lock` stay at 0.4.1 and `flutter3d_samples` goes out
as 0.4.3. They depend on no sibling and nothing in them changed, so a 0.7.0 of
any of them would be a release with nothing in it. `ARCHITECTURE.md` §16 gave
the same reason at 0.6.0 and the rule is unchanged.

## What breaks for an importer of 0.6.0

- **Re-exports are gone, and that is most of it.** `flutter3d_app` no longer
  re-exports `flutter3d_session`, `pad_input` and `pointer_lock`, and
  `flutter3d_game` no longer re-exports `flutter3d_sim`. A file that used a
  name through one of those imports the package that owns it.
- **`flutter3d` still hands over the geometry and the formats, from somewhere
  else.** `package:flutter3d/flutter3d.dart` exports `flutter3d_core.dart`,
  which exports both libraries, so `MeshData` or `GltfLoader` through the one
  import resolves as it did. What changed is where they live: a file that
  reached into `package:flutter3d/src/...` for them, or depended on
  `flutter3d_geometry` or `flutter3d_formats` by name, names
  `package:flutter3d_core/geometry.dart` or `formats.dart` instead.
- **A genre's widgets are in its `bridge.dart`.** The shooter, the platformer
  and racing each kept HUD widgets in their main library, which made a
  simulation's barrel name Flutter. `package:flutter3d_game_shooter/bridge.dart`
  and its two siblings hold them now, and the main library names no Flutter.
  The package still depends on the SDK, for that `bridge.dart`, so it is not
  one of the plain Dart packages and a bare `dart pub get` does not resolve it.
- **`RenderSnapshotJob` takes its device.** It built a `CpuDevice` by default,
  which is why a Flutter-free package depended on the software rasteriser.
- **A backend has more to implement.** `GraphicsDevice.present` is gone, and
  the interface gained `overwriteGeometry`, `overwriteTexture` and
  `maxColorAttachments` as abstract members. `SceneSurface` takes a required
  `presentFrame`, and `uploadEncodedImage` a required `decodeImage`.
- **Three lists grew, which breaks an exhaustive `switch` over them**:
  `LightType.area`, `MaterialAlphaMode.hashed` and `ModelFormat.stl`.
- **A recorded run from 0.6.0 does not open.** `Demo` requires `levelHash`,
  `buildStamp` and `checkpoints`, so that a replay can be checked against the
  level and the run it claims to repeat. `formatVersion` is still 1, so the
  refusal says the file names no level hash and not that it is old.
- **The four ended names above.** Each line of an import moves to the package
  in the fourth column.

Each package's own `CHANGELOG.md` says this for that package.

## The rules that hold this in place

- **`the publishing order names every package`** reads the list under *The
  order, used on the day* in `ARCHITECTURE.md` §16 and the directories under
  `packages/`, and fails on a name in one and not the other, either way round.
  A folded package that left a directory behind, or a new one nobody put in the
  order, is a red scan.
- **`every package agrees about versions with the workspace`** checks that each
  caret constraint on a sibling admits the version that sibling declares. It is
  why this release rewrote sixty-two constraints at once: `^0.6.0` does not
  admit 0.7.0, and neither did the `^0.1.0` twelve packages had on
  `flutter3d_core`.
- **`the simulation names no Flutter`** is what the `bridge.dart` split is held
  by: it reads a genre's simulation files for an import that reaches Flutter.
  `tool/flat_dart_check.sh` is the stronger check and covers the fifteen plain
  Dart packages, resolving each with a bare `dart pub get` in a directory with
  no workspace above it. The genres are not among the fifteen.
- **The enum rule of 0.5.0 already reads the fourteen new packages.** Every
  enum in them has its reason in `boundaryEnumExempt` — `flame_flutter3d`'s
  `SyncDirection` and `PlaneAxis` among them — so publishing them opens no
  closed list to somebody else's `switch` that was not argued for first.

## What does not happen on the day the tree is ready

The tree is prepared in full and `pub publish` waits. `rel-06` has been held
since 2026-09-09 behind `rel-16`, five to ten people walking the modeller's
tutorial against a clock, and on 2026-09-19 the owner kept that gate. So the
order is: the modeller is published to `models.pleion.dev`, because the cohort
walks it there; the cohort runs; then the nine tiers go out in the order §16
gives, the tag `v0.7.0` is put on the commit that was published, and the four
names above are marked.

**Until then, a deploy from this tree carries one obligation rather than a
ban.** The site's own quickstart names `^0.7.0` in its pubspec example, which
resolves nowhere on pub.dev until this tree is published — so that example
carries its own warning, pointing a reader at `^0.6.0` or at building from
the repository instead, the same distinction the repository's own README
already draws.
flutter3d.pleion.dev was deployed several times before 0.7.0 shipped, to
carry other work this tree had finished — the Flame bridge, its showcase
category, `flutter3d_demo_arcade` — and the quickstart warning is what makes
that safe to have done: the one page that could have misled a reader now
says plainly that it has not shipped yet.
