---
description: Thirteen steps from an empty Flutter app to a lit, shadowed, animated scene with picking, particles and a debug overlay.
---

# Tutorial: your first scene

Thirteen steps, each one runnable. By the end you have an application that loads a model, lights and shadows it, plays an animation, lets you click on things, and tells you what the frame cost.

<div class="goal">
<ul>
<li>A Flutter desktop app drawing through Flutter GPU</li>
<li>A scene with generated geometry, a loaded glTF model and three kinds of light</li>
<li>Cascaded shadows, bloom and tone mapping</li>
<li>An orbit camera, click-to-select, a particle effect and the debug overlay</li>
</ul>
</div>

## Create the project {.step}

```bash
flutter create --platforms=macos,windows,linux my_scene
cd my_scene
```

Add the engine and a backend to `pubspec.yaml`. Why the backend is named here at all is explained in the [quickstart](/quickstart/).

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter3d:
    path: ../flutter3d/packages/flutter3d
  flutter3d_impeller:
    path: ../flutter3d/packages/flutter3d_impeller
  flutter3d_particles:
    path: ../flutter3d/packages/flutter3d_particles

  vector_math: ^2.2.0

flutter:
  assets:
    - assets/models/
```

```bash
flutter pub get
```

## Turn Flutter GPU on for this application {.step}

Flutter GPU and Impeller are enabled **per application**, not per channel. An app that skips this fails to initialise the shader library and renders nothing.

In `macos/Runner/Info.plist`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<key>FLTEnableImpeller</key>
<true/>
```

On Android the key is `io.flutter.embedding.android.EnableFlutterGPU` in `AndroidManifest.xml`.

<div class="warn">
<p><code>flutter create</code> generates <code>MACOSX_DEPLOYMENT_TARGET = 10.15</code> and current Xcode will not build it. Raise it to 12.0 in <code>macos/Runner.xcodeproj/project.pbxproj</code>.</p>
</div>

## Build the shader bundle {.step}

```bash
(cd ../flutter3d/packages/flutter3d_impeller && ./tool/build_shaders.sh)
```

Generated, gitignored, and tied to the Flutter version. Run it again after every SDK change, or shaders that used to load stop loading.

## Open a device and create a renderer {.step}

The device is asynchronous and everything that uploads anything needs it, so it lives as a field rather than being rebuilt where it is wanted.

```dart
import 'dart:async';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_impeller/flutter3d_impeller.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

class SceneScreen extends StatefulWidget {
  const SceneScreen({super.key});
  @override
  State<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<SceneScreen>
    with SingleTickerProviderStateMixin {
  GpuRenderBackend? _device;
  Renderer? _renderer;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    unawaited(_openGraphics());
  }

  Future<void> _openGraphics() async {
    final GpuRenderBackend device;
    try {
      device = await GpuRenderBackend.create();
    } catch (error) {
      if (mounted) setState(() => _initError = error);
      return;
    }
    if (!mounted) return;
    _device = device;

    setState(() {
      try {
        // The fallbacks a material without a map samples are the renderer's
        // own unless you pass others: neutral textures instead of per-map
        // flags, so the shader needs no branch and the engine no bookkeeping
        // about which maps a material happens to have.
        _renderer = Renderer.create(device: device);
      } catch (error) {
        _initError = error;
      }
    });
  }
}
```

Report `_initError` on screen rather than throwing. The overwhelmingly likely cause is a missing shader bundle, and a message naming `build_shaders.sh` saves the next person twenty minutes.

## A scene that is never null {.step}

```dart
/// Empty until content arrives, and **never null**.
Scene _scene = Scene();
```

<div class="warn">
<p>This is the one line worth copying verbatim. The renderer must build its frame targets before anything else has taken device memory, and waiting for a model to load means a dozen textures are uploaded first. On some machines that combination fails to allocate — <em>every frame, from the first</em>, and the picture is an error screen. Start with an empty scene and add to it.</p>
</div>

## Draw a frame {.step}

```dart
class SceneSurface extends StatelessWidget {
  const SceneSurface({
    super.key,
    required this.renderer,
    required this.scene,
    required this.view,
    required this.settings,
  });

  final Renderer renderer;
  final Scene scene;
  final RenderView view;
  final RenderSettings settings;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final frame = renderer.render(
          width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
          height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
          scene: scene,
          views: <RenderView>[view],
          settings: settings,
        );
        // From the device rather than painted from an image: a backend whose
        // frame is composited elsewhere has no image to paint, and `present`
        // is the one answer both can give.
        return renderer.device.present(frame.frame);
      },
    );
  }
}
```

Drive it from a `Ticker` so the frame is rebuilt each vsync:

```dart
late final Ticker _ticker;
Duration _lastTick = Duration.zero;
double _elapsed = 0.0;

void _startTicking() {
  _ticker = createTicker((Duration now) {
    final dt = _lastTick == Duration.zero
        ? 1.0 / 60.0
        : (now - _lastTick).inMicroseconds / 1e6;
    _lastTick = now;
    _elapsed += dt;
    if (mounted) setState(() {});
  })..start();
}
```

