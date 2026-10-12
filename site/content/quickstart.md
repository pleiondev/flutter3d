---
description: A new Flutter app, two packages from pub.dev, the build hook, the platform keys, and a model on screen that you can turn. The checkout comes last.
---

# Quickstart

From `flutter create` to a model on screen that you can turn with a finger, in about fifteen minutes. Everything here comes from pub.dev; a checkout of this repository is only for working on the engine itself, and that is the last section.

<div class="goal">
<ul>
<li>A new Flutter app with the engine at <code>^1.0.0-rc.1</code></li>
<li>The build hook that converts your models and compiles the shaders your app needs</li>
<li>The two platform keys, and how to tell when they are missing</li>
<li>A <code>Scene3D</code> with a <code>Model3D</code> in it, on macOS and in Chrome</li>
<li>What to do after <code>flutter upgrade</code></li>
</ul>
</div>

Words that look familiar but mean something specific here are in the [glossary](/reference/glossary/), the materials first among them.

## Requirements

| | |
|---|---|
| Flutter | 3.44 or newer; CI runs 3.47.0 stable. The shader bundle is compiled for the SDK that builds the app |
| Dart | 3.12 or newer (comes with the SDK above) |
| Platform | macOS and the browser are supported and exercised. Android is played on a real handset (Impeller Vulkan); iOS runs clean in the simulator on Metal; Windows and Linux go through Impeller and are unverified. [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md) has the table |
| Impeller | Required on a device. Flutter GPU refuses to start on Skia, and the view then draws through the software rasteriser and says so |

<p>On Impeller, GPU memory goes back through Dart's garbage collector. <code>flutter_gpu</code> has no call that frees a buffer or a texture, so <code>dispose</code> drops the engine's last reference and the memory returns when the collector finds it, not at the call. On a phone, keep a model you will show again rather than loading it twice. <a href="https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md#flutter-gpu">SUPPORT.md</a> has the detail.</p>

## Create the app {.step}

```bash
flutter create my_scene
cd my_scene
```

## Add the two packages {.step}

`flutter3d` is the engine. `flutter3d_app` is the view and the widgets that run it, and it depends on the backends your platform draws with (Impeller on a device, WebGPU and WebGL2 in a browser, the software rasteriser when none of them starts), choosing among them at run time.

```bash
flutter pub add flutter3d:^1.0.0-rc.1 flutter3d_app:^1.0.0-rc.1
```

<div class="warn">
<p><strong>Write the constraint.</strong> Until 1.0.0 is out, pub.dev's default version is still 0.8.x, so a plain <code>flutter pub add flutter3d</code> brings 0.8.5, and nothing on this page is true of it. <code>^1.0.0-rc.1</code> asks for the release candidate and admits 1.0.0 when it follows.</p>
</div>

## Add the build hook {.step}

```bash
flutter pub add dev:flutter3d_build:^1.0.0-rc.1
dart run flutter3d_build:init
flutter clean
```

`init` writes four things and changes nothing a second time: `hook/build.dart`, which runs `flutter3d_build`'s `buildAssets` on every build; the `dev_dependencies:` line; the `flutter: assets:` entries for `flutter3d_generated/`; and a `.gitignore` line, because that directory is output. From now on everything under `assets_src/` is converted into `flutter3d_generated/` on every build, and a build with nothing changed converts nothing.

The hook also compiles the engine's shaders into your project, with your SDK's own `impellerc`, and only the stages your app needs. On `flutter3d_app`'s example that is 3.7 MB of shaders in a native build against 8.5 MB for all of them (Flutter 3.47.0, 2026-10-11, measured with `flutter3d shaders`). In a browser, `main.dart.js` of the same example is 1,195,037 bytes gzipped, and with the project's shader bundle (587,778 bytes) the page loads 1.78 MB, against 2.46 MB before the selection (2026-10-12, commit `a39605190`). The APK and IPA sizes are measured on the phones for the release and go here when they are.

<div class="note">
<p><strong>Why <code>flutter clean</code>.</strong> A project that was built once before the hook existed keeps build output that has never heard of it, and Flutter does not always notice that a hook appeared. Cleaning once, right after <code>init</code>, makes the first build run it. You do not need to clean again for a new model; the hook picks those up by itself.</p>
</div>

