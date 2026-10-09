# A Flame game that owns its 3D world

A Flame game with the `HasFlutter3d` mixin has its scene, camera, renderer
and projector as fields of its own, and builds its 3D world the way it
builds everything else: in code that runs once Flame has loaded it.
`Flutter3dFlameWidget` then needs nothing but the game.

## Step 1: Hand the game a device

On its own the widget opens the device and the scene. Here the page already
has both, so the game is opened on them directly, and the widget sees a game
whose world is already open.

{{code open}}

## Step 2: Build the world in onOpen3d

`onOpen3d` runs once, after the game has loaded and its world is open,
whichever of the two came first. The crates, the layer that hears taps and
the hitbox lines are all the game's own. `createCamera3d` hands it the
page's orbiting camera, so that what it projects is what is drawn.

{{code world}}

## Step 3: A tap on what the camera shows

Flame decides whether a point is inside a component on the plane the game
plays on. Seen through a perspective camera, a crate is drawn somewhere
else, larger near and smaller far, and Flame's own test misses it.
`Tap3dCallbacks` asks whether the tap falls on the screen rectangle the
crate's node covers, and `Taps3dComponent` gives each tap to the nearest
crate under it. The crate flashes through its `tint`, which is its alone
though the three share a material, and puts a "+1" over itself in Flame's
layer at the point the projector gives.

{{code crate}}

On the page a crate is tapped every second and a half through that same
path. The green outlines are the crates' hitboxes, drawn in the scene where
the crates are; Flame's `debugMode` would draw them flat on its own canvas.
