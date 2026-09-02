---
description: Three independent golden sets, mutation-checking every new test, determinism and snapshots, and why only about thirty of 3130 tests need a GPU.
---

# Testing

3130 tests across 24 packages and five applications, counted the same way the `the document says how many tests there are` rule does: a scan of every `test(`/`testWidgets(` call. The rule holds `ARCHITECTURE.md` §13, the README and this page to the answer — the README went on saying 1242 across thirteen packages for as long as nothing compared it with anything. About thirty need a GPU; the [architecture](/core/architecture/) is what keeps the number that low.

| Package | Tests | | Package | Tests |
|---|---|---|---|---|
| `flutter3d` | 705 | | `flutter3d_particles` | 68 |
| `flutter3d_sim` | 336 | | `pad_input` | 59 |
| `flutter3d_game_shooter` | 291 | | `flutter3d_audio` | 52 |
| `apps/flutter3d_editor` | 194 | | `flutter3d_impeller` | 37 |
| `flutter3d_game_racing` | 193 | | `flutter3d_bridge` | 32 |
| `flutter3d_game_platformer` | 187 | | `flutter3d_webgl` | 31 |
| `apps/flutter3d_demo_platformer` | 168 | | `flutter3d_session` | 29 |
| `flutter3d_physics` | 137 | | `pointer_lock` | 28 |
| `apps/flutter3d_demo_racing` | 119 | | `flutter3d_hardware` | 17 |
| `flutter3d_cpu` | 112 | | `flutter3d_testing` | 7 |
| `flutter3d_screens` | 110 | | `apps/flutter3d_template_app` | 4 |
| `flutter3d_game` | 69 | | `flutter3d_backend` | 2 |
| `apps/flutter3d_demo_dungeon` | 69 | | `flutter3d_shaders` | 1 |

The rows sum to 3057 rather than 3063: the remaining six live in `packages/*/example/test`, which the count includes and this table does not.

`flutter3d_app` and `flutter3d_samples` are not in the table and have no `test/` at all. One is a barrel of thirty-five `export` lines and the other is test data with two path constants over it; what there is to check about them is structural, and other packages' decoder tests are what exercise the samples. `flutter3d_conformance` is missing for a different reason: it is invoked as a script harness rather than through `flutter test`, so it does not surface in a grep of `test(` calls either. See below for what that cost once.

```bash
tool/ci.sh                                   # shaders, analyze, every test
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test) # plain Dart, no Flutter needed
```

## Three independent golden sets, not one

Thirty-three scenes are rendered three times: through Impeller, through the software rasteriser in `flutter3d_cpu`, and through WebGL2 in a driven browser. Each backend is held to zero differing pixels against its own set, with a per-channel tolerance of 8.

<div class="why">
<p>Independently written implementations agreeing is evidence; one implementation agreeing with itself is not. The software set also keeps thirty-three scenes checkable in a headless run: recording the other two takes a GPU or a browser, but comparing the committed sets takes neither.</p>
</div>

`cross_backend_test.dart` compares them with per-scene budgets, and any new backend has to pass `flutter3d_conformance` before it counts as one.

<div class="warn">
<p>Flutter GPU requires Impeller, which a headless <code>flutter test</code> cannot give it, so the conformance harness has to be an application that somebody watches run. It was one — and stood there showing a pass list to a human — from the same commit that added a fix meant to be caught by it, until <code>packages/flutter3d_impeller/tool/conformance.sh</code> was written to actually run the suite and return its exit code. Once it did, the suite passed; nobody had known either way before then. The <code>the Impeller conformance runner is reachable</code> rule now keeps that script from going stale — checking that it exists, that it is executable, and that it and the entry point still agree about the line the verdict is read from.</p>
</div>

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

`GameRandom` exists because `math.Random` has no readable state, which makes it the one thing in a simulation that cannot be written down. The determinism test found a real defect on its first run: monster thinking was staggered across steps by `Object.hashCode`, which is an address, so two runs of the same seed diverged.