`dart run flutter3d_build:flutter3d doctor` (or `flutter3d doctor`, after `dart pub global activate flutter3d_build`) checks the hook, the asset lines, the shader bundle and the platform keys of the next step, and says what to change.

## Turn Flutter GPU on for the app {.step}

Flutter GPU and Impeller are enabled **per application**, not per channel, so these keys are yours to add. A browser build needs neither.

macOS and iOS, in `macos/Runner/Info.plist` and `ios/Runner/Info.plist`, inside the top-level `<dict>`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<key>FLTEnableImpeller</key>
<true/>
```

Android, in `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableFlutterGPU"
    android:value="true" />
```

<div class="warn">
<p><strong>Missing keys do not fail.</strong> The app opens and draws through the software rasteriser, because that is what <code>flutter3d_app</code> falls back to when Impeller will not start. The view shows a banner that begins <em>Drawing with</em> and says the GPU backend would not start, which can be closed, and the console has a <code>flutter3d_app:</code> line naming the backend that refused and why. If you see either, these keys are why.</p>
</div>

## Put a model in {.step}

Any `.glb` will do. The robot the [cookbook](https://github.com/pleiondev/flutter3d/tree/main/examples/cookbook) uses is CC0:

```bash
mkdir -p assets_src/models
curl -L -o assets_src/models/robot.glb \
  https://raw.githubusercontent.com/pleiondev/flutter3d/main/examples/cookbook/assets_src/models/RobotExpressive.glb
```

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: Robot()));

class Robot extends StatelessWidget {
  const Robot({super.key});

  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      // Turned by a drag, moved in and out by a pinch or the wheel.
      const OrbitCamera3D(distance: 6.0),
      // 15 000 lux from high up, casting shadows.
      const Light3D.sun(),
      // A path under assets_src/: the hook converts it, and Model3D reads
      // what it wrote.
      Model3D(
        source: 'assets_src/models/robot.glb',
        animation: 'Walking',
      ),
      // A material, as a widget: the meshes below it are drawn with it.
      Material3D(
        baseColor: LinearColor.fromSrgb(0.55, 0.6, 0.55),
        roughness: 0.9,
        children: const <Widget>[
          Mesh3D(shape: PlaneShape(width: 12, depth: 12)),
        ],
      ),
    ],
  );
}
```

```bash
flutter run -d macos
flutter run -d chrome
```

`Scene3D` is a `Flutter3dView` underneath: it opens the device, makes the renderer and the loop, and owns the frame clock, focus, pausing when the route is covered or the app goes to the background, and teardown. Its children become nodes of an ordinary `Scene`, and a rebuild that keeps a widget's key keeps its node, so anything you set on the node by hand survives it.

