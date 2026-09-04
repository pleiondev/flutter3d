---
description: The racing game built against the WebGL2 backend — unplayable for months, and what the two changes that fixed it were.
---

# Demo: the racing game in a browser

*Ring*, running on `flutter3d_webgl`. It builds, it loads, it draws the circuit, and for months it did all of that at well under one frame a second. That is what this page used to be about. It drives now, and the page keeps the hunt, because what was wrong was not where anybody looked.

<div class="demo">
  <iframe class="demo-frame" src="/demo/racing/" title="Ring, the racing demo" allow="autoplay; pointer-lock" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>960×540</b> internal</span>
    <span><a href="/demo/racing/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

## What was measured, and what it was not

The frame budget was the first suspect and it was wrong.

| Setting | Result |
|---|---|
| 1280×720, 3 cascades at 2048 (the desktop settings) | Countdown ran at roughly a fifth of real time; a JavaScript evaluation on the page timed out after 45 s |
| 960×540, 2 cascades at 1024 | No measurable change |
| 480×270, 1 cascade at 512 | No measurable change |

Dropping to a twelfth of the shadow atlas and a ninth of the pixels changed nothing, so **the cost was not fill rate**. That measurement looked like a dead end and was the clue: a smaller frame buys back fill rate, and touches nothing a frame *allocates*.

### It was the shadow atlas, and not for the reason it looks

The cube atlas for point lights is six tiles across and one row per shadowed light. Its tile size came from `ShadowSettings.resolution`, the number a game sets for the *sun*. This game asks for 1024 on the web, so the atlas came out 6144 × 4096 texels of `r16g16b16a16Float`: **201 MB**, and there are two of them, the movers and the bake. Four hundred megabytes of texture on a platform where a tab has less, for a circuit lit mostly by a directional light.

Shrinking the frame never touched it, because the atlas is not sized from the frame. `ShadowSettings.cubeResolution` is its own number now, defaulting to 512, and the two atlases come to 100 MB together — a quarter of what they were, with golden sets that did not move a pixel when it changed.

### And the compiler

The demos are built with `--wasm` now. dart2wasm compiles the simulation to WebAssembly instead of JavaScript: a car's tire model, three AI drivers, a spline a kilometre long. The games are the one thing on this site that spends its frame budget in Dart instead of in a driver.

## What it runs at now

The shooter's own counter read **53 fps with no dropped frames** in the crypt, against 15–30 before these two changes — one machine, one reading, with the browser and the date unrecorded, so it is the size of the change and not a figure to reproduce. This game has no counter on screen. What it has is a lap clock that keeps real time, three AI drivers that hold their line, and a car that answers the wheel.

<div class="note">
<p>Both fixes came out of a shadow investigation, not a performance one. The memory was measured while chasing a straight edge in a teapot's shadow, and nobody had thought to ask what a cube atlas costs when its tile comes from a setting named for the sun.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W or ↑</dt><dd>Throttle</dd></div>
  <div><dt>S or ↓</dt><dd>Brake, and reverse once stopped</dd></div>
  <div><dt>A D or ← →</dt><dd>Steer. The lock falls away with speed, which is <code>steerFalloff</code></dd></div>
  <div><dt>Space</dt><dd>Handbrake</dd></div>
  <div><dt>T, or the pad's north face</dt><dd>Change tyres — the pit stop, and the one control that repairs a damaged car. A verb the car has rather than a screen, so it rebinds like any other</dd></div>
  <div><dt>R</dt><dd>Race the season again, once it is over. Gated on that deliberately: a key that throws away four won circuits mid-lap is worse than no key</dd></div>
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

`SceneSurface` reads those instead of naming numbers. It used to be the third copy of that widget in this repository, and the argument for leaving it copied was that the three differed in exactly one place. That argument did not survive: the widget is `flutter3d_session`'s now — `packages/flutter3d_session/lib/src/scene_surface.dart`, re-exported through `flutter3d_app` — and the place the three differ is a constant each application passes in. See [assembling an application](/core/session/).

## Building it yourself

```bash
# What this site serves, for all three games at once: regenerates the GLSL,
# builds each to WebAssembly and puts them in the site's own dist/demo/.
(cd site && tool/demos.sh)

# Or one game by hand.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_racing && flutter build web --wasm --release --base-href=/demo/racing/)
```

The desktop build, which is still the sharper one — 1280×720 with three cascades against 960×540 with two:

```bash
(cd apps/flutter3d_demo_racing && flutter run -d macos)
```

## Next

- [What a racing game adds](/racing/): the track, the car, the tire, the lap
- [Tutorial: build a racing game](/racing/tutorial/): the whole thing, step by step
- [Writing a HAL backend](/core/backends/): the contract that made this a swap rather than a port