## Geometry, a material and a light {.step}

```dart
void _buildScene(GraphicsDevice device) {
  final scene = Scene();

  // A shape is a value that builds MeshData on the CPU; the device turns that
  // into buffers. Bounds, culling and picking need only the first half.
  final ground = MeshNode(
    DeviceMesh.upload(device, const PlaneShape(width: 40, depth: 40).build()),
    Material(
      name: 'ground',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.24, 0.26, 0.28, 1.0),
      roughness: 0.95,
    ),
    name: 'ground',
  );

  final ball = MeshNode(
    DeviceMesh.upload(device, const SphereShape(radius: 1.0).build()),
    Material(
      name: 'ball',
      lighting: LightingModel.pbr,
      baseColor: Vector4(0.90, 0.42, 0.28, 1.0),
      metallic: 0.1,
      roughness: 0.32,
    ),
    name: 'ball',
  )..setPosition(0.0, 1.0, 0.0);

  // Key light: the one that casts shadows.
  final sun = LightNode(type: LightType.directional, intensity: 3.2)
    ..castsShadow = true
    ..setLocalForward(Vector3(-0.4, -1.0, -0.3));

  // Fill, and a spot for shape.
  final fill = LightNode(
    type: LightType.point,
    color: Vector3(0.4, 0.6, 1.0),
    intensity: 8.0,
    range: 14.0,
  )..setPosition(-5.0, 3.0, 4.0);

  final spot = LightNode(
    type: LightType.spot,
    color: Vector3(1.0, 0.86, 0.7),
    intensity: 18.0,
    range: 20.0,
    innerConeAngle: 0.25,
    outerConeAngle: 0.5,
  )
    ..setPosition(4.0, 6.0, 2.0)
    ..setLocalForward(Vector3(-0.5, -1.0, -0.3));

  scene..add(ground)..add(ball)..add(sun)..add(fill)..add(spot);
  setState(() => _scene = scene);
}
```

Up to **eight** lights of any type. They are packed into `vec4[8]` uniform arrays with the count as a uniform, so switching one on or off never rebuilds a pipeline.

## The camera, and something to turn it with {.step}

```dart
final CameraNode _camera = CameraNode(
  projection: const PerspectiveProjection(fovYRadians: 1.05, near: 0.1, far: 200.0),
  name: 'main',
);
late final RenderView _view = RenderView(camera: _camera)
  ..clearColor = Vector4(0.05, 0.07, 0.10, 1.0);

late final OrbitController _orbit = OrbitController(_camera, distance: 8.0);
```

Wire it to gestures, and frame whatever is in the scene:

```dart
GestureDetector(
  onScaleStart: (d) => _lastFocal = d.localFocalPoint,
  onScaleUpdate: (ScaleUpdateDetails d) {
    final delta = d.localFocalPoint - _lastFocal;
    _lastFocal = d.localFocalPoint;
    _orbit
      ..rotate(-delta.dx * 0.006, -delta.dy * 0.006)
      ..zoom(1.0 / d.scale.clamp(0.5, 2.0))
      ..apply();
    _orbit.syncProjectionDepth(_camera);
  },
  child: sceneSurface,
);

// After the scene is built:
_orbit
  ..frameBounds(_scene.computeBounds())
  ..apply();
```

<div class="note">
<p><code>syncProjectionDepth</code> fits near and far to what is actually framed. Leaving <code>near</code> at a tiny default while <code>far</code> is 200 spends the whole depth buffer on the first metre, and the symptom is z-fighting on surfaces that are nowhere near each other.</p>
</div>

## Shadows, bloom and tone mapping {.step}

```dart
RenderSettings _settings = const RenderSettings(
  exposure: 1.6,
  tonemap: true,
  shadows: ShadowSettings(
    enabled: true,
    cascades: 3,       // one to three, side by side in one texture
    resolution: 1024,  // the atlas is resolution × cascades wide
    cascadeSplit: 0.7,
    bias: 0.0015,
    normalOffset: 0.02,
  ),
  bloom: BloomSettings(
    enabled: true,
    threshold: 1.0,    // display white
    knee: 0.5,
    intensity: 0.06,
    levels: 5,
  ),
  fog: FogSettings(density: 0.0),
);
```

Three cascades at the default 2048 is a six-thousand-pixel HDR texture and about a hundred megabytes. Three tiles of 1024 cover a scene far better than one of 4096, so prefer a smaller tile *and* cascades.

## Load a model and play a clip {.step}

Do not await this before the first frame. Draw a placeholder, and swap the model in when it arrives.

```dart
ModelAsset? _asset;
AnimationPlayer? _player;
String? _clip;

Future<void> _loadModel(GraphicsDevice device, Scene scene) async {
  try {
    final document = await decodeModelInIsolate(
      ModelLoadRequest(source: const BundleAssetSource('assets/models/hero.glb')),
    );
    final asset = await ModelAsset.fromDocument(
      document,
      device: device,
      name: 'hero',
    );
    if (!mounted) return;

    final instance = asset.instantiate(scene, name: 'hero');
    setState(() {
      _asset = asset;             // held, so nothing collects it out from under the scene
      _player = instance.player;  // null when the file has no clips
    });

    for (final warning in asset.warnings) {
      debugPrint('model: $warning');
    }
  } catch (error) {
    debugPrint('model: could not load, carrying on without it ($error)');
  }
}
```