There are widgets for groups (`Node3D`), shapes (`Mesh3D`, with `onTap`), models with their animation (`Model3D`, with `onTap` for the part that was hit), lights (`Light3D.sun`, `Light3D.lamp`), cameras (`Camera3D`, `OrbitCamera3D`), reflection probes (`ReflectionProbe3D`), decals (`Decal3D`), mirrors (`Mirror3D`) and particles (`Particles3D`). The [cookbook](https://github.com/pleiondev/flutter3d/tree/main/examples/cookbook) has twenty of them put to work, one task to a file.

<div class="note">
<p><strong>One material type.</strong> In a widget tree it is <code>Material3D</code>, and in code it is <code>RenderMaterial</code>, the object a <code>Material3D</code> makes and every mesh draws with. The engine has three other types with <em>material</em> in their names; the <a href="/reference/glossary/#materials">glossary</a> says what each is for and why an application does not draw with any of them.</p>
</div>

<div class="note">
<p><strong>The viewer widget arrives in rc.2.</strong> A model viewer in one widget, with its own camera, lights and loading state, is part of <code>1.0.0-rc.2</code>. In rc.1 the four lines above are the viewer.</p>
</div>

## Without widgets {.step}

The same scene can be built in code: hand `Flutter3dView` an `onCreated`, and add nodes to the engine's scene once the device is open.

```dart
Flutter3dView(
  onCreated: (Flutter3dEngine engine) => engine.scene.add(
    // A shape builds its mesh on the CPU; the device uploads it.
    MeshNode(
      DeviceMesh.upload(engine.device, const SphereShape(radius: 1.0).build()),
      RenderMaterial(
        baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28),
        roughness: 0.35,
      ),
    ),
  ),
  // After the loop has stepped and before the frame is drawn.
  onFrame: (EngineFrame frame) {},
)
```

The view makes an empty scene with a light, and a camera at `(0, 1, 5)` looking at the origin, unless you hand it a `scene` and a `camera` of your own. Its other options come in four groups: `view: ViewSettings(settings: ...)` is what every frame is drawn with, `plugins: PluginSettings(plugins: [...])` go into its loop, `loop: LoopSettings(...)` holds the step rate, the input and where the simulation runs, and a `device` or `renderer` you hand it in `device: DeviceSettings(...)` is borrowed and left alone when the view goes. The [core tutorial](/core/tutorial/) walks through the rest.

`Flutter3dView` is built on `SceneSurface`, which draws a scene that somebody else has set up: a device opened (`openDevice`), a `Renderer.create` over it, a loop stepped, and focus, lifecycle and teardown all the caller's. That stays public for a host with its own frame clock, and [the frame](/core/rendering/) describes what the renderer does with a scene either way.

## A twin or a laboratory {.step}

The same view starts a twin and a laboratory; what changes is where the simulation's time and input come from. `TimeSource` comes from `flutter3d_sim`, and `SimulationPlacement` from `flutter3d_app`.

- **A clock of your own.** `time:` is how many seconds each frame hands the loop. `TimeSource.scaled(10)` runs ten minutes of the model in one, `TimeSource.manual()` moves only when your button calls `advance`, and `TimeSource.log(...)` replays a recording at the pace it was taken. The fixed step stays the loop's, so a run at a tenth of real speed is the same run.
- **Readings as input.** A twin feeds what its source says into the step's input (`InputState.feedExternal` from `EngineLoop.onStepInput`), and an `Assimilation` decides what the model makes of it. The readings are then on the run's tape, so a `RunTimeline` scrubs the history without asking the source again. `packages/flutter3d_app/example/lib/twin_main.dart` polls a REST endpoint in its own code and does exactly this.
- **Probes, not the world.** A `Probe` on an entity publishes a quantity every step, and `ProbeBuilder(published: engine.published, probe: ...)` shows it beside the view, the same whether the simulation runs in the view's loop or in an isolate.
- **Kilometres from the site origin.** A plant's level can sit kilometres from the point its `GeoOrigin` names. The view moves the loop's origin after the camera, and physics stays float32 relative to that origin, so a scene placed through `toVector3Relative` 5 km from the site origin steps to within ± 0.02 mm of the same scene at the origin, measured on a crate settling and a bob swinging on a hinge for ten seconds at 60 Hz. A body placed in float32 out there before the origin moved keeps its rounding (up to a quarter of a millimetre), and [the units contract](https://github.com/pleiondev/flutter3d/blob/main/docs/CONTRACTS.md) has the cases the number leaves out.
- **The accurate profile.** The view's own loop runs the deterministic profile a game is played on. A laboratory that demonstrates builds its loop on `SimulationProfile.accurate` in a top-level function and hands it to `loop: LoopSettings(simulation: SimulationPlacement.isolate(...))`; `packages/flutter3d_education/example/lib/pendulum_main.dart` measures a pendulum's period that way, within 1e-4 of its series over 100 swings. A laboratory a server verifies by replaying the student's run stays on the deterministic profile.

## In a browser {.step}

A browser build needs no keys and no step of its own. The hook writes the project's bundle for the web too: its WebGL2 section always, and its WebGPU section where `glslangValidator` and `naga` are installed (without them the WebGPU device loads the engine's compiled table, which costs the page more). The view tries WebGPU first and falls back to WebGL2 where the browser has no adapter to give. `flutter build web --release` is what the [playable demos](/platformer/demo/) are built with.

A large model decodes on the page's thread unless you give it a worker. The worker is opt-in: compile it once with `dart run flutter3d_core:decode_worker web/flutter3d_decode_worker.js` and call `WebDecodeWorker.use(Uri.parse('flutter3d_decode_worker.js'))` before `runApp`. Without the script, or where the browser will not start a worker, decoding stays on the page, as it always did, and `WebDecodeWorker.inPlaceReason` says why. The script is compiled from the engine's decoders, so build it again after you upgrade the engine.

## After `flutter upgrade` {.step}

The shader bundle is compiled for one SDK, and Impeller refuses a bundle built on another. The hook compiles it again for the SDK that runs the build, so after an upgrade the next build normally does it for you. If the hook's output was cached from before and the app stops at start with a `ShaderBundleException` whose message says the bundle is stale, run:

```bash
flutter clean
flutter run -d macos
```

`flutter3d doctor` says the same thing before you run: a bundle "built on another SDK" is a problem it names, with the fix. The web decode worker, if you use one, is compiled from the engine and is rebuilt when you upgrade the engine rather than Flutter.

## Or start from a project kind

The steps above are what `flutter3d create project` does in one command, with an application of one of three kinds already in `lib/main.dart` and a `test/widget_test.dart` that opens it on the software device:

```bash
dart pub global activate flutter3d_build 1.0.0-rc.1
flutter3d create project my_viewer --kind viewer   # a model a drag turns, on Flutter3dView
flutter3d create project my_arcade --kind arcade   # a Flame game over a 3D layer
flutter3d create project my_scene                  # one lit sphere in a Scene3D
```

Each analyses clean and builds for the web as it is made; `flutter create --platforms=macos,web .` in the new directory adds the platform folders. The level genres (a platformer, a shooter, a racer, a strategy map) start from the level editor's templates instead, in [your first project](/first-project/).

To try the level format before making anything, the [playground](/playground/) draws a level or a prefab document as you type it.

## Where to go next

- [The playground](/playground/): a level or a prefab document, drawn in this browser as you edit it
- [The cookbook](https://github.com/pleiondev/flutter3d/tree/main/examples/cookbook): twenty tasks, one file each
- [Tutorial: first scene](/core/tutorial/): lights, shadows, a clip, picking, particles and the settings, step by step on the same widgets
- [Your first project](/first-project/): a game scaffolded from a template, with a level and a body that walks
- [Glossary](/reference/glossary/): what each word here names
- [The asset pipeline](/reference/asset-pipeline/): what the hook does with your models, textures and materials
- [Pitfalls](/reference/pitfalls/): the conditions without which Flutter GPU renders nothing and reports no error
- [Coming from 0.8](/reference/migrating-to-1.0/): one command moves a project

## Working on the engine itself

Everything above uses the packages from pub.dev. To change the engine, run its demos from source or send a change, clone the repository. It is a [pub workspace](https://dart.dev/tools/pub/workspaces): one resolve covers all 61 packages and 18 applications against a single lock file.

```bash
git clone https://github.com/pleiondev/flutter3d.git
cd flutter3d
flutter pub get

# The engine demo's own bundle, which it loads at runtime and names as an
# asset. Every other app's bundle is built by its hook.
(cd packages/flutter3d/example && ./tool/build_shaders.sh)

(cd packages/flutter3d/example && flutter run -d macos)      # the engine demo
(cd apps/flutter3d_demo_dungeon && flutter run -d macos)     # the shooter
(cd apps/flutter3d_demo_platformer && flutter run -d chrome) # the platformer
(cd examples/cookbook && flutter run -d macos -t lib/campfire.dart)
```

The demo bundle is gitignored and tied to the Flutter version: a fresh checkout has none, and the symptom is a missing-asset error at startup. Run the script again after `flutter upgrade`. It calls `impellerc` directly and prints the compiled binding table on the way out. Read that table once: the compiler drops a uniform block or a sampler whose result never reaches the output, so what a shader *declares* and what it actually *binds* are different lists.

```bash
tool/ci.sh                                   # shaders, analyze, every test
(cd packages/flutter3d_game && flutter test)
(cd packages/flutter3d_physics && dart test) # plain Dart, no Flutter needed
```

There are 14701 tests across 61 packages and 18 applications, and only about thirty need a GPU: the Impeller half of the golden set. The other half renders through the software backend, so 96 scenes stay checkable in a headless run. [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md) says how a change is written and tested.
