## 0.8.3

**Flame's effects reach the scene in the frame they happen.** Flowing Flame
to the scene, `Object3dComponent` writes the scene again in `updateTree`,
after its children, and an effect is a child: written only in `update`,
before them, every `MoveEffect` and `RotateEffect` drew a frame late. It
still writes in `update` as well, so code that drives a component by
calling `update` itself, as the showcase's transform page does, keeps
working. Flowing the other way it reads the scene in `update`, so its
children see this frame's body.

**A nested component lands where Flame draws it.** The transform written
into the scene is the absolute one, so a component under another, a frog
on a log, is placed at the log plus the frog. It wrote its local position
as a world one. Read back from the scene, a nested component's position is
brought into its parent's space.

**A component let go stops being drawn at once.** `removeFromParent` hides
its node straight away; Flame takes the component out on its next
lifecycle pass, and until then the node was drawn a frame too long.

**The rest of Flame's transform crosses.** `elevation` lifts a component off
its plane along the normal, so one plane serves what floats and what flies
over it; `scenePosition` says where it is in the scene. Flame's `scale`
scales the node. Flame's visibility (`HasVisibility.isVisible`) hides and
shows it, written only when it changes, so a node blinked by hand still
blinks. And `visual`, a node under the bridged one made on first use, is
the game's to turn, bank or tilt: the bridge writes the bridged node's
rotation every frame and never touches `visual`'s. River Sortie dropped its
second plane, its hand-made pivot nodes and its node-level show and hide;
Meteor Yard its pivot map.

**`Flutter3dFlameWidget.onRendererReady`** hands a game the `Renderer` the
3D layer draws with, once it exists, for what only the renderer can do:
letting go of a streamed mesh after the frames in flight
(`Renderer.releaseMeshAfterFrame`), adding a contributor.

**`Object3dComponent` takes a `size` and an `anchor`.** A bridged component
that collides needs both: a `RectangleHitbox()` fills its parent's size, and
the anchor decides whether the point written into the scene is the centre
or the top-left corner. They were Flame's and set in every subclass's
constructor body, five times in River Sortie alone; they pass through the
constructor now.

## 0.8.2

**`PhysicsStepComponent` steps the physics on Flame's clock.** A
`RigidBodyComponent` never steps the shared world, so every bridged game
wrote the same small component to do it once a frame: the arcade, the
example, each its own copy. It is public now. It calls `Dynamics.step`, then
an optional `afterStep` for anything that follows a body the solver just
moved (a trigger sensor riding on a solid body), then `CollisionWorld.update`,
which is what sends contacts to a `CollisionBridge`. Give it a priority below
the components that read the bodies.

**`Flutter3dFlameWidget` closes the device it opened.** Without `existing`
it opens a `GraphicsDevice` and a `Renderer` of its own, and it never
released either: a page that came and went left a GPU context behind each
time. It now disposes both with itself, and still leaves a pair passed in
through `existing` to whoever passed it. It also takes its `BridgeClock` off
the game when it goes, so a game that outlives the widget stops calling
back into it, and a rebuild that hands in a different game moves the clock
to the new one. Before, the new game never got a clock, and the 3D layer
stopped following it.

**A removed component hears no more contacts.** `CollisionBridge` relayed
to its component whether or not it was still in a game, so a ship removed
on one frame could still be told it hit something on the next. Flame's own
collision system does not call a removed component, and now the bridge does
not either. `CollisionBridge.detach()` clears the collider's listener, for
a collider that outlives its component.

**`ActorSystemComponent` takes a `priority`** in its constructor, as every
other component does.

**`CameraSyncComponent` runs a `CameraSyncController` as a component**, for
a game that would rather order the camera sync among its components than
tick it from `onTick`. The controller itself is unchanged.

