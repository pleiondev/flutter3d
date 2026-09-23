---
description: The racing game built against the WebGL2 backend, unplayable in the browser for months, and the two changes that fixed it.
---

# Demo: the racing game in a browser

*Ring*, running on `flutter3d_webgl`. It built, loaded and drew the circuit, and for months it did all of that at well under one frame a second. This page used to be about that. The game drives now, and the page keeps the hunt for the cause, because the cause was somewhere nobody looked.

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Ring, the racing demo" allow="autoplay; pointer-lock" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>960×540</b> internal</span>
    <span><a href="/demo/racing/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

## What was measured, and what it was not

The frame budget was the first suspect, and it was the wrong one.

| Setting | Result |
|---|---|
| 1280×720, 3 cascades at 2048 (the desktop settings) | Countdown ran at roughly a fifth of real time; a JavaScript evaluation on the page timed out after 45 s |
| 960×540, 2 cascades at 1024 | No measurable change |
| 480×270, 1 cascade at 512 | No measurable change |

Dropping to a twelfth of the shadow atlas and a ninth of the pixels changed nothing, so **the cost was not fill rate**. That looked like a dead end and turned out to be the clue: a smaller frame buys back fill rate and does nothing about what a frame *allocates*.

### It was the shadow atlas, for a reason that isn't obvious

The cube atlas for point lights is six tiles across and one row per shadowed light. Its tile size came from `ShadowSettings.resolution`, the number a game sets for the *sun*. This game asks for 1024 on the web, so the atlas came out at 6144 × 4096 texels of `r16g16b16a16Float`: **201 MB**, and there are two atlases, one for the movers and one for the bake. That is four hundred megabytes of texture on a platform where a tab has less, for a circuit lit mostly by a directional light.

Shrinking the frame never touched it, because the atlas is not sized from the frame. `ShadowSettings.cubeResolution` is a separate number now, defaulting to 512, and the two atlases come to 100 MB together. That is a quarter of what they were, and the golden sets did not move by a pixel when it changed.

### And the compiler

For a while the demos were built with `--wasm`, which compiles the simulation to WebAssembly instead of JavaScript: a car's tire model, three AI drivers, a spline a kilometre long. The games are the one thing on this site that spends its frame budget in Dart and not in a driver. The dart2wasm build of the WebGL backend then turned out to throw on its first frame in the shooter and the platformer, so all the demos are built with dart2js until that is found; `site/tool/demos.sh` has the details.

## What it runs at now

The shooter's counter read **53 fps with no dropped frames** in the crypt, against 15 to 30 before these changes. That was one machine and one reading, and the browser and the date were not recorded, so treat it as the size of the change and not a figure to reproduce. This game has no counter on screen. It has a lap clock that keeps real time, three AI drivers that hold their line, and a car that answers the wheel.

<div class="note">
<p>Both fixes came out of a shadow investigation, not a performance one. The memory was measured while chasing a straight edge in a teapot's shadow, and until then nobody had asked what a cube atlas costs when its tile size comes from a setting named for the sun.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W or ↑</dt><dd>Throttle</dd></div>
  <div><dt>S or ↓</dt><dd>Brake, and reverse once stopped</dd></div>
  <div><dt>A D or ← →</dt><dd>Steer. The lock falls away with speed, which is <code>steerFalloff</code></dd></div>
  <div><dt>Space</dt><dd>Handbrake</dd></div>
  <div><dt>T, or the pad's north face</dt><dd>Change tyres. This is the pit stop, and the one control that repairs a damaged car. It is a verb the car has, not a screen, so it rebinds like any other</dd></div>
  <div><dt>R</dt><dd>Race the season again, once it is over. It only works then on purpose: a key that throws away four won circuits mid-lap is worse than no key</dd></div>
</dl>

Click the frame first. The keyboard goes to whatever was clicked last, and a platform view takes the focus when you click it.

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

`SceneSurface` reads those constants instead of naming numbers. It used to be the third copy of that widget in this repository, on the argument that the three copies differed in exactly one place. That argument did not hold up. The widget belongs to `flutter3d_app` now (`packages/flutter3d_app/lib/src/surface/scene_surface.dart`), and the place the three differed is a constant each application passes in. See [assembling an application](/core/session/).

## Building it yourself

```bash
# What this site serves, for every game at once: regenerates the GLSL, builds
# each one for the web and puts them in the site's own dist/demo/.
(cd site && tool/demos.sh)

# Or one game by hand. Without --wasm, for the reason above.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_racing && flutter build web --release --base-href=/demo/racing/)
```

The desktop build is still the sharper one. It draws at the window's own size with three cascades at 2048, where the browser gets 960×540 with two at 1024:

```bash
(cd apps/flutter3d_demo_racing && flutter run -d macos)
```

## Next

- [What a racing game adds](/racing/): the track, the car, the tire, the lap
- [Tutorial: build a racing game](/racing/tutorial/): the whole thing, step by step
- [Writing a HAL backend](/core/backends/): the contract that made this a swap and not a port
