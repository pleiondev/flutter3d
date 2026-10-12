---
description: Twelve steps from flutter create to a lit, shadowed, animated scene with picking, particles and the debug overlay, on the 1.0 widgets.
---

# Tutorial: your first scene

Twelve steps, each one runnable. By the end you have an application that loads a model, lights and shadows it, plays a clip, lets you tap on things, throws sparks where you tapped, and tells you what the frame cost. It is written on `Scene3D` and the widgets under it, and the last steps show the engine those widgets build, for when you want it by hand.

<div class="goal">
<ul>
<li>A Flutter app drawing through Flutter GPU, from packages on pub.dev</li>
<li>Shapes, a loaded glTF model and three kinds of light</li>
<li>Cascaded shadows, bloom and tone mapping</li>
<li>An orbit camera, tap-to-select, particles and the debug overlay</li>
<li>The scene graph underneath, reached from the same widget</li>
</ul>
</div>

## Create the project {.step}

The [quickstart](/quickstart/) explains each of these lines; here they are in order.

```bash
flutter create my_scene
cd my_scene
flutter pub add flutter3d:^1.0.0-rc.1 flutter3d_app:^1.0.0-rc.1 flutter3d_particles:^1.0.0-rc.1
flutter pub add dev:flutter3d_build:^1.0.0-rc.1
dart run flutter3d_build:init
flutter clean
```

The constraint is written out because pub.dev's default is still 0.8.x until 1.0.0. `init` wires the build hook, which converts what you put under `assets_src/` and compiles the shader stages your app needs for the SDK that builds it.

## Turn Flutter GPU on for this application {.step}

Flutter GPU and Impeller are enabled **per application**. In `macos/Runner/Info.plist` (and `ios/Runner/Info.plist`):

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<key>FLTEnableImpeller</key>
<true/>
```

On Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml`. Without them the app still opens, through the software rasteriser, with a banner that says so.

## A first scene {.step}

`Scene3D` opens the device, makes the renderer and the loop, and draws its children. A `Material3D` is the material the meshes below it are drawn with.

```dart
import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';

void main() => runApp(const MaterialApp(home: Workshop()));

class Workshop extends StatefulWidget {
  const Workshop({super.key});

  @override
  State<Workshop> createState() => _WorkshopState();
}

class _WorkshopState extends State<Workshop> {
  @override
  Widget build(BuildContext context) => Scene3D(
    children: <Widget>[
      Camera3D(position: Vector3(0.0, 3.0, 8.0), target: Vector3.zero()),
      const Light3D.sun(),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.24, 0.26, 0.28),
        roughness: 0.95,
        children: const <Widget>[
          Mesh3D(shape: PlaneShape(width: 40, depth: 40), name: 'ground'),
        ],
      ),
      Material3D(
        baseColor: LinearColor.fromSrgb(0.9, 0.42, 0.28),
        metallic: 0.1,
        roughness: 0.32,
        children: <Widget>[
          Mesh3D(
            shape: const SphereShape(radius: 1.0),
            position: Vector3(0.0, 1.0, 0.0),
            name: 'ball',
          ),
        ],
      ),
    ],
  );
}
```

A shape is a value that builds its mesh on the CPU, and the widget uploads it to the device once. A rebuild handed a new shape object builds it again and uploads only when its vertices differ, so writing `const SphereShape(...)` in `build` costs nothing per frame.

Colours are linear light, what the shader adds up. `LinearColor.fromSrgb` converts a colour you picked by eye.

## Three kinds of light {.step}

Brightness is photometric: lux for the sun, candela for a lamp or a spot. The defaults are lights the default camera (f/4, 1/60 s, ISO 100) shows well.