## The same tape on a different machine

Two runs agreeing in one process is the easy half. The half a verifying server needs is two runs agreeing on two *machines* — because a server that recomputes a submitted run only proves something if its arithmetic is the player's arithmetic.

This page used to say that could not be relied on. It had never been measured. `parity_test.dart` measures it, by digesting a simulation every twenty-five steps and comparing the digests across platforms.

| Scenario | Checkpoints matching, VM against Chrome |
|---|---|
| Character controller through a room of brushes | **40 of 40** |
| Arcade vehicle on flat ground | 17 of 40, first divergence at step 75 |

Both numbers come from the same day and the same machine, and they do not conflict. Of twelve `dart:math` functions asked about twenty thousand arguments each, only `sqrt` and `pow` give the same bits in both places; every transcendental differs, and so does every combination of them. Whether a run diverges is therefore a question about which arguments it reaches. Walking reaches almost no transcendental. Driving is made of them.

<div class="note">
<p><code>warning:</code> the first version of that table sampled twelve hand-picked arguments and reported eight of ten functions portable. It was an artefact of the sample size, and a substitution built on the wrong answer went into the vehicle before a wider sweep took it out. <strong>A test of where two implementations agree will report that they agree.</strong></p>
</div>

What this settles: a run can be replayed exactly on the platform it was played on, and cannot be compared bit for bit across platforms in a simulation built out of transcendentals. A verifier localises a mismatch to an interval and quarantines it; it does not call it cheating.

<div class="note">
<p><code>why:</code> a digest and not a comparison. Two machines cannot compare their worlds by sending each other their worlds — a snapshot is tens of kilobytes and a run is thousands of steps. <code>StateDigest</code> is 32-bit FNV-1a taken over bits rather than text, with the multiply done in halves so that no intermediate passes 2^53 and a browser gets the same number. <code>DigestTrace</code> takes a checkpoint every so many steps and names the first one two runs disagree at, which turns "the replay diverged" into an interval to bisect.</p>
</div>

## What can be tested without a device

Everything except the Impeller goldens. In practice that means:

| Layer | Headless | Notes |
|---|---|---|
| Geometry, `MeshData`, shapes, tangents | Yes | No device is involved at any point |
| Scene graph, bounds, culling, framing, picking | Yes | `MeshNode` holds a `MeshGeometry`, not a `GpuMesh` |
| Decoders: glTF, OBJ, `.f3d` | Yes | The decoding layer names no graphics API |
| Draw-call sorting | Yes | `key_sort.dart` is arithmetic |
| Collision, sweeps, the character controller | Yes | Plain Dart under `dart test` |
| The whole simulation, all three games | Yes | Including playing a level to its exit |
| A rendered frame | Yes | Through `flutter3d_cpu` |
| Impeller output | No | |

## Test doubles ship with the package they double

Four packages carry a `lib/testing.dart`. It is a separate library, so nothing a consumer builds pulls it in, and it is importable, which a `test/` directory is not:

```dart
import 'package:flutter3d_hardware/testing.dart';  // FakeBackend
import 'package:flutter3d_cpu/testing.dart';       // cpuTestDevice
import 'package:flutter3d_audio/testing.dart';     // soundTableIn
import 'package:flutter3d_screens/testing.dart';        // creditGaps
```

`FakeBackend` is a `GraphicsDevice` that draws nothing and records everything: which passes were opened, what they were attached to, what was bound, how many times it drew. `cpuTestDevice` is a `CpuDevice` with the builtin shaders and the two fallback textures a `Renderer` asks for.

<div class="why">
<p>Each of these was copied before it was shared, and the copies drifted. <code>FakeBackend</code> was 475 lines in two packages, identical down to a paragraph naming a test only one of them had, and the second copy was 26 lines behind, missing the very fields a test would reach for. The device-and-fallbacks helper was in eight files, always the same white albedo and the same flat normal typed out again.</p>
<p>A package cannot import another package's <code>test/</code>, which is why there were two copies rather than one. <code>lib/testing.dart</code> is what a package can import.</p>
</div>

