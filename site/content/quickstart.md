---
description: Resolve the workspace, build the shader bundle, run the demo, and put your own lit mesh on screen.
---

# Quickstart

This takes about fifteen minutes, from a fresh checkout to a lit mesh turning on screen. Two of those minutes go on a shader bundle that a fresh checkout does not have and cannot run without.

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

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces): one resolve covers all thirty-eight packages and twelve applications against a single lock file. Without it, packages that depend on each other by path drift apart at the first version bump, and the drift only shows up as an unbuildable checkout on somebody else's machine.

```bash
git clone https://github.com/pleiondev/flutter3d.git
cd flutter3d
flutter pub get
```

## Build the shader bundles

There are two: the engine's canonical bundle, which every application links,
and a separate one belonging to the engine's demo, which the demo loads at
runtime and names as an asset.

<div class="note">
<p>The engine's own bundle no longer needs this step. <code>packages/flutter3d_impeller/hook/build.dart</code> (<code>ap-06</code> in <code>doc/asset-pipeline-plan.md</code>) builds it during <code>flutter build</code> and <code>flutter run</code>, so after a fresh checkout and <code>flutter pub get</code>, <code>flutter run -d macos</code> in any of the three games below draws a frame with no shader step in between. The step stays here only for the one bundle the hook does not cover.</p>
</div>

```bash
(cd packages/flutter3d/example && ./tool/build_shaders.sh)
```

<div class="warn">
<p>That bundle is still generated, gitignored and tied to the Flutter version. A fresh checkout has none, and the symptom is a missing-asset error at startup, not a build failure. Run the script again after <code>flutter upgrade</code>. It has not moved onto the hook because it is the demo's own bundle, separate from the canonical one <code>ap-06</code> covers; that entry's "Not done" says why.</p>
</div>

The script calls `impellerc` directly instead of going through Native Assets, and prints the compiled binding table on the way out. Read that table once. The compiler drops a uniform block or a sampler whose result never reaches the output, so what a shader *declares* and what it actually *binds* are different lists.

## Run something

```bash
# The engine's demo: a model browser with every feature switchable.
# Needs the shader step above; it is the one bundle that still asks for it.
(cd packages/flutter3d/example && flutter run -d macos)

# The shooter
(cd apps/flutter3d_demo_dungeon && flutter run -d macos)

# The platformer
(cd apps/flutter3d_demo_platformer && flutter run -d macos)

# The racing game
(cd apps/flutter3d_demo_racing && flutter run -d macos)

# Any of them in a browser: the same command, a different device. No shader
# bundle is involved, because the WebGL backend translates the same GLSL and
# the browser compiles it.
(cd apps/flutter3d_demo_platformer && flutter run -d chrome)
```

<div class="note">
<p>To produce something you can hand out, build it with <code>flutter build web --release</code>. That is how the <a href="/platformer/demo/">playable demos</a> on this site are built. Leave out <code>--wasm</code> for now: the dart2wasm build of the WebGL backend throws on its first frame, and <code>site/tool/demos.sh</code> records the details.</p>
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

There are 9862 tests across 38 packages and twelve applications, and only about thirty need a GPU: the Impeller half of the golden set. The other half renders through the software backend, so forty-four scenes stay checkable in a headless run.

## Your own application

A new app needs three things in its pubspec: the engine, a backend, and whatever else it draws with. The backend is named on purpose, because it is the one line an application changes to run on a different graphics API.

<div class="note">
<p>The 0.7.1 set is on <a href="https://pub.dev/publishers/pleion.dev/packages">pub.dev</a>, so the <code>^0.7.1</code> lines below resolve as written. Skip 0.7.0: installed from pub.dev, its Impeller build hook fails before the first test, and on macOS and iOS an unlit material crashes the first frame. If you are moving a project from 0.6.0, several packages were folded into others; <code>doc/boundary-0.7.0.md</code> in the repository lists which import lines move.</p>
</div>

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
  #   flutter3d_webgpu   -> WebGPU, in a browser that has an adapter
  #   flutter3d_cpu      -> software, rasterises in Dart (tests, goldens)
  flutter3d_impeller: ^0.7.1

  flutter3d: ^0.7.1

  vector_math: ^2.2.0
```

Then open a device, create a renderer, and hand it a scene. Everything below is real API; the [core tutorial](/core/tutorial/) walks through it line by line.

```dart
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

Future<Renderer> openRenderer() async {
  final device = await GpuRenderBackend.create();
  // The fallbacks a material without a map samples (white, and the neutral
  // normal) are the renderer's own unless you hand it others. Neutral
  // fallbacks instead of per-map flags: the shader then needs no branch and
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
<p>None of the shipped games open a device this way. This page hand-rolls <code>GpuRenderBackend.create()</code> and a bare <code>Ticker</code> because that is what happens underneath, but by the second game the same conditional import, frame surface and level lifecycle had been copy-pasted three times. <a href="/core/session/">Assembling an application</a> covers the pattern the games use instead: <code>flutter3d_app</code> and <code>flutter3d_game</code>.</p>
</div>

## Where to go next

- [Your first project](/first-project/): a project of your own, scaffolded from a template, in a directory that is not this one
- [Core: what core is](/core/): the shape of the engine and which package owns what
- [The frame](/core/rendering/): what the renderer does with a scene
- [Tutorial: first scene](/core/tutorial/): the whole application, step by step
- [Assembling an application](/core/session/): the device, frame surface and level lifecycle the shipped games use
- [The asset pipeline](/reference/asset-pipeline/): converting your own models and textures on every build, instead of committing what a script produced once
- [Pitfalls](/reference/pitfalls/): the conditions without which Flutter GPU renders nothing and reports no error
