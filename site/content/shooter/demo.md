---
description: The shooter, built against the WebGL2 backend and running in this page — monsters, weapons, torchlight and a view model, in a browser.
---

# Demo: the shooter in a browser

*Dungeon*, running on `flutter3d_webgl`. The crypt, its monsters, four weapons and the weapon held in the hands — through the same HAL the desktop build uses, with one file swapped.

<div class="demo">
  <iframe class="demo-frame" src="/demo/shooter/" title="Dungeon — the shooter demo" allow="autoplay"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>1280×720</b> internal, scaled by CSS</span>
    <span><a href="/demo/shooter/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first — the keyboard goes to whatever was clicked last. This one takes appreciably longer to start than the platformer: the crypt is a bigger level with more textures, and the counters in the corner report the catch-up while it settles.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W A S D</dt><dd>Move</dd></div>
  <div><dt>Drag</dt><dd>Aim <em>and</em> fire. Holding the button does both at once, which is what a captured pointer already does, so they are one gesture here instead of two fighting over the button</dd></div>
  <div><dt>1 2 3 4</dt><dd>Fists, pistol, shotgun, rocket launcher</dd></div>
  <div><dt>E or F</dt><dd>Use — doors, lifts, buttons, notes</dd></div>
  <div><dt>Space</dt><dd>Jump</dd></div>
  <div><dt>Shift</dt><dd>Sprint</dd></div>
  <div><dt>F</dt><dd>Toggles the fog, which is also a before-and-after measurement</dd></div>
</dl>

## Why fire and look are the same button

On desktop the pointer is captured, so moving the mouse aims and holding the button fires, at the same time and without either interfering.

A browser has no pointer lock without a plugin, so the drag has to stand in for the mouse, and a drag that also has to *not* fire would mean a shooter where aiming and shooting are mutually exclusive. Making them one gesture is closer to the real control than separating them would be.

The platformer made the opposite call. There the pointer is the dash, a single discrete verb, so spending one on every turn of the camera would be worse than moving it to a key.

## What the browser costs

| | |
|---|---|
| **Frame rate** | Around 15–30 fps here against 60 on Impeller. The crypt is the heavier of the two: more lights, more shadow casters, particles on every torch, and a second pass for the view model |
| **Fixed resolution** | 1280×720 internally, stretched by CSS. A `WebGlDevice` owns its canvas and a WebGL canvas resets its drawing buffer when resized |
| **No sound** | `flutter_soloud` does not start in this build; `AudioScene` keeps its `SilentBackend` and the game plays on |
| **No pointer lock** | `mouse_capture` is a macOS plugin, reports itself unsupported, and no-ops |
| **Download** | About 52 MB |

<div class="why">
<p>The frame rate is the honest number and it is worth reading rather than apologising for. Nothing here is optimised for this backend: the render list, the pass order and the shadow atlas are all sized for a discrete GPU, and the composite path blits a 720p frame to a canvas the browser then composites again. What the demo demonstrates is that the <em>seam</em> holds — that an engine written against a HAL runs on a backend it was not written for, not that WebGL2 is where this engine is fastest.</p>
</div>

## What changed in the application

The same three files as the platformer, plus one decision about the pointer.

```dart
// lib/src/backend.dart
export 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';
```

```dart
// A first-person camera reads `lookDelta` inside the step, so the loop is the
// right place for the delta on both paths — unlike the platformer, whose
// follow camera reads it during the frame.
_loop = GameLoop(
  input: _input,
  onStep: _step,
  drainLook: kIsWeb ? _drainDragLook : _devices.drainLook,
);
```

```dart
// A platform view takes every pointer event over it, so the drag is read from
// a transparent layer above the frame rather than from the listener around it.
if (kIsWeb)
  Positioned.fill(
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _keyboard.requestFocus();
        _dragging = true;
        _devices.pressPointer(ShooterActions.fire);
      },
      onPointerMove: (PointerMoveEvent event) {
        if (!_dragging) return;
        _dragLook.add(Vector2(event.delta.dx, event.delta.dy));
      },
      onPointerUp: (_) {
        _dragging = false;
        _devices.releasePointer(ShooterActions.fire);
      },
    ),
  ),
```

Nothing in `flutter3d`, `flutter3d_game`, `flutter3d_physics` or `flutter3d_shooter` changed to make this run.

## Three things that had to be fixed

Each was a real defect instead of a web caveat, and each is fixed in the repository.

1. **The generated GLSL was stale.** `flutter3d_webgl/lib/engine_shaders.dart` had not been regenerated since cascaded shadows added `shadow_matrix_far`, so the backend could not draw one sphere. [The detail is on the platformer's demo page](/platformer/demo/#the-bug-this-demo-found).
2. **The canvas took the pointer.** A WebGL canvas is a display surface, not a control, and left interactive it swallowed every event the widgets above it needed. It now carries `pointer-events: none`.
3. **`mouse_capture` threw where it promised not to.** `MouseCapture` documents that it no-ops on a platform without an implementation, and it does — except that its constructor subscribes to an event channel, which is a `MissingPluginException` on the first listener. It hands back an empty stream now, which is what "this platform never changes capture state" actually means.

## Building it yourself

```bash
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/dungeon && flutter build web --release)
python3 -m http.server 8000 --directory apps/dungeon/build/web
```

## Next

- [Demo: the platformer](/platformer/demo/): the lighter of the two
- [Writing a HAL backend](/core/backends/): the contract that made this a swap rather than a port
- [Tutorial: build a shooter](/shooter/tutorial/): how the game itself is put together
