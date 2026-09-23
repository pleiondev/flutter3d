---
description: The strategy game, built against the WebGL2 backend and running in this page. A crowd on a hillside, a fog that belongs to one side, and a pointer answered by pixel.
---

# Demo: the strategy game in a browser

A match on a hillside, running on `flutter3d_webgl`, or on WebGPU where the browser offers it. Your camp is in the near corner and a bot's is in the far one, both digging the same ground towards the same finishing line. The engine, the simulation and the map are the ones the desktop build plays; only the backend the application asks for is different.

<div class="demo">
  <iframe class="demo-frame" src="/demo/strategy/" title="The strategy demo" allow="autoplay" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · <b>960×540</b> internal, scaled by CSS</span>
    <span><a href="/demo/strategy/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first. The keyboard goes to whatever was clicked last, and a platform view takes the focus when you click it.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>Click the ground</dt><dd>Send your whole crowd there. It takes them off whatever they were digging, the way an order does</dd></div>
  <div><dt>Drag</dt><dd>Push the view across the map</dd></div>
  <div><dt>Scroll</dt><dd>Pull the camera back, or bring it in</dd></div>
  <div><dt>Hover a building</dt><dd>Lights it, and names it in the corner</dd></div>
</dl>

The line in the top corner is the score, meaning what each side has delivered, and it names the winner once there is one.

## What this one shows that the others do not

**The map is drawn through one side's eyes.** Ground none of your units has walked is under fog, ground you have left is dim, and the other side's crowd is drawn only where you can see it right now. The fog is a lattice of cells over the hillside, drawn as two instanced batches of boxes standing on the ground and resynced every frame from what your units can see. It is the largest thing on screen, and it is why this demo tests fill rate more than geometry.

**Hovering asks the renderer, not the bounding boxes.** This is the first game here to use the picking pass. Every other genre points with a ray against bounds, and the click on the ground still does. That answers "which box did I point at", and a box is a metre wider than the hall inside it. The picking pass draws the scene again with each mesh writing its own number, then reads back the one pixel under the cursor, so the answer follows the silhouette. It handles one question at a time: the pass costs a scene's worth of draws, and a pointer that moved sixty times a second would otherwise queue sixty of them and get each answer about where the cursor used to be.

**The opponent has no private door.** The bot issues the same orders through the same handles your click does, one decision every half second. That symmetry is what made it worth writing, because a mirrored opponent is a load test, a replay test and an opponent at once. None of the three works if the bot can reach past the interface.

## What changed in the application

The engine and the simulation did not change. The conditional import that picks a backend has moved out of this application into `flutter3d_app`, so what the application keeps is only what no two applications share:

```dart
// apps/flutter3d_demo_strategy/lib/src/backend.dart
const int kRenderWidth = 960;
const int kRenderHeight = 540;

const int kShadowCascades = kFixedResolution ? 2 : 3;
const int kShadowResolution = kFixedResolution ? 1024 : 2048;
```

The shadow numbers are branched for the same reason the racer's are, and the reason weighs more here. A cube shadow atlas is sized from `ShadowSettings.resolution`, the number a game picks for the *sun*, and a desktop's setting becomes a texture measured in hundreds of megabytes on a platform where a whole tab has less. This game reaches the browser with its budget already spent on ground, crowd and fog, so the atlas is the first thing to shrink. [The racing demo](/racing/demo/) tells how that was found.

## Building it yourself

```bash
# What this site serves, for every game at once: regenerates the GLSL, builds
# each one for the web and puts them in the site's own dist/demo/.
(cd site && tool/demos.sh)

# Or this one by hand. Without --wasm: the dart2wasm build of the WebGL
# backend throws on its first frame, which site/tool/demos.sh explains.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_strategy && flutter build web --release --base-href=/demo/strategy/)
```

The desktop build draws at whatever size the window is, with no fixed internal target:

```bash
(cd apps/flutter3d_demo_strategy && flutter run -d macos)
```

## Next

- [Demo: the racing game](/racing/demo/): where the shadow atlas was measured
- [Demo: the shooter](/shooter/demo/): the same swap, on a first-person game
- [Writing a HAL backend](/core/backends/): the contract that made this a swap and not a port
