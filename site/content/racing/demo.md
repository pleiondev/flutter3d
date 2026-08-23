---
description: The racing game built against the WebGL2 backend — it renders correctly and is not yet playable at a usable frame rate, and this page says why.
---

# Demo: the racing game in a browser

*Ring*, running on `flutter3d_webgl`. It builds, it loads, and it draws the circuit correctly. It is **not playable in a browser yet**, and this page is about that rather than around it.

<div class="warn">
<p>This build runs at well under one frame a second. The countdown reaches zero after about a minute of real time, and the browser's main thread stops answering while a frame is in flight. The other two demos run: <a href="/platformer/demo/">the platformer</a> comfortably, <a href="/shooter/demo/">the shooter</a> at 15–30 fps. Play this one on the desktop build.</p>
</div>

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Ring, the racing demo" allow="autoplay" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>960×540</b> internal · renders, does not run</span>
    <span><a href="/demo/racing/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

## What was measured

The frame budget was the first suspect and it was wrong.

| Setting | Result |
|---|---|
| 1280×720, 3 cascades at 2048 (the desktop settings) | Countdown ran at roughly a fifth of real time; a JavaScript evaluation on the page timed out after 45 s |
| 960×540, 2 cascades at 1024 | No measurable change |
| 480×270, 1 cascade at 512 | No measurable change |

Dropping to a twelfth of the shadow atlas and a ninth of the pixels changed nothing, so **the cost is not fill rate**. That leaves geometry, draw submission, or something on the Dart side that is cheap under AOT and expensive under dart2js. It has not been found yet, and this page will say so until it has.

What is ruled out, and why it is worth ruling out: the same backend, the same renderer and the same shaders run the other two games. Whatever this is, it is specific to what a circuit asks for rather than general to WebGL2.

## What does work

- The track builds: the road ribbon, the barriers, the kerbs, the scenery brushes.
- The scene lights, shadows and fogs the same as on Impeller.
- The simulation is correct. It is simply being stepped a handful of times a second, so the lights take a minute to go out.
- Nothing errors. The console is clean apart from SoLoud declining to start.

That combination is worth stating plainly, because it is the useful half: the [HAL](/core/architecture/#the-hal) held. A third game reached a browser without an engine change, and what stopped it is a performance problem in one scene, not a portability one.

## Controls, for when it runs

<dl class="keys">
  <div><dt>W or ↑</dt><dd>Throttle</dd></div>
  <div><dt>S or ↓</dt><dd>Brake, and reverse once stopped</dd></div>
  <div><dt>A D or ← →</dt><dd>Steer. The lock falls away with speed, which is <code>steerFalloff</code></dd></div>
  <div><dt>Space</dt><dd>Handbrake</dd></div>
</dl>

Click the frame first: the keyboard goes to whatever was clicked last, and a platform view takes the focus when you click it.

## What changed in the application

The same conditional import as the other two games. `apps/flutter3d_demo_racing/lib/src/backend.dart` used to export the native backend unconditionally, with a comment saying the conditional would come back when there was a web build.

```dart
export 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';
```

One thing is new here. The shadow atlas is a per-build number now, because the desktop setting is a 6144-pixel HDR texture and a browser should not be asked for one:

```dart
// backend_native.dart          backend_web.dart
const int kShadowCascades = 3;  const int kShadowCascades = 2;
const int kShadowResolution = 2048;  const int kShadowResolution = 1024;
```

`SceneSurface` reads those instead of naming numbers, which is the third copy of that widget in this repository and the point at which it should become a package. It has not, because the three differ in exactly one place and a package whose only parameter is the thing each caller sets differently has moved an argument rather than removed a duplicate.

## Building it yourself

```bash
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_racing && flutter build web --release --base-href=/demo/racing/)
```

The desktop build, which is the one to actually drive:

```bash
(cd apps/flutter3d_demo_racing && flutter run -d macos)
```

## Next

- [What a racing game adds](/racing/): the track, the car, the tire, the lap
- [Tutorial: build a racing game](/racing/tutorial/): the whole thing, step by step
- [Writing a HAL backend](/core/backends/): the contract that made this a swap rather than a port