```dart
// The key light, the one that casts shadows: 15 000 lux, a hazy sun.
Light3D.sun(direction: Vector3(-0.4, -1.0, -0.3)),

// A household bulb, 800 lumens, warm white. Indoors a hundredth of daylight.
Light3D.lamp(position: Vector3(-5.0, 3.0, 4.0), range: 14.0),

// A spot, for shape: candela along its axis, inside a cone in radians.
Light3D(
  type: LightType.spot,
  position: Vector3(4.0, 6.0, 2.0),
  direction: Vector3(-0.5, -1.0, -0.3),
  color: const LinearColor(1.0, 0.86, 0.7),
  intensity: 20000.0,
  range: 20.0,
  outerConeAngle: 0.5,
),
```

A room lit only by bulbs needs the camera opened up, as a photographer would: `RenderSettings(autoExposure: AutoExposureSettings(enabled: true))`, or a `PhysicalCamera` at f/2 and 1/30 s.

## Shadows, bloom and tone mapping {.step}

What every frame is drawn with is one `RenderSettings`, handed to `Scene3D`:

```dart
static const RenderSettings look = RenderSettings(
  tonemap: true,
  shadows: ShadowSettings(
    cascades: 3,        // one to three, side by side in one texture
    resolution: 1024,   // the atlas is resolution × cascades wide
    cascadeSplit: 0.7,
  ),
  bloom: BloomSettings(
    threshold: 1.0,     // display white
    intensity: 0.06,
  ),
);

// Scene3D(settings: look, children: ...)
```

Three tiles of 1024 cover a scene far better than one of 4096, so prefer a smaller tile *and* cascades.

## An orbit camera {.step}

Replace the `Camera3D` with one a person can turn:

```dart
const OrbitCamera3D(distance: 9.0, pitch: 0.4),
```

A drag swings round the target and tilts short of the poles, a pinch or the scroll wheel moves in and out, and a fling slows by itself. `target:` follows on every build where it changed, so a game can point it at something that moves, and the distance and the angle stay where the person left them.

## Load a model and play a clip {.step}

Put a `.glb` under `assets_src/models/`. The quickstart fetches a CC0 robot; any animated model will do.

```dart
Model3D(
  source: 'assets_src/models/robot.glb',
  animation: clip,                    // a field: 'Idle', 'Walking', 'Dance'
  position: Vector3(3.0, 0.0, 0.0),
  onLoaded: (ModelInstance robot) =>
      debugPrint('${robot.meshes.length} meshes'),
),
```

