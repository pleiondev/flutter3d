---
description: Resolve the workspace, build the shader bundle, run the demo, and put your own lit mesh on screen.
---

# Quickstart

This takes about fifteen minutes, from a fresh checkout to a lit mesh turning on screen. Two of those minutes go on a shader bundle that a fresh checkout does not have and cannot run without.

<div class="goal">
<ul>
<li>A resolved pub workspace and a built shader bundle</li>
<li>The engine's own demo running, with every feature switchable</li>
<li>Your own Flutter app drawing a mesh through <code>Flutter3dView</code></li>
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

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces): one resolve covers all fifty-seven packages and seventeen applications against a single lock file. Without it, packages that depend on each other by path drift apart at the first version bump, and the drift only shows up as an unbuildable checkout on somebody else's machine.

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

There are 13267 tests across 57 packages and seventeen applications, and only about thirty need a GPU: the Impeller half of the golden set. The other half renders through the software backend, so ninety-six scenes stay checkable in a headless run.

## Your own application

A new app needs two engine packages in its pubspec: `flutter3d`, the engine, and `flutter3d_app`, which picks this platform's backends and wraps an engine in a widget.

<div class="note">
<p>The 1.0.0 set goes out first as a release candidate, <code>1.0.0-rc.1</code>, on <a href="https://pub.dev/publishers/pleion.dev/packages">pub.dev</a>. pub.dev keeps 0.8.x as the default until 1.0.0, so the candidate is opt-in: the <code>^1.0.0-rc.1</code> lines below ask for it, and they admit 1.0.0 too when it follows. Skip 0.7.0: installed from pub.dev, its Impeller build hook fails before the first test, and on macOS and iOS an unlit material crashes the first frame. If you are moving a project from 0.6.0, several packages were folded into others; <code>doc/boundary-0.7.0.md</code> in the repository lists which import lines move.</p>
</div>

```yaml
name: my_game
publish_to: 'none'

environment:
  sdk: ^3.12.2

dependencies:
  flutter:
    sdk: flutter

  # The engine, and the widget that runs it. flutter3d_app depends on the
  # backends this platform draws with (Impeller on a device, WebGL2 and
  # WebGPU in a browser, the software rasteriser when neither starts) and
  # chooses among them at run time.
  flutter3d: ^1.0.0-rc.1
  flutter3d_app: ^1.0.0-rc.1

  vector_math: ^2.2.0
```

Then put a `Flutter3dView` where the picture goes. It opens the device, makes the renderer and the loop, and owns the frame clock, focus, pausing when the route is covered or the app goes to the background, and teardown. `onCreated` is called once the device is open, with the engine: the scene to fill, the device to upload to, the loop to add systems and plugins to.

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

/// How far the ball has turned, in radians.
var spin = 0.0;

void main() => runApp(
  MaterialApp(
    home: Scaffold(
      body: Flutter3dView(
        onCreated: (Flutter3dEngine engine) {
          // A shape is a value that builds `MeshData` on the CPU; the device
          // turns that into buffers. The two steps stay apart because bounds,
          // culling and picking need the first one and no device at all.
          engine.scene.add(
            MeshNode(
              DeviceMesh.upload(
                engine.device,
                const SphereShape(radius: 1.0).build(),
              ),
              RenderMaterial(
                baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28),
                roughness: 0.35,
              ),
            ),
          );
        },
        // Called after the loop has stepped, before the frame is drawn.
        onFrame: (Flutter3dEngine engine, FrameInfo frame) {
          spin += frame.seconds * 0.5;
          engine.scene.meshes.first.setRotationYawPitchRoll(spin, 0.0, 0.0);
        },
      ),
    ),
  ),
);
```

The view makes an empty scene with a light, and a camera at `(0, 1, 5)` looking at the origin, unless you hand it a `scene` and a `camera` of your own. `settings` is what every frame is drawn with, `plugins` go into its loop, and a `device` or `renderer` you hand it is borrowed and left alone when the view goes. The [core tutorial](/core/tutorial/) walks through the rest.

### Or write the scene as widgets

`flutter3d_app` has the same scene as widgets. `Scene3D` is a `Flutter3dView` underneath, and its children become nodes of an ordinary `Scene`. A rebuild that keeps a widget's key keeps its node, so anything you set on the node imperatively survives it.

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

Widget ball({required bool polished}) => Scene3D(
  children: <Widget>[
    Camera3D(position: Vector3(0.0, 1.2, 3.5), target: Vector3.zero()),
    Light3D.point(position: Vector3(2.0, 2.5, 2.0), range: 20.0),
    // Every Mesh3D below without a material of its own is drawn with this
    // one. A rebuild writes the new values into the same material object.
    Material3D(
      key: const ValueKey<String>('ball'),
      baseColor: polished
          ? LinearColor.fromSrgb(0.25, 0.45, 0.9)
          : LinearColor.fromSrgb(0.9, 0.42, 0.28),
      roughness: polished ? 0.1 : 0.35,
      children: const <Widget>[Mesh3D(shape: SphereShape(radius: 1.0))],
    ),
  ],
);
```

There are widgets for groups (`Node3D`), models with their animation (`Model3D`), lights, cameras, reflection probes (`ReflectionProbe3D`), decals (`Decal3D`), mirrors (`Mirror3D`, whose child meshes are its surfaces) and particles (`Particles3D`). `Contributor3D` adds any pass contributor for as long as it is in the tree. `example/lib/widgets_main.dart` is the runnable version of the snippet above.

If your game already has its own loop and renderer, `SceneWidgets.mount` builds the same widgets into a scene you draw yourself, without a screen. The golden runner draws the `widget-scene` reference that way, on all four backends.

### The low level underneath

`Flutter3dView` is built on `SceneSurface`, which draws a scene that somebody else has set up: a device opened (`openDevice`, or a backend's own `open`), a `Renderer.create` over it, a loop stepped, and focus, lifecycle and teardown all the caller's. That stays public for a host that has its own frame clock or draws several engines into one widget tree, and [the frame](/core/rendering/) describes what the renderer does with a scene either way. [Assembling an application](/core/session/) covers what the shipped games add on top: `flutter3d_game`'s run, levels and settings.

## Where to go next

- [Your first project](/first-project/): a project of your own, scaffolded from a template, in a directory that is not this one
- [Core: what core is](/core/): the shape of the engine and which package owns what
- [The frame](/core/rendering/): what the renderer does with a scene
- [Tutorial: first scene](/core/tutorial/): the whole application, step by step
- [Assembling an application](/core/session/): the device, frame surface and level lifecycle the shipped games use
- [The asset pipeline](/reference/asset-pipeline/): converting your own models and textures on every build, instead of committing what a script produced once
- [Pitfalls](/reference/pitfalls/): the conditions without which Flutter GPU renders nothing and reports no error
