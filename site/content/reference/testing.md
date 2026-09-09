---
description: Three independent golden sets and a fourth being recorded, mutation-checking every new test, determinism and snapshots, and why only about thirty of 4381 tests need a GPU.
---

# Testing

4381 tests across 33 packages and seven applications, counted the same way the `the document says how many tests there are` rule does: a scan of every `test(`/`testWidgets(` call. The rule holds `ARCHITECTURE.md` §13, the README and this page to the answer — the README went on saying 1242 across thirteen packages for as long as nothing compared it with anything. About thirty need a GPU; the [architecture](/core/architecture/) is what keeps the number that low.

| Package | Tests | | Package | Tests |
|---|---|---|---|---|
| `flutter3d` | 850 | | `flutter3d_geometry` | 86 |
| | | | `flutter3d_bridge` | 65 |
| | | | `flutter3d_formats` | 3 |
| | | | `flutter3d_mesh` | 39 |
| | | | `apps/flutter3d_modeler` | 4 |
| `flutter3d_sim` | 491 | | `pad_input` | 59 |
| `flutter3d_game_shooter` | 337 | | `flutter3d_audio` | 55 |
| `flutter3d_game_racing` | 223 | | `flutter3d_webgl` | 55 |
| `flutter3d_game_platformer` | 217 | | `flutter3d_hardware` | 54 |
| `apps/flutter3d_demo_platformer` | 196 | | `flutter3d_impeller` | 53 |
| `flutter3d_cpu` | 187 | | `apps/flutter3d_demo_strategy` | 42 |
| `apps/flutter3d_editor` | 169 | | `flutter3d_session` | 38 |
| `apps/flutter3d_demo_racing` | 145 | | `pointer_lock` | 28 |
| `flutter3d_physics` | 168 | | `flutter3d_webgpu` | 175 |
| `flutter3d_game_strategy` | 131 | | `flutter3d_editor_mcp` | 14 |
| `flutter3d_screens` | 120 | | `flutter3d_testing` | 7 |
| `flutter3d_editor_core` | 101 | | `apps/flutter3d_template_app` | 4 |
| `apps/flutter3d_demo_dungeon` | 89 | | `flutter3d_backend` | 4 |
| `flutter3d_game` | 79 | | `flutter3d_shaders` | 1 |
| `flutter3d_particles` | 73 | | | |

The rows sum to 4362 rather than 4381: the remaining 19 live in `packages/*/example/test`, which the count includes and this table does not.

`flutter3d_app` and `flutter3d_samples` are not in the table and have no `test/` at all. One is a barrel of thirty-five `export` lines and the other is test data with two path constants over it; what there is to check about them is structural, and other packages' decoder tests are what exercise the samples. `flutter3d_conformance` is missing for a different reason: it is invoked as a script harness rather than through `flutter test`, so it does not surface in a grep of `test(` calls either. See below for what that cost once.

```bash
tool/ci.sh                                   # shaders, analyze, every test
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test) # plain Dart, no Flutter needed
```

## Three independent golden sets, not one — and a fourth being recorded

Forty-three scenes are rendered three times: through Impeller, through the software rasteriser in `flutter3d_cpu`, and through WebGL2 in a driven browser. Each backend is held to zero differing pixels against its own set, with a per-channel tolerance of 8.

The browser's set is recorded when a branch lands rather than beside it — `golden_web.sh` holds one fixed port for the whole of its run — so a new scene is in two sets for as long as that takes. Which scenes, and what they are waiting for, is `_provisional` in `flutter3d_webgl/test/cross_backend_test.dart`: the comparison is skipped with the reason printed instead of quietly missing, and the check beside it fails the moment a reference lands and the name is still there.

**WebGPU's set is being recorded and is not finished**, so it is stated here as a number rather than as a fourth set: **42 of the 43 scenes** had references when this was written, on a branch of their own, with `loaded-shader` the one still missing. The distinction is not pedantry — a partial set cannot say a picture regressed, only that some pictures exist, and a line reading "four sets" would promise the first while delivering the second. The same stand records it: `flutter3d_webgl/tool/golden_web.sh --backend=webgpu` writes into `flutter3d_webgpu/test/goldens`. One build serves the whole suite for either browser backend, because the scene *and* the backend are query parameters on the page rather than defines on the compile — a define per backend would have spent the stand's entire saving on a single word. `--no-build` reuses the build already there, which is what makes a second backend's recording cheap.

<div class="warn">
<p><strong>A backend can only witness a shader edit if a machine reads the shaders.</strong> The GLSL in <code>flutter3d_shaders</code> is compiled by <code>impellerc</code>, translated by the WebGL generator and translated again into WGSL for WebGPU — but transcribed into Dart <em>by hand</em> for the software rasteriser. So when six fragment stages were rewritten to satisfy WGSL's uniformity rule, the software set matching byte for byte was not evidence that the edit was neutral. The sets that can answer that are Impeller's and WebGL2's, and this is the kind of thing worth knowing before reading a green run as an answer.</p>
</div>