The file is read once, when the widget is first built, on a background isolate. `placeholder:` takes a 3D widget to stand in until it is in the scene (the cookbook's `placeholder_while_loading.dart`). A rebuild with another `animation` changes the clip of the instance already in the scene and loads nothing; a different `source` is a different model, so give that one a different key. The model belongs to the widget and is released when the widget goes.

## Tap on something {.step}

A tap on the `Scene3D` is a ray through the camera, and the nearest surface under the finger answers, whether or not it listens. `Mesh3D.onTap` gives where it landed; `Model3D.onTap` gives the part as well.

```dart
MeshNode? selected;

// On the ball:
onTap: (HitResult hit) => setState(() => selected = null),

// On the robot:
onTap: (MeshNode part, HitResult hit) => setState(() => selected = part),

// And in Scene3D:
settings: look.copyWith(highlighted: <SceneNode>[?selected]),
```

The `HitResult` is reused by the next tap. Copy anything that has to outlive the callback, as `hit.point.clone()`.

## Sparks where you tapped {.step}

`Particles3D` emits at its node's place, simulated between frames and drawn as billboards in one call:

```dart
import 'package:flutter3d_particles/flutter3d_particles.dart';

const ParticleEffect sparks = ParticleEffect(
  count: 1,
  emitter: ConeEmitter(speed: Range(2.0, 5.0)),
  lifetime: Range(0.3, 0.6),
  size: Range(0.03, 0.06),
  color: LinearColor(1.0, 0.6, 0.2),
  affectors: <ParticleAffector>[ParticleGravity.world(), ParticleFade()],
);

// In the scene, at the last tap:
Particles3D(effect: sparks, perSecond: 200, position: tappedAt),
```

`perSecond` follows every build, so `0` stops the emitter and lets what is already in the air finish. Each demo application keeps a catalogue of effects in its own `lib/src/effects.dart`, and copying an entry from there is the fastest way to a good one.

## What the frame cost {.step}

`onFrame` is called before every frame with the seconds since the last one and what the renderer answered for the frame before:

```dart
onFrame: (FrameInfo frame) {
  if (frame.result case final result?) {
    debugPrint('${result.drawCalls} draws, ${result.triangles} triangles, '
        '${result.cpuMicros} µs');
  }
},
```

Turn on the debug overlay while you are still finding out where things are. All of it is drawn in one call:

```dart
settings: look.copyWith(
  debug: const DebugDrawSettings(bounds: true, lightGizmos: true, axes: true),
),
```

<div class="why">
<p>Judging a render by eye does not scale. If a setting looks like it does nothing, capture the same frame with it on and off and diff the two: a zero difference answers the question.</p>
</div>

## The engine under the widgets {.step}

`Scene3D` hands you what it built once the device is open:

```dart
onCreated: (Scene3DController scene) {
  // The scene graph the widgets build into, and a node added by hand: a
  // shape builds its mesh on the CPU, and the device uploads it.
  scene.scene.add(
    MeshNode(
      DeviceMesh.upload(scene.device, CuboidShape().build()),
      RenderMaterial(baseColor: LinearColor.fromSrgb(0.3, 0.5, 0.9)),
      name: 'crate',
    )..setPosition(-3.0, 0.5, 0.0),
  );

  // The renderer and the loop, as the Flutter3dView underneath made them:
  // systems and plugins go into scene.engine.loop.
  debugPrint('drawing with ${scene.device.runtimeType}');
},
```

A property a widget leaves null is left as the node has it, so what you set here survives a rebuild unless the widget says otherwise. `RenderMaterial` is the one material type in code, the same object a `Material3D` makes; the [glossary](/reference/glossary/#materials) names the others and why an application does not draw with them.

For a scene built wholly in code, `Flutter3dView(onCreated: ...)` hands you the same engine with an empty scene, and the [quickstart](/quickstart/#without-widgets) has the shape of it.

## When nothing appears {.step}

The failures that produce a picture instead of an error, in the order to check them.

| Symptom | Cause |
|---|---|
| A banner saying the GPU backend would not start | `FLTEnableFlutterGPU` or `FLTEnableImpeller` is missing from `Info.plist`, or the Android meta-data; the frames are the software rasteriser's |
| `ShaderBundleException` naming a stale bundle | The bundle was compiled on another SDK, usually after `flutter upgrade`. `flutter clean` and build again |
| `MissingShaderStageException` | A lighting model or a material's stage the project's bundle left out; the message names the need to add under `shaders:` |
| A model that never appears, and a line about `flutter3d_generated` | The hook has not run: `dart run flutter3d_build:init`, then `flutter clean` |
| `A Mesh3D was given no material` | A `Mesh3D` with no `material:` and no `Material3D` above it |
| The scene is all ambient, or black | A light far too dim for the camera: lux and candela, not 1.0 |

The full list, with the fix for each, is on the [Pitfalls](/reference/pitfalls/) page.

## Where to go from here

You now have a scene, a renderer and a loop. What you do not have yet is a *game*: a fixed step, collision, a level, and input that survives a slow frame. That is the [simulation layer](/core/simulation/), and the genre tutorials build a whole game on top of it:

- [Build a shooter](/shooter/tutorial/): weapons, monsters that path around corners, an inventory, locked doors, saves
- [Build a platformer](/platformer/tutorial/): a double jump with coyote time, wall slides, ice and conveyors, springs, checkpoints
- [The cookbook](https://github.com/pleiondev/flutter3d/tree/main/examples/cookbook): twenty tasks, one file each