Advance the player **once a frame**, not once a simulation step, an animation should run at whatever the display does:

```dart
void _animate(double dt) {
  final player = _player;
  if (player == null) return;

  const wanted = 'idle';
  if (wanted != _clip) {
    player.crossFadeToNamed(wanted, duration: 0.14);
    _clip = wanted;
  }
  player
    ..speed = 1.0
    ..update(dt);
}
```

Non-fatal decoding problems land in `warnings` rather than failing the file, a skipped primitive or an ignored extension explains a model that looks odd but still loaded.

<div class="note">
<p>There is no <code>hero.glb</code> in this repository; the name stands for whatever animated <code>.glb</code> you have. The demo applications keep theirs under <code>apps/flutter3d_demo_*/assets/models/</code> (the platformer's runner is <code>penguin.glb</code>), and the catch above means a missing file leaves the scene running rather than broken.</p>
</div>

## Click on something {.step}

Picking is CPU-side and needs no device: ray/AABB from the BVH, then Möller–Trumbore against triangles for any node that kept its source data.

```dart
final Raycaster _raycaster = Raycaster();
final List<SceneNode> _selected = <SceneNode>[];

void _pick(Offset local, Size size) {
  // x and y are widget coordinates from the top left, exactly as Flutter
  // reports a pointer. The Y flip and the aspect ratio live in setFromScreen
  // rather than here, because those are the two things that get silently
  // reversed.
  final hit = _raycaster
      .setFromScreen(_camera, local.dx, local.dy,
          width: size.width, height: size.height)
      .intersectScene(_scene);

  setState(() {
    _selected
      ..clear()
      ..addAll(<SceneNode>[if (hit?.node != null) hit!.node!]);
    _settings = _settings.copyWith(highlighted: _selected);
  });
}
```

<div class="warn">
<p>The <code>HitResult</code> is reused by the next call. Copy anything that has to outlive it.</p>
</div>

## Particles, and the overlay that tells you what happened {.step}

```dart
final ParticleSystem _particles = ParticleSystem(capacity: 2000);

// once, after the renderer exists
_renderer?.addContributor(ParticleContributor(_particles));

// once a frame
_particles.advance(dt);

// when something happens
_particles.burst(Effects.spark, hit.point, direction: hit.normal);
```

<div class="note">
<p><code>Effects</code> is not engine API. <code>burst</code> takes a <code>ParticleEffect</code>, and a game keeps its own catalogue of those as constants; each demo application defines one in its own <code>lib/src/effects.dart</code> (for instance <code>apps/flutter3d_demo_platformer/lib/src/effects.dart</code>), and copying an entry from there is the fastest way to a first effect.</p>
</div>

Turn on the debug overlay while you are still finding out where things are. All of it is drawn in **one** call.

```dart
_settings = _settings.copyWith(
  debug: const DebugDrawOptions(
    bounds: true,
    normals: false,
    lightGizmos: true,
    axes: true,
    cameraFrustums: false,
  ),
);
```

<div class="why">
<p>Judging a render by eye does not scale. If a setting looks like it does nothing, capture the same frame with it on and off and diff the two: a zero difference answers the question.</p>
</div>

## When nothing appears {.step}

The failures that produce a picture rather than an error, in the order they are worth checking.

| Symptom | Cause |
|---|---|
| `Failed to initialize ShaderLibrary` | The bundle is missing or stale, or `FLTEnableFlutterGPU` is not in `Info.plist` |
| Black viewport, no errors at all | `Viewport` and `Scissor` default to a zero-sized rect and the API does not complain |
| The model is clipped against the near plane | The projection's depth convention — Impeller wants `[0, 1]`, not OpenGL's `[-1, 1]` |
| Everything is culled away | Y flipped in the projection, which reverses on-screen winding |
| Draw count goes up, nothing appears | There is no non-indexed draw. Bind an index buffer even for the identity sequence |
| The scene is all ambient | A light direction that was normalised into a new vector instead of in place |
| Geometry flickers under load | `HostBuffer.reset()` right after an async `submit()`. Use a ring of ~3 host buffers |
| Background washes out | A display-referred clear colour going through the sRGB encode twice |

The full list, with the fix for each, is on the [Pitfalls](/reference/pitfalls/) page.

## Where to go from here

You now have a renderer, a scene and a loop. What you do not have is a *game*, no fixed step, no collision, no level, no input that survives a slow frame. That is the [simulation layer](/core/simulation/), and the two genre tutorials build a whole game on top of it:

- [Build a shooter](/shooter/tutorial/): weapons, monsters that path around corners, an inventory, locked doors, saves
- [Build a platformer](/platformer/tutorial/): a double jump with coyote time, wall slides, ice and conveyors, springs, checkpoints
