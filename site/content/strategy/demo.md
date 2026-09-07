---
description: The strategy game, built against the WebGL2 backend and running in this page. A crowd on a hillside, a fog that belongs to one side, and a pointer answered by pixel.
---

# Demo: the strategy game in a browser

A match on a hillside, running on `flutter3d_webgl`. Your camp is in the near corner and a bot's is in the far one, both digging the same ground for the same finishing line. The same engine, the same simulation, the same map the desktop build plays; what changed is which backend the application asks for.

<div class="demo">
  <iframe class="demo-frame" src="/demo/strategy/" title="The strategy demo" allow="autoplay" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>1280×720</b> internal, scaled by CSS</span>
    <span><a href="/demo/strategy/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first; the keyboard goes to whatever was clicked last, and a platform view takes the focus when you click it.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>Click the ground</dt><dd>Send your whole crowd there. It takes them off whatever they were digging, the way an order does</dd></div>
  <div><dt>Drag</dt><dd>Push the view across the map</dd></div>
  <div><dt>Scroll</dt><dd>Pull the camera back, or bring it in</dd></div>
  <div><dt>Hover a building</dt><dd>Lights it, and names it in the corner</dd></div>
</dl>

The line in the top corner is the score — what each side has delivered — and it says who won once one of them has.

## What this one shows that the others do not

**The map is drawn through one side's eyes.** Ground nobody of yours has walked is under fog, ground you have left is dim, and the other side's crowd is drawn only where you can currently see it. That is a lattice of cells over the hillside, two instanced batches of boxes standing on the ground, resynced every frame from what your units can see. It is the largest thing on screen and it is the reason this demo is a fill-rate question rather than a geometry one.

**Hovering asks the renderer, not the bounding boxes.** This is the first game here to use the picking pass. A ray against bounds — which is what every other genre points with, and what the click on the ground still uses — answers "which box did I point at", and a box is a metre wider than the hall inside it. The pass draws the scene again with each mesh writing its own number and reads back the one pixel under the cursor, so the answer is the silhouette. One question at a time: the pass costs a scene's worth of draws, and a pointer that moved sixty times a second would otherwise queue sixty of them and answer each about where the cursor used to be.

**The opponent has no private door.** The bot writes the same orders through the same handles the click above does, one thought every half second. That symmetry is why it was worth writing: a mirror is a load test, a replay test and an opponent at once, and none of the three works if the bot can reach past the interface.

## What changed in the application

Nothing in the engine and nothing in the simulation. The conditional import that picks a backend is not in this application at all any more — it lives in `flutter3d_backend`, reached through the `flutter3d_app` barrel — so what an application keeps is only what no two of them share:

```dart
// apps/flutter3d_demo_strategy/lib/src/backend.dart
const int kRenderWidth = 960;
const int kRenderHeight = 540;

const int kShadowCascades = kFixedResolution ? 2 : 3;
const int kShadowResolution = kFixedResolution ? 1024 : 2048;
```

The shadow numbers are branched for the same reason the racer's are, and the reason lands harder here. A cube shadow atlas is sized from `ShadowSettings.resolution`, the number a game picks for the *sun*, and a desktop's setting turns into a texture measured in hundreds of megabytes on a platform where a whole tab has less. This game arrives at a browser with its budget already spent on ground, crowd and fog, so the atlas is the first thing asked to be smaller. See [the racing demo](/racing/demo/) for the hunt that found it.

## Building it yourself

```bash
# What this site serves, for every game at once: regenerates the GLSL, builds
# each to WebAssembly and puts them in the site's own dist/demo/.
(cd site && tool/demos.sh)

# Or this one by hand.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_strategy && flutter build web --wasm --release --base-href=/demo/strategy/)
```

The desktop build, which draws at whatever size the window is rather than at a fixed internal target:

```bash
(cd apps/flutter3d_demo_strategy && flutter run -d macos)
```

## Next

- [Demo: the racing game](/racing/demo/): where the shadow atlas was measured
- [Demo: the shooter](/shooter/demo/): the same swap, on a first-person game
- [Writing a HAL backend](/core/backends/): the contract that made this a swap rather than a port
