---
description: The platformer, built against the WebGL2 backend and running in this page — the same engine, the same level, one line of the application changed.
---

# Demo: the platformer in a browser

*Ascent*, running on `flutter3d_webgl`. Same engine, same level file, same simulation — the only thing that changed is which backend the application asks for.

<div class="demo">
  <iframe class="demo-frame" src="/demo/platformer/" title="Ascent — the platformer demo" allow="autoplay"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>1280×720</b> internal, scaled by CSS</span>
    <span><a href="/demo/platformer/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first — the keyboard goes to whatever was clicked last. It takes a few seconds to start: the level's textures and the hero's <code>.glb</code> are fetched before the first frame.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W A S D</dt><dd>Run, read against the camera</dd></div>
  <div><dt>Space</dt><dd>Jump. Tap for a short one, hold for a full one. That is <code>jumpCut</code>. Again in the air for the double jump</dd></div>
  <div><dt>Drag</dt><dd>Turn the camera. Browsers give no pointer lock without a plugin, so a drag stands in for it</dd></div>
  <div><dt>Q</dt><dd>Dash. The pointer is the dash on desktop; here the pointer is busy looking</dd></div>
  <div><dt>Ctrl or C</dt><dd>Drop through a one-way platform</dd></div>
  <div><dt>Shift</dt><dd>Sprint</dd></div>
</dl>

Wall jumps, mantles, slides, long jumps and ground pounds are all in there — the full list of what each one costs is in [what a platformer adds](/platformer/#the-runner).

## What is actually different

Three files, and none of them is in the engine.

```dart
// lib/src/backend.dart — the whole of the choice
export 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';
```

A conditional import instead of a runtime branch, because the two backends pull in incompatible worlds: `flutter_gpu` does not compile for the web and `dart:js_interop` does not compile for macOS, so a file that imported both could target neither.

```dart
// lib/src/backend_web.dart
Future<GraphicsDevice> openDevice({required int width, required int height}) async {
  final device = WebGlDevice.create(
    width: width,
    height: height,
    // GLSL ES 3.00, translated from `flutter3d_shaders` by
    // `flutter3d_webgl/tool/generate_shaders.dart`. There is no compiled
    // bundle here: a browser compiles GLSL itself, so a "bundle" is a map
    // from the engine's entry point names to source text.
    sources: engineShaders,
  );
  if (device == null) throw StateError('WebGL2 is not available');
  return device;
}
```

Everything above that line is the ordinary frame: a `Scene`, a `CameraNode`, a `RenderView`, `Renderer.render`. The simulation does not know a browser is involved and neither does the renderer.

## What the browser costs

Stated rather than discovered, because a demo that hides its trade-offs is an advertisement.

| | |
|---|---|
| **Fixed resolution** | A `WebGlDevice` owns the canvas it was created with, and a WebGL canvas resets its drawing buffer when resized. So the frame is drawn at 1280×720 and the element is stretched to the layout by CSS, which is why `present` takes a `BoxFit` |
| **No pointer lock** | `pointer_lock` is a macOS plugin. It reports itself unsupported here and no-ops, exactly as it promises, so the drag stands in |
| **No sound** | `flutter_soloud` does not start in this build. `AudioScene` keeps its `SilentBackend` and the game plays on, which is the arrangement that exists so a machine with no audio device is not a machine that cannot play |
| **No settings or saves** | Both are files, and there is no filesystem. `SettingsFile` and `SaveFile` already promise never to throw and to fall back to defaults; they now resolve their directory lazily so that promise holds where `Platform.environment` does not exist |
| **Download** | About 50 MB, most of it textures and models |

## The bug this demo found

The WebGL backend shipped with all twenty-six shader entry points and could not draw a single sphere.

`lib/engine_shaders.dart` is generated — `flutter3d_shaders` translated to GLSL ES 3.00 by `tool/generate_shaders.dart`, and its own header says there is no check that the file is current. Cascaded shadows added `shadow_matrix_far` to the fragment uniform block, the generated file still had the old one, and the failure was exactly the one the HAL's contract names:

```
Bad state: uniform block "FragInfo" has no member "shadow_matrix_far".
It has: light_position, light_color, light_direction, light_cone, base_color,
emissive, camera_position, material, material2, frame_params, shadow_params,
shadow_matrix. The engine and the shader disagree about this block.
```

Re-running the generator fixed it. **A caller naming a member the block does not have is an error rather than a zero**, which is the one direction of that mismatch that fails loudly, and it is why the block is checked by name at all. The other direction, a shader reading a member nobody wrote, gets zeros and draws an unlit scene with nothing reported anywhere.

<div class="warn">
<p>That generated file is the seam's weak point, and it is weak by design instead of by accident: the compiled Impeller bundle makes the same bargain. Both are build outputs that go stale silently, and the thing that catches it is running them. There is no test that the translation is current.</p>
</div>

## Building it yourself

```bash
# Re-translate the shaders if the engine's GLSL has changed.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)

(cd apps/flutter3d_demo_platformer && flutter build web --release)
python3 -m http.server 8000 --directory apps/flutter3d_demo_platformer/build/web
```

## Next

- [Demo: the shooter](/shooter/demo/): the same swap, on a first-person game
- [Writing a HAL backend](/core/backends/): the contract this backend implements
- [Tutorial: build a platformer](/platformer/tutorial/): how the game itself is put together