**`FlameInputBridge.onGameKeyEvent`** answers a `FlameGame`'s
`KeyboardEvents.onKeyEvent` in its own `KeyEventResult`. `onKeyEvent` answers
a component's `KeyboardHandler`, whose `true` means "keep propagating", and
every game that forwarded to it wrote the flip to `ignored`/`handled` by
hand.

**A Flame turn on a ground plane is no longer drawn mirrored.**
`BridgePlane.rotationFor` took its sign from `Quaternion.rotated`, which
computes `q̄·v·q` and turns a vector by `-θ`, while a node is drawn through
its matrix, which turns by `+θ`. On `BridgePlane.ground` a Flame angle of
+0.5, clockwise on screen, was drawn anticlockwise; on a backdrop the two
sign flips cancelled and it came out right. `rotationFor` and `angleFor` now
both work through the matrix a node is drawn with, and a test checks where
the node is drawn on every plane, where the old ones only checked that an
angle survived the round trip, which it did either way. An
`Object3dComponent` syncing rotation `flameToScene` on the ground plane turns
the other way than it did, which is the way Flame means.

**Flame is updated once a frame, not twice.** The bridge redrew the 3D layer
with a `setState` on the whole `Stack`, which rebuilt `GameWidget` every
frame, and `GameWidget` calls `game.update(0)` from its layout whenever it is
rebuilt: every frame the game updated twice and `onTick` saw a second call
with a `dt` of zero. Now only the 3D layer is rebuilt, and the `GameWidget`
is made once per game, so a rebuild from above (a HUD beside it) does not
reach Flame either.

It asks for `flutter3d_physics` `^0.8.2`, which brings the cloth fix.

## 0.8.1

**An example to start from.** `example/` is the smallest hybrid game: a Flame
HUD over a 3D yard, a cube whose Flame position drives its scene node, and a
crate that falls under `flutter3d_physics` onto a trigger pad and reports the
landing through Flame's own `onCollisionStart`. It runs the physics step as a
Flame component, so the order within a frame is the component tree's.

The README is rewritten around what the bridge does. Nothing in `lib/`
changed.

It asks for `flutter3d` and `flutter3d_physics` `^0.8.1`, which bring the
contact-shadow and folded-cloth fixes; the rest of its `flutter3d_*`
dependencies stay at `^0.8.0`.

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**A bridge to the Flame 2D game engine.** Flame draws its own layer, flutter3d
draws its own, and `Flutter3dFlameWidget` composites the two in one `Stack`,
Flame's `GameWidget` above flutter3d's `SceneSurface` — the same ordering
`apps/flutter3d_demo_platformer` already uses for a HUD over a bare
`SceneSurface`, and for the same reason: on the web the 3D surface is a
platform view that swallows pointer events, so whatever needs raw input has
to sit above it. A single `BridgeClock` component rides Flame's own game
loop rather than starting a second ticker, so the two engines' frames never
drift apart.

`BridgePlane` is the one place a Flame `Vector2` and a flutter3d `Vector3`
are the same point — a ground plane or a vertical backdrop, chosen once and
shared by every bridged component rather than reinvented per caller.
`Object3dComponent` keeps a Flame `PositionComponent` and a flutter3d
`SceneNode` at the same place on one `BridgePlane`, in whichever direction a
`SyncDirection` names; `ActorComponent` and `RigidBodyComponent` extend it to
carry a `flutter3d_sim` actor's or a `flutter3d_physics` rigid body's own
position across the same seam, and `ActorSystemComponent` centralises the
one `ActorSystem.step` every `ActorComponent` in a game shares.
`CollisionBridge` re-fires flutter3d's collision events as Flame's own,
projecting a 3D contact onto the bridge's plane. `FlameInputBridge` reuses
`flutter3d_game`'s own `Bindings`/`InputState` — a bridged game and a native
one share one rebinding UI and one saved binding file, not two input models.
`CameraSyncController` keeps an orthographic flutter3d camera and Flame's own
2D viewfinder framed the same.
