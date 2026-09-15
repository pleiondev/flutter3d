---
name: flutter3d-game-one-assembly
description: Use when wiring a flutter3d game's run — subclassing RunSession, mounting it over flutter3d_app's SceneSurface, and the one-assembly rule a scan enforces.
---

# A run, over the surface every application shares

`SceneSurface` is `flutter3d_app`'s, because the modeller and the lessons hand a
frame to Flutter the same way a game does:

```dart
SceneSurface(
  renderer: renderer,
  scene: scene,
  view: view,
  settings: () => currentSettings,   // a function, called per frame
  onBeforeFrame: placeTheCamera,
)
```

**`settings` is a function rather than an object**, so anything derived from
where the camera ended up is derived after it got there. `onBeforeFrame` runs
immediately before the frame, which is where a camera reads the interpolated
pose. `FrameClock`, `FrameTimingLog` and `DidNotStart` sit beside it.

## A run

`RunSession<L>` is abstract over a game's loaded-level type. Implement the
questions only the game can answer:

```dart
final class MyRun extends RunSession<LoadedLevel> {
  MyRun({required super.firstLevel, required super.saves, super.onChanged});

  @override Future<LoadedLevel> open(String asset) => …;   // load and stage
  @override RunOutcome outcomeOf(LoadedLevel level) => …;
  @override String? nextOf(LoadedLevel level) => …;
  @override Snapshot snapshotOf(LoadedLevel level) => …;
  @override void restoreInto(LoadedLevel level, Snapshot snapshot) => …;
}
```

`begin()`, `load(asset, resume: …)`, `restart()`, `startOver()` and `observe()`
come with it. The optional hooks — `carryFrom`, `startFresh`, `close`, `onLost`,
`beforeNext` — default to doing nothing.

`RunSession` is an ordinary class with no state-management opinion.

## One assembly per game

**Every game has exactly one function that turns a level document into a run**,
and nothing else spawns a level. `dart run tool/structure.dart` reads every
application in the repository for it.

It is not a style preference: the platformer had six copies of its assembly and
they had drifted, and the dungeon had two, one of which proved the crypt
finishable with a loadout the game never gives anybody.

## What is deliberately not here

The title card and the loss screen, which are the face of a particular game. The
backend choice, which is `flutter3d_app`'s: a run takes its device as a value, so
one can be mounted over a `CpuDevice` in a test. And a season or championship:
nobody resumes a race half a lap in, so `snapshotOf` and `restoreInto` would be
two required overrides returning nothing.
