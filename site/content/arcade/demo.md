---
description: Meteor Yard, a top-down arcade game on Flame with a 3D yard underneath it, built against the WebGL2 backend and running in this page.
---

# Demo: Meteor Yard in a browser

A ship over a yard of pillars and rocks, with bots walking their lanes across it. The yard, the ship and the bots are drawn by flutter3d; the game around them is a Flame game, with its own component tree, its own collision callbacks and its own joystick. `flame_flutter3d` joins the two, and this is the one demo that uses every bridge it has at once.

<div class="demo">
  <iframe class="demo-frame" src="/demo/arcade/" title="Meteor Yard, the arcade demo" allow="autoplay" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · drawn at the frame's own size</span>
    <span><a href="/demo/arcade/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first; the keyboard goes to whatever was clicked last. Until the craft models arrive the ship and the bots are plain shapes, and they stay that way if the models will not load.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>W A S D or arrows</dt><dd>Fly. Up the screen is forward</dd></div>
  <div><dt>Joystick</dt><dd>On a phone, in the bottom-left corner: Flame's own <code>JoystickComponent</code>, feeding the same input the keys do</dd></div>
  <div><dt>Tap the status line</dt><dd>Play a lost level again</dd></div>
</dl>

## The rules

**A bot goes only when the ship flies at it.** The contact counts as a ram when the bot is within sixty degrees of the ship's heading. A bot that runs into the ship from the side or from behind is a hit on the ship instead, and a level ends after its last allowed hit.

**Four levels, each harder than the last.** More bots, faster bots, fewer hits allowed. From the second level some of the bots hunt: they leave their lane and chase the ship once it comes close, and they glow magenta so you can tell which. From the third, bots see a ram coming and step aside. No bot is faster than the ship, so every one of them can be caught.

## What this one shows that the others do not

**Two engines, one clock.** Flame's game loop drives everything: the physics step, the actor system and the transform sync are Flame components with priorities, so the order within a frame is the order of the component tree. flutter3d draws what the step left behind.

**A 3D contact arrives as a Flame collision.** The ship carries a trigger sensor in the physics world, and `CollisionBridge` reports its contacts through Flame's ordinary `onCollisionStart`, with the other party resolved to its Flame component. The game decides ram or hit there, in plain Flame code.

**Flame on top, 3D underneath.** The HUD is Flutter, the joystick is Flame, and both sit over the 3D surface in one `Stack`. The camera follows the ship through Flame's viewfinder, and the bridge turns its zoom into an orthographic height for the 3D camera.

The bridges themselves are in [the package reference](/reference/packages/#flame_flutter3d), and the game's source is `apps/flutter3d_demo_arcade`.

## Building it yourself

```bash
# What this site serves, for every game at once.
(cd site && tool/demos.sh arcade)

# Or by hand, without --wasm, for the reason site/tool/demos.sh gives.
(cd packages/flutter3d_webgl && dart run tool/generate_shaders.dart)
(cd apps/flutter3d_demo_arcade && flutter build web --release --base-href=/demo/arcade/)
```

On a desktop:

```bash
(cd apps/flutter3d_demo_arcade && flutter run -d macos)
```

## Next

- [The showcase](/showcase/): a page for each bridge, with a live scene
- [Demo: the platformer](/platformer/demo/): a whole game on flutter3d alone
- [Demo: the strategy game](/strategy/demo/): picking by pixel, and fog that belongs to one side