{{golden3 shadow-teapot | One scene, three sets: a GPU through Metal, a rasteriser written in Dart, and a browser. The pictures on this site are the Impeller set.}}

<div class="why">
<p>Independently written implementations agreeing is evidence; one implementation agreeing with itself is not. The software set also keeps forty-three scenes checkable in a headless run: recording the other two takes a GPU or a browser, but comparing the committed sets takes neither.</p>
</div>

`cross_backend_test.dart` compares them with per-scene budgets, and any new backend has to pass `flutter3d_conformance` before it counts as one.

<div class="warn">
<p>Flutter GPU requires Impeller, which a headless <code>flutter test</code> cannot give it, so the conformance harness has to be an application that somebody watches run. It was one — and stood there showing a pass list to a human — from the same commit that added a fix meant to be caught by it, until <code>packages/flutter3d_impeller/tool/conformance.sh</code> was written to actually run the suite and return its exit code. Once it did, the suite passed; nobody had known either way before then. The <code>the Impeller runners are reachable</code> rule now keeps that script from going stale — checking that it exists, that it is executable, and that it and the entry point still agree about the line the verdict is read from.</p>
</div>

`flutter3d_webgpu` is the backend that gets the arrangement Impeller cannot. Chrome has a real WebGPU device inside `flutter test`, so `flutter test --platform chrome` runs the whole suite against live hardware as an ordinary test file — 33 of 33, two of them passing by declining a capability the device says it has not got: the blend constant and wireframe. Two more used to be there. Rendering into a mip left the list without moving the number, because the two checks that read the capability answered a smaller question rather than skipping when it was false. The block-compressed formats left it when the device started asking its adapter which compression families it carries and requesting exactly those — the check that had been skipping three candidates now draws a block of each. A decline is reported as a decline and never as a pass, because "the suite is green" and "the suite is green, and here is what it never asked" are different sentences.

The rest of that package's tests are deliberately split by whether they need a browser at all. The translation table, the pipeline signature and every vertex-layout refusal live in files that import neither `dart:js_interop` nor `package:web`, so they run on the VM in about a second — a typo in `"less-equal"` fails there rather than as a pipeline a browser rejects at run time on the one machine that has a GPU. The GLSL→WGSL pipeline is checked the same way the WebGL translation is: CI regenerates the table and fails on the diff, which catches a stale table *and* a different compiler on the machine, since this road runs through `glslangValidator` and `naga` rather than one generator.

