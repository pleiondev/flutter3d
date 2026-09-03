---
description: Resolve the workspace, build the shader bundle, run the demo, and put your own lit mesh on screen.
---

# Quickstart

Fifteen minutes from a fresh checkout to a lit mesh turning on screen. Two of those minutes are a shader bundle that a fresh checkout does not have and cannot run without.

<div class="goal">
<ul>
<li>A resolved pub workspace and a built shader bundle</li>
<li>The engine's own demo running, with every feature switchable</li>
<li>Your own Flutter app drawing a mesh through <code>Renderer</code></li>
</ul>
</div>

## Requirements

| | |
|---|---|
| Flutter | 3.47.0 stable or newer. The shader bundle format is tied to the SDK version |
| Dart | 3.12.2 or newer (comes with the SDK above) |
| Platform | macOS and the browser are supported and exercised. Android is played on a real handset (Impeller Vulkan); iOS runs clean in the simulator on Metal; Windows and Linux go through Impeller and are unverified |
| Impeller | Required. Flutter GPU refuses to start on Skia |

## Resolve the workspace

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces): one resolve covers all twenty-four packages and five applications against a single lock file. Packages that depend on each other by path drift apart at the first version bump otherwise, and the drift only shows up as an unbuildable checkout on somebody else's machine.

```bash
git clone https://github.com/pleiondev/flutter3d.git
cd flutter3d
flutter pub get
```

## Build the shader bundles

Required before the first run, and again after every Flutter SDK change. There
are two: the engine's own, which every application links, and the engine demo's,
which it loads at runtime and names as an asset.

```bash
(cd packages/flutter3d_impeller && ./tool/build_shaders.sh)
(cd packages/flutter3d/example && ./tool/build_shaders.sh)
```

<div class="warn">
<p>The bundle is generated, gitignored, and its format is tied to the Flutter version. A fresh checkout has none, and the symptom is <code>Failed to initialize ShaderLibrary</code> at startup instead of a missing-file error. After <code>flutter upgrade</code>, run it again — shaders that used to load will stop.</p>
</div>

The script calls `impellerc` directly rather than going through Native Assets, and prints the compiled binding table on the way out. That table is worth reading once: the compiler drops a uniform block or a sampler whose result never reaches the output, so what a shader *declares* and what it actually *binds* are different lists.

## Run something

```bash
# The engine's demo: a model browser with every feature switchable
(cd packages/flutter3d/example && flutter run -d macos)

# The shooter
(cd apps/flutter3d_demo_dungeon && flutter run -d macos)

# The platformer
(cd apps/flutter3d_demo_platformer && flutter run -d macos)

# The racing game
(cd apps/flutter3d_demo_racing && flutter run -d macos)

# Any of them in a browser: the same command, a different device. No shader
# bundle is involved — the WebGL backend translates the same GLSL and the
# browser compiles it.
(cd apps/flutter3d_demo_platformer && flutter run -d chrome)
```

<div class="note">
<p>For something to hand out rather than to run, build it: <code>flutter build web --wasm --release</code> produces the WebAssembly output and the JavaScript one beside it, and <code>flutter_bootstrap.js</code> picks between them at load. That is what the <a href="/platformer/demo/">playable demos</a> on this site are.</p>
</div>

<div class="note">
<p>Flutter GPU and Impeller are enabled <strong>per application</strong> through <code>Info.plist</code>, not per channel. Every app in this repository sets <code>FLTEnableFlutterGPU</code> and <code>FLTEnableImpeller</code> for itself, and a new one that skips them fails to initialise the shader library and renders nothing. On Android the key is <code>io.flutter.embedding.android.EnableFlutterGPU</code> in <code>AndroidManifest.xml</code>.</p>
</div>

## Run the tests

```bash
tool/ci.sh                                  # shaders, analyze, every test
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test) # plain Dart, no Flutter needed
```

3206 tests across 24 packages and five applications, and only about thirty need a GPU: the Impeller half of the golden set. The other half renders through the software backend, so thirty-five scenes stay checkable in a headless run.

## Your own application

A new app needs three things in its pubspec: the engine, a backend, and whatever else it draws with. The backend is named on purpose. It is the one line an application changes to run on a different graphics API.

```yaml
name: my_game
publish_to: 'none'

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter

  # The backend. The engine talks to a HAL (flutter3d_hardware) and never to a
  # graphics API, so this is the one line that picks which one runs:
  #   flutter3d_impeller -> flutter_gpu (Metal, Vulkan)  <- the production one
  #   flutter3d_webgl    -> WebGL2, in the browser
  #   flutter3d_cpu      -> software, rasterises in Dart (tests, goldens)
  flutter3d_impeller: ^0.4.0

  flutter3d: ^0.4.0

  vector_math: ^2.2.0
```

Then open a device, create a renderer, and hand it a scene. Everything below is real API; the [core tutorial](/core/tutorial/) walks the whole thing line by line.

```dart
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

Future<Renderer> openRenderer() async {
  final device = await GpuRenderBackend.create();
  // The fallbacks a material without a map samples — white, and the neutral
  // normal — are the renderer's own unless you hand it others. Neutral
  // fallbacks rather than per-map flags: the shader then needs no branch and
  // the engine no bookkeeping about which maps a material has.
  return Renderer.create(device: device);
}

Scene buildScene(GraphicsDevice device) {
  final scene = Scene();

  // A shape is a value that builds `MeshData` on the CPU; the device turns
  // that into buffers. The two steps stay apart because bounds, culling and
  // picking need the first one and no device at all.
  scene.add(MeshNode(
    DeviceMesh.upload(device, const SphereShape(radius: 1.0).build()),
    Material(
      name: 'ball',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.9, 0.42, 0.28, 1.0),
      roughness: 0.35,
    ),
  ));

  scene.add(LightNode(type: LightType.directional)
    ..intensity = 3.0
    ..castsShadow = true
    ..setLocalForward(Vector3(-0.4, -1.0, -0.3)));

  return scene;
}
```

<div class="note">
<p>None of the three shipped games open a device this way. Hand-rolling <code>GpuRenderBackend.create()</code> and a bare <code>Ticker</code> is what this page teaches because it is what is actually happening underneath, but by the second game the same conditional import, frame surface and level lifecycle had been copy-pasted three times. <a href="/core/session/">Assembling an application</a> is the guide for the pattern the games use instead: <code>flutter3d_backend</code>, <code>flutter3d_session</code> and <code>flutter3d_screens</code>.</p>
</div>

## Where to go next

- [Your first project](/first-project/): a project of your own, scaffolded from a template, in a directory that is not this one
- [Core: what core is](/core/): the shape of the engine and which package owns what
- [The frame](/core/rendering/): what the renderer actually does with a scene
- [Tutorial: first scene](/core/tutorial/): the whole application, step by step
- [Assembling an application](/core/session/): the device, frame surface and level lifecycle the shipped games actually use
- [Pitfalls](/reference/pitfalls/): the conditions without which Flutter GPU silently renders nothing