`cpuTestDevice` stops short of building the `Renderer`, deliberately: `flutter3d_cpu` must not depend on `flutter3d`. A backend that could not be compiled without the engine would not be an implementation of an interface, it would be part of the engine. That is a rule, and one of the twenty-one checks it.

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
<p>Three bugs shipped that every simulation test passed and a single rendered frame would have caught. That is why <code>flutter3d_cpu</code> is a dev dependency of the games rather than a curiosity, and why <code>test/frame_test.dart</code> exists in each.</p>
</div>

```dart
test('a frame renders', () {
  final renderer = Renderer.create(device: CpuDevice(/* ... */));
  final frame = renderer.render(width: 320, height: 180, scene: scene,
      views: <RenderView>[view], settings: const RenderSettings());
  expect(frame.drawCalls, greaterThan(0));
});
```

## The rules that hold the architecture are not tests

They ask how the code is *arranged*: who imports what, what a name says, where a thing may live. A test asks what code *does*. They live in `tool/structure.dart` and run first:

```bash
dart run tool/structure.dart
```

Twenty-two rules, under a second. Nothing they read needs `pub get`, a shader bundle or a device, so finding out in minute four that a package imports a genre was finding out late what was knowable in second one.

| Rule | What it refuses |
|---|---|
| `no package names a genre` | A genre import, **and** a genre word: `oneWay`, `ammo` and `lapTime` import nothing and are the same leak |
| `the hardware layer names no graphics API` | `flutter_gpu` or Flutter in the graphics vocabulary |
| `the engine names no backend` | A backend import, or dependency, in `flutter3d` |
| `a genre package draws only where it says` | A renderer reached from a genre's simulation half, and an allowlist entry that has stopped drawing |
| `a genre package reaches no other genre` | A racer borrowing a platformer's runner |
| `nothing shares a mutable value as a constant` | `static final Vector3`, which the first caller to scale in place changes for the whole process |
| `a step reaches for no clock and no loose dice` | `Random()` and `DateTime.now()` in a simulation package |
| `each assembly has one home per application` | A second place that spawns a level or dresses it |
| `no test builds its own world` | A harness that is not the game, and so agrees with any bug the game has |
| `every exemption names a file that is there` | An allowlist entry whose file has moved, or whose case only resolves on macOS |
| `the compiled shader bundle is not older than its sources` | A bundle built before the GLSL was edited, which fails as `failed to bind texture` rather than as a shader behaving oddly |

Ten more check the lists against the workspace, every pubspec's floors and sibling constraints, a package for a dependency on an application, the applications for a silenced `print` and for the flag that turns the GPU on, the Impeller conformance runner for rot, and four numbers that go stale on their own: the test count, the golden scene count, the structure-rule count and the publishing order, each compared against the tree. A number in prose is a number nobody recounts, so the counting rules read this site's pages too.

<div class="why">
<p>These were a <code>boundaries_test.dart</code> in each package, and thirteen packages of twenty-one had none: all thirteen clean, and not one of them checked. A runner that walks <code>packages/</code> itself covers a package the day it exists rather than the day somebody remembers to add a file to it.</p>
</div>

### The detectors prove themselves first

Rule 6.3 applies to these more than to anything else: a scan behind a detector nobody has seen fail is a rule nobody is keeping. The genre scan once lived in two copies and one of them had already lost the check that it fired at all, so it passed whether or not the rule held.

So the detectors run against synthetic input before a single file is read. They must fire on `int ammo = 0;` and stay quiet on `overlaps`, `elapsed` and `collapse`, all three of which contain `lap`. A broken detector stops the run and no scan is reported, because a green scan behind one is worse than a red one: somebody believes it.

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
