---
description: The shooter, built against the WebGL2 backend and running in this page. Monsters, weapons, torchlight and a view model, in a browser.
---

# Demo: the shooter in a browser

*Dungeon*, running on `flutter3d_webgl`. The crypt, its monsters, four weapons and the weapon held in the hands, through the same HAL the desktop build uses, with one file swapped.

<div class="demo">
  <iframe class="demo-frame" src="/demo/shooter/" title="Dungeon — the shooter demo" allow="autoplay; pointer-lock"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>1280×720</b> internal, scaled by CSS</span>
    <span><a href="/demo/shooter/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first; the keyboard goes to whatever was clicked last. This one takes appreciably longer to start than the platformer: the crypt is a bigger level with more textures, and the counters in the corner report the catch-up while it settles.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W A S D</dt><dd>Move</dd></div>
  <div><dt>Mouse</dt><dd>Aim. Click once and the browser hands the pointer over; Escape gives it back</dd></div>
  <div><dt>Click</dt><dd>Fire, once the pointer is captured</dd></div>
  <div><dt>1 2 3 4</dt><dd>Fists, pistol, shotgun, rocket launcher</dd></div>
  <div><dt>E or F</dt><dd>Use: doors, lifts, buttons, notes</dd></div>
  <div><dt>Space</dt><dd>Jump</dd></div>
  <div><dt>Shift</dt><dd>Sprint</dd></div>
  <div><dt>M</dt><dd>The automap: what you have walked, with the fight running underneath</dd></div>
  <div><dt>R</dt><dd>Restart, once the run is over</dd></div>
  <div><dt>F</dt><dd>Toggles the fog, which is also a before-and-after measurement</dd></div>
</dl>

## What else is in the crypt

- **Dying plays back.** The last three seconds run again through the ordinary step, sounds and all, with the camera standing back from the body; then the death is put back. That is a `RewindBuffer`, one keyframe a second and the tape between, and it is the [simulation page's](/core/simulation/#rewind) worked example.
- **A rocket leaves a hole.** A wall a rocket hits is cut, mesh and collision together, and you can walk through what is left. The hole goes into the save and into the demo, so a replay arrives at the same walls.
- **Every run is written down.** When a run ends, either way, the level, the starting snapshot and every step's intent go out as `demo.json`, so the file that reproduces a bug exists before anybody asks for it.
- **Walls muffle.** A torch behind a door is quieter *and* duller than one in the room, and one three rooms away is barely there; each wall between a sound and your ears takes half.
- **The walls light each other.** Every level ships with a baked lightmap: the glow a torch-lit wall throws across the floor, with two bounces, added under the dynamic torches. The torches still flicker; the bounce does not need to.
- **Rooms behind walls are not drawn.** The crypt ships with a visibility table baked beside it, and a frame leaves out every batch of wall no cell near the eye can see.

## Fire and look are the same two buttons they are on a desktop

They were not, and the reason is worth keeping. A browser was treated as a platform with no pointer to capture, so a drag stood in for the mouse; and a drag that also had to *not* fire would have made aiming and shooting mutually exclusive, so they were one gesture. That is a reasonable answer to the wrong question. Browsers have had `requestPointerLock` for a decade; `pointer_lock` simply had no browser backend.

It has one now, so this build behaves like the desktop one: the pointer is captured on the first click, the mouse aims, the button fires, Escape releases. On a phone the on-screen stick appears instead, which it never used to, because the guard that hid pointer capture hid the touch controls as well. Flutter reports a mobile browser as `android` or `iOS`, so nothing had to be detected for that.

`Playing` asks the three questions separately now: can the pointer be captured, where does the camera come from, does the player have fingers. `kIsWeb` was one answer to all three, and wrong about two.

## What the browser costs

Sound, pointer capture and saved settings were all listed here as missing. All three work now: `flutter_soloud` ships a WebAssembly build, `pointer_lock` grew a browser backend over `document.requestPointerLock`, and settings and saves live in `localStorage` instead of files.

| | |
|---|---|
| **Frame rate** | 53 fps with no dropped frames on the WebAssembly build, against 60 on Impeller. It was 15–30 before `--wasm` and before the cube atlas stopped being sized from the cascade's resolution. The crypt is the heavier of the two demos: more lights, more shadow casters, particles on every torch, a second pass for the view model |
| **Fixed resolution** | 1280×720 internally, stretched by CSS. A `WebGlDevice` owns its canvas and a WebGL canvas resets its drawing buffer when resized |
| **Download** | About 55 MB |

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
// A first-person camera reads the look delta inside the step, so the loop is
// the right place to drain it — unlike the platformer, whose follow camera
// reads it during the frame. Which *source* it drains is `Playing`'s answer,
// not this file's.
void _drainLook(Vector2 out) {
  if (Playing.dragLook) {
    _dragLook.drainInto(out);
  } else {
    _devices.drainLook(out);
  }
  _pad.drainLook(out);
}
```

There is no `kIsWeb` anywhere in this application. The drag layer above the frame is mounted `if (Playing.dragLook)`, the capture is asked for `if (Playing.capturesPointer)`, and the on-screen stick appears `if (Playing.touch)`. A desktop browser takes all three branches a desktop takes.

Nothing in `flutter3d`, `flutter3d_game`, `flutter3d_physics` or `flutter3d_game_shooter` changed to make this run.

## Three things that had to be fixed

Each was a real defect instead of a web caveat, and each is fixed in the repository.

1. **The generated GLSL was stale.** `flutter3d_webgl/lib/engine_shaders.dart` had not been regenerated since cascaded shadows added `shadow_matrix_far`, so the backend could not draw one sphere. [The detail is on the platformer's demo page](/platformer/demo/#the-bug-this-demo-found).
2. **The canvas took the pointer.** A WebGL canvas is a display surface, not a control, and left interactive it swallowed every event the widgets above it needed. It now carries `pointer-events: none`.
3. **`pointer_lock` threw where it promised not to.** `PointerLock` documents that it no-ops on a platform without an implementation, and it does. Its constructor, though, subscribed to an event channel, and that is a `MissingPluginException` on the first listener. It hands back an empty stream now, which is what "this platform never changes capture state" comes to in code.

## Building it yourself

```bash
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_dungeon && flutter build web --release)
python3 -m http.server 8000 --directory apps/flutter3d_demo_dungeon/build/web
```

## Next

- [Demo: the platformer](/platformer/demo/): the lighter of the two
- [Writing a HAL backend](/core/backends/): the contract that made this a swap rather than a port
- [Tutorial: build a shooter](/shooter/tutorial/): how the game itself is put together
