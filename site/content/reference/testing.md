---
description: Two independent golden sets, mutation-checking every new test, determinism and snapshots, and why only thirty of 1242 tests need a GPU.
---

# Testing

1242 tests across fifteen packages. About thirty of them need a GPU; the [architecture](/core/architecture/) is what keeps the number that low.

```bash
tool/ci.sh                                   # shaders, analyze, every test
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test) # plain Dart, no Flutter needed
```

## Two independent golden sets, not one

Thirty scenes are rendered twice: once through Impeller, once through the software rasteriser in `flutter3d_cpu`. Zero differing pixels, with a per-channel tolerance of 8.

<div class="why">
<p>Two independently written implementations agreeing is evidence; one implementation agreeing with itself is not. The second set also keeps thirty scenes checkable in a headless run, because only the Impeller half needs a device.</p>
</div>

`cross_backend_test.dart` compares them with per-scene budgets, and any new backend has to pass `flutter3d_conformance` before it counts as one.

## Every new test is written by breaking what it covers

Write the test. Break the code it covers. Watch the test fail. Name the mutation in a comment. Then fix the code.

<div class="why">
<p>This is not a ritual. In recent sessions the rule found three tests that <strong>could not fail</strong>: one read a single pixel, one never built the pipeline it claimed to check, and one asserted a guarantee a neighbouring class makes instead of the one under test. While the navigation grid was being written, six of seven mutations were caught immediately and the seventh — cutting a corner diagonally — went through, so a test for it was written. <strong>The check breaks more often than the code.</strong></p>
</div>

The same habit applies to golden images: swap one reference for another's and confirm the comparison fails. Five of six lighting goldens in this repository were byte-identical, because the scene's lighting model reached the UI field but never the materials, so every one rendered as PBR and every one passed.

## Determinism, and the snapshot that proves it

No step reads the system clock, and no step takes randomness except from an explicitly passed `Random`.

```dart
test('two runs of one seed agree', () {
  final a = play(seed: 7, inputs: recorded);
  final b = play(seed: 7, inputs: recorded);
  expect(a.save().toJson(), b.save().toJson());

  final c = play(seed: 7, inputs: recorded.withOneExtraPress());
  expect(c.save().toJson(), isNot(a.save().toJson()));
});
```

That third assertion matters as much as the first two. A determinism test where every run agrees might be testing determinism or might be testing that nothing happens.

<div class="note">
<p>Determinism here is for reproducible tests, replays and bug investigation — <strong>not</strong> for network synchronisation. A networked game on this stack would be server-authoritative precisely because bit-identical arithmetic cannot be guaranteed between the Dart VM and a browser.</p>
</div>

`GameRandom` exists because `math.Random` has no readable state, which makes it the one thing in a simulation that cannot be written down. The determinism test found a real defect on its first run: monster thinking was staggered across steps by `Object.hashCode`, which is an address, so two runs of the same seed diverged.

## What can be tested without a device

Everything except the Impeller goldens. In practice that means:

| Layer | Headless | Notes |
|---|---|---|
| Geometry, `MeshData`, shapes, tangents | Yes | No device is involved at any point |
| Scene graph, bounds, culling, framing, picking | Yes | `MeshNode` holds a `MeshGeometry`, not a `GpuMesh` |
| Decoders: glTF, OBJ, `.f3d` | Yes | The decoding layer names no graphics API |
| Draw-call sorting | Yes | `key_sort.dart` is arithmetic |
| Collision, sweeps, the character controller | Yes | Plain Dart under `dart test` |
| The whole simulation, both games | Yes | Including playing a level to its exit |
| A rendered frame | Yes | Through `flutter3d_cpu` |
| Impeller output | No | |

## Play the game in a test

The most valuable test in either game is the one that plays it.

```dart
test('the crypt can be finished', () {
  final game = loadCrypt();
  for (final (action, steps) in route) {
    for (var i = 0; i < steps; i++) {
      game.input.press(action);
      game.loop.advance(1 / 60);
      game.input.endStep();
    }
    game.input.release(action);
  }
  expect(game.sim.state, GameState.complete);
});
```

## And draw one frame anyway

<div class="warn">
<p>Three bugs shipped that every simulation test passed and a single rendered frame would have caught. That is why <code>flutter3d_cpu</code> is a dev dependency of both games rather than a curiosity, and why <code>test/frame_test.dart</code> exists in each.</p>
</div>

```dart
test('a frame renders', () {
  final renderer = Renderer.create(device: CpuRenderBackend(), /* ... */);
  final frame = renderer.render(width: 320, height: 180, scene: scene,
      views: <RenderView>[view], settings: const RenderSettings());
  expect(frame.drawCalls, greaterThan(0));
});
```

## The tests that hold the architecture

Four of them, and each one turns a rule into a fact.

| Test | What it refuses |
|---|---|
| `flutter3d_graphics/test/no_backend_test.dart` | A `flutter_gpu` import in the graphics vocabulary |
| `flutter3d/test/backend_is_contained_test.dart` | A backend import in the engine |
| `flutter3d_game/test/no_genre_test.dart` | Genre vocabulary in the game layer |
| Its twin in `flutter3d_bridge` | The same, one layer up |

Without them the rules would live only in a README, where nothing checks them.

## Coverage that moved with its fixtures

Four suites covering the game layer's own machinery — the level format, the validator, navigation, and buttons and trigger volumes — now run from the shooter package. Their fixtures are written in that game's vocabulary (`monster`, `key`, `torch`), so they moved rather than being rewritten blind.

The coverage still runs on every CI. What was lost is locality: content-free fixtures for those four have not been written.

## Frame capture as a measurement

```bash
flutter run -d macos \
  --dart-define=FLUTTER3D_CAPTURE=shot.png \
  --dart-define=FLUTTER3D_CAPTURE_FRAME=200 \
  --dart-define=FLUTTER3D_SPIN=false \
  --dart-define=FLUTTER3D_ANIM_TIME=0.75
```

`FLUTTER3D_SPIN=false` stops the turntable so two captures differ only by what is being tested, and `FLUTTER3D_ANIM_TIME` freezes a clip at a given second — without which two captures of an animated model are not comparable, because a format that loads faster starts playing sooner.

<div class="why">
<p>Three attempts at an A/B comparison in the shooter were spoiled by a synthetic keystroke not reaching the window. The fog A/B toggles on the clock instead, so the measurement no longer depends on the window manager cooperating.</p>
</div>