The same package has a second instrument in the same shape, held by the same rule: `tool/surface_probe.sh` measures flutter_gpu's `GpuImageSurface` against the `asImage()` path `present` uses, on a live GPU, and prints what each costs. The probe itself lives in the engine's example beside the entry point that runs it, not in the backend — it reaches flutter_gpu directly, and is no part of what the backend publishes. It is a measurement rather than a check — its exit code says only whether the last frame of each of the five present paths, and of the resized surface, came back holding the colour it was cleared to, which is a check on the image wrapping the right texture and not on anything the compositor did — and what it found is on the [backends](/core/backends/#presenting) page.

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

This page used to say that could not be relied on. It had never been measured. `parity_test.dart` measures it, by digesting a simulation every so many steps and comparing the digests across platforms.

| Scenario | Checkpoints matching, VM against Chrome |
|---|---|
| Character controller through a room of brushes | **40 of 40**, before and after |
| Arcade vehicle on flat ground | 17 of 40 → **40 of 40** |
| Rigid-body solver settling a pile of crates | **40 of 40** |

The middle row is why the first two disagreed. Of twelve `dart:math` functions asked about twenty thousand arguments each, only `sqrt` and `pow` give the same bits in both places; every transcendental differs, and so does every combination of them. Whether a run diverged was therefore a question about which arguments it reached. Walking reaches almost no transcendental. Driving is made of them — and a verifying server cannot rest on a guarantee that holds for one genre and not another.

<div class="note">
<p><code>warning:</code> the first version of that sweep sampled twelve hand-picked arguments and reported eight of ten functions portable. It was an artefact of the sample size, and a substitution built on the wrong answer went into the vehicle before a wider sweep took it out. <strong>A test of where two implementations agree will report that they agree.</strong></p>
</div>

**So a step stopped calling them.** `Portable` answers the seven questions a simulation asks — `sin`, `cos`, `sinCos`, `tan`, `atan`, `atan2`, `asin`, `exp` — out of `+`, `-`, `*`, `/`, `sqrt` and the bytes of a double, every one of which the specification pins. It gives the same bits everywhere **by construction** rather than by measurement, which is the part that also covers machines nobody has run it on. The polynomials are fdlibm's; `portable_math_test.dart` holds them to two units in the last place against `dart:math`, because portable and wrong is a physics bug that no parity test could ever report — both platforms would compute the same wrong number and every checkpoint would match. A twenty-ninth structure rule, `a step asks no machine for an answer`, keeps the call sites there; cameras, a sky, a lamp's brightness and the lightmap baker are exempt by name.

The solver row was predicted and measured anyway: `flutter3d_physics` calls no transcendental at all, but the three ways it could still have diverged — the order the broadphase hands over contact pairs, a long chain of non-associative additions, and a browser's `int` being a `double` underneath the spatial grid — have nothing to do with `dart:math`.

<div class="note">
<p><code>warning:</code> that trace is two hundred steps where the others are a thousand, and the reason is worth carrying to the next one. Written the usual way, the pile had come to rest by step 175 and thirty-four of forty checkpoints were the same number — forty checkpoints that are really six, an instrument reporting more agreement than it found. Over the window where something happens, thirty-three of forty differ.</p>
</div>

What this settles: a run submitted to a server can be replayed bit for bit on a different platform, and a mismatch is now evidence of a defect rather than of a browser. It is still localised to an interval and quarantined rather than called cheating — because the first thing to suspect is this repository.

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

`cpuTestDevice` stops short of building the `Renderer`, deliberately: `flutter3d_cpu` must not depend on `flutter3d`. A backend that could not be compiled without the engine would not be an implementation of an interface, it would be part of the engine. That is a rule, and one of the thirty-one checks it.

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
  // cpuTestDevice, not `CpuDevice(...)`: the device needs a width, a height and
  // a shader library, and the renderer needs the two fallback textures beside
  // it. That is the fifteen lines this helper replaced in eight files.
  final it = cpuTestDevice(width: 320, height: 180);
  final renderer = Renderer.create(
    device: it.device,
    fallbackAlbedo: it.albedo,
    fallbackNormal: it.normal,
  );
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

Thirty-one rules, under a second. Nothing they read needs `pub get`, a shader bundle or a device, so finding out in minute four that a package imports a genre was finding out late what was knowable in second one.

| Rule | What it refuses |
|---|---|
| `no package names a genre` | A genre import, **and** a genre word: `oneWay`, `ammo` and `lapTime` import nothing and are the same leak |
| `the hardware layer names no graphics API` | `flutter_gpu` or Flutter in the graphics vocabulary |
| `the engine names no backend` | A backend import, or dependency, in `flutter3d` |
| `a genre package draws only where it says` | A renderer reached from a genre's simulation half, and an allowlist entry that has stopped drawing |
| `a genre package reaches no other genre` | A racer borrowing a platformer's runner |
| `a genre camera turns the shared rig` | A genre camera file whose code never names `CameraRig` — smoothing, impulse decay and the pull out of walls written a third time instead of reused |
| `nothing shares a mutable value as a constant` | `static final Vector3`, which the first caller to scale in place changes for the whole process |
| `a step reaches for no clock and no loose dice` | `Random()` and `DateTime.now()` in a simulation package |
| `a step asks no machine for an answer` | `math.sin` and its neighbours in a simulation package: the VM and a browser give different bits for every one of them, and a run built on that replays differently on the machine that verifies it |
| `each assembly has one home per application` | A second place that spawns a level or dresses it |
| `no test builds its own world` | A harness that is not the game, and so agrees with any bug the game has |
| `every exemption names a file that is there` | An allowlist entry whose file has moved, or whose case only resolves on macOS |
| `the compiled shader bundle is not older than its sources` | A bundle built before the GLSL was edited, which fails as `failed to bind texture` rather than as a shader behaving oddly |

Eighteen more check the lists against the workspace, a plain Dart package for a dependency — its own, or a sibling's — that would resolve the Flutter SDK, every pubspec's floors and sibling constraints, a package for a dependency on an application, a simulation package for an import of Flutter, the applications for a silenced `print` and for the flag that turns the GPU on, the Impeller runners — conformance and the surface probe — for rot, every picture this site shows for a golden that is actually recorded, the publishing order for a package it forgot, a public member nothing calls for a sentence saying who it is for, the shader table on the backends page for a stage a bundle must answer to, and five numbers that go stale on their own: the test count, the golden scene count, the structure-rule count, the number of checks the conformance suite says it runs, and the number of enums the hardware layer promises not to rename — plus one that refuses an enum in a published package unless a table says why it is machinery — each compared against the tree. A number in prose is a number nobody recounts, so the counting rules read this site's pages too, and the sentence you are reading is one of them: the rule counts the table above and requires the rest to be the rest.

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
