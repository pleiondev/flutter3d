---
description: River Sortie, a jet up a river that never ends after River Raid, written as a Flame game and drawn in 3D by flutter3d, built against the WebGL2 backend and running in this page.
---

# Demo: River Sortie in a browser

A jet flies up a river that narrows and splits round islands. Tankers and helicopters wait on it, jets cut across it, the tank runs dry unless the jet flies low over a fuel depot, and every stretch ends in a bridge that has to be shot down to pass. It is a homage to River Raid, which Carol Shaw wrote for the Atari 2600 in 1982, and a Flame game from end to end: flutter3d draws it and does nothing else.

<div class="demo">
  <iframe class="demo-frame" src="/demo/river/" title="River Sortie, the river demo" allow="autoplay" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGL2 · drawn at the frame's own size</span>
    <span><a href="/demo/river/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>Click the frame first; the keyboard goes to whatever was clicked last. The sound starts with the first take-off, because a browser lets a page make a sound only after you have done something in it. Until the models arrive the craft are plain shapes, and they stay that way if the models will not load.</p>
</div>

## Controls

<dl class="keys">
  <div><dt>Space</dt><dd>Take off, and fire while held</dd></div>
  <div><dt>Left and right, or A and D</dt><dd>Steer across the river</dd></div>
  <div><dt>Up and down, or W and S</dt><dd>Open and close the throttle</dd></div>
  <div><dt>Stick and fire button</dt><dd>On a phone: Flame's own <code>JoystickComponent</code> and <code>HudButtonComponent</code>, feeding the same input the keys do</dd></div>
</dl>

## The rules

**The cartridge's scoring.** A tanker is 30, a helicopter 60, a fuel depot 80, a jet 100 and a bridge 500. Every ten thousand points is another jet in reserve, and a lost jet's replacement starts past the last bridge brought down. The river is the same every run: a seeded generator lays it out a stretch at a time, the way the cartridge's river was the same every time it was switched on.

**Five levels, and a task each.** Bring down two bridges; sink six tankers; down five helicopters, some of which shoot back; shoot three jets as they cross; sink eight tankers and down four helicopters on scarce fuel. After that the river goes on for ever. The last bridge of a level is shielded until its task is done: glowing rails show it, a shot throws sparks off it, and the panel says what is still wanted.

**Things go down the way they would.** A tanker lists and sinks trailing smoke. A helicopter spins into the river. A depot goes up and takes whatever is close with it, including a jet refuelling over it. A bridge breaks in the middle and each half swings into the water. Anything hit loses its hitbox at once, so a sinking tanker is scenery.

## What this one shows that Meteor Yard does not

**Flame decides every hit.** Meteor Yard runs flutter3d's physics and relays its contacts into Flame. Here it is the other way round: every moving thing is a Flame component with a Flame hitbox, Flame's collision detection finds the overlaps, and `onCollisionStart` says what hit what. Each component is an `Object3dComponent`, so its Flame position is written into a scene node every frame, and that is all the 3D side is told.

**Flame paints the instrument panel.** The score, the fuel gauge, the jets in reserve and the orders are drawn on Flame's own canvas in its viewport, over the 3D surface.

**The banks are not hitboxes.** The river's edge is a curve the course can answer for any point, so the jet asks whether it is over water rather than colliding with the hundreds of boxes a bank would need.

**Free models, fitted to a length.** The jets, the helicopter and the tankers are free models in whatever unit their authors used, placed with `ModelAsset.instantiateFitted`. The valley, the trees, the bridges and the depots are built in code, painted with vertex colours through `LinearColor.fromSrgb` and `MeshData.withColor`, one mesh per stretch of river.

The game's source is `apps/flutter3d_demo_river`, and its README credits the models.

## Building it yourself

```bash
# What this site serves.
(cd site && tool/demos.sh river)
```

On a desktop, or starting on a later level:

```bash
(cd apps/flutter3d_demo_river && flutter run -d macos)
(cd apps/flutter3d_demo_river && flutter run -d macos --dart-define=RIVER_LEVEL=3)
```

## Next

- [Demo: Meteor Yard](/arcade/demo/): the other Flame game, with every bridge at once
- [The showcase](/showcase/): a page for each bridge, with a live scene
- [The package reference](/reference/packages/#flame_flutter3d): what each bridge does
