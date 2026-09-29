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

**A phone's stick and button go through the input bridge.**
`FlameInputBridge.followJoystick(stick)` returns a component that writes a
Flame `JoystickComponent`'s deflection into the move axis every frame,
screen-up as forward, the way a gamepad's stick goes in; `bindButton(button,
action)` holds an action while an on-screen button is down. River Sortie
polled its stick in `update` and wired the button's three callbacks itself.

**`ChaseCamera` follows a bridged component in perspective.** From an
offset behind it, looking at a point ahead, following part way across if
asked, stiff or springy. It eases through `flutter3d_sim`'s `CameraRig`,
so `chase.rig.shake(0.5)` shakes it and a `CollisionWorld` with walls in it
keeps it out of them. `ChaseCameraComponent` runs one as a component.
River Sortie's hand-written camera went, and its camera shakes when the jet
goes down.

**`BridgeProjector` goes between the 3D camera and Flame's screen.**
`toScreen` says where a point of the scene is drawn, for a label or a
"+30" in Flame's viewport over a craft; `onPlane` says which point of a
plane is under a touch.

**`ChunkStreamer` builds an endless world piece by piece.** Given how a
piece is built and let go, `cover(from, to)` builds what came into view,
in order, and drops what left it; `clear` drops everything for a restart.
River Sortie's stretches of river are one.

**`InstancedObject3dComponent` draws many small things as one.** A Flame
component that takes a slot in a shared `InstancedMeshNode` while mounted,
writes its transform into it the way `Object3dComponent` writes a node's,
and gives it back when removed, at once. River Sortie's shots are one draw
however many are in the air.

**`Particles3dComponent` runs a `flutter3d_particles` system on Flame's
clock**, bursting from a Flame point with `burstAt`, and draws it through a
`MeshParticleContributor` once `drawWith` has the renderer, additively by
default or with `blend: MeshParticleContributor.darkening` for smoke. River
Sortie's fire, sparks and spray went into one pool and its smoke into
another, and `BurstComponent`, a scene node per shard, is gone. The package
now depends on `flutter3d_particles` 0.8.1, which is plain Dart.

**A road that bends under Flame's straight world.** `BridgeSpace` is where
a Flame point is placed and turned in the scene; `BridgePlane` is the flat
one, and `CurvilinearSpace` lays Flame's world along an `OpenPath`: `x` is
metres right of the road's middle, `-y` metres along it, and an angle turns
from the road's heading. `Object3dComponent(space:)` writes through it, so
an Enduro car keeps Flame hitboxes that mean side by side on the road
however the road winds.

**A world whose edges meet.** `WrapSpace` wraps its children's positions
round a rectangle, draws a ghost of each child within `margin` of an edge
on the other side (three in a corner) so a ship half over an edge is seen
on both, and gives the child ghost hitboxes one world across, so Flame's
own collision detection finds a contact across the seam and reports it to
the child itself. `shortestWay` is the direction across an edge when that
is shorter.

**An orthographic camera agrees with Flame to the pixel, and rolls.**
`CameraSyncController` takes a `viewportHeight`: with it, Flame's zoom is
pixels per world unit, the viewport's height over the camera's, rather
than the reciprocal convention that moved the right way and matched
nothing on screen. `syncAngle` keeps Flame's viewfinder angle and the
camera's turn about the plane's normal the same.

**`Flutter3dFlameWidget` passes Flame's overlays and focus on**:
`overlayBuilderMap`, `initialActiveOverlays`, `focusNode` and `autofocus`
reach the `GameWidget`, so a pause menu over the 3D layer is Flame's own
overlay rather than a second `Stack`.

**A model's animations play on Flame's clock.** `ModelAnimationComponent`
advances a loaded model's `AnimationPlayer` in its own update, so it stops
when the game is paused, and changes clip by name with a crossfade; asking
for the clip already playing does nothing, so a game can ask every frame.
`MeshFlipbookComponent` shows a handful of meshes in turn, an invader's two
poses.

**Flame's own events land where the player sees things.**
`ProjectedViewfinder` maps the screen to the game's plane through the 3D
camera: a component's `TapCallbacks`, Flame's hit test and
`camera.globalToLocal` in a game's code find the plane point under the
finger, where the viewfinder's affine transform put it metres away under a
perspective camera. The sky meets no plane and hits nothing. It changes
events and conversions; Flame still draws its world flat.

**A component lets go of the meshes it made.** `Object3dComponent(owns:)`
names meshes built for one component, a bridge's span, and gives them back
when the component is removed: through the renderer after the frames in
flight in a `HasFlutter3d` game, at once when there is no renderer. River
Sortie's bridges own their span and shield.

**An actor hears its contacts, and an instance has a colour.**
`CollisionBridge` relays to any component with Flame's collision callbacks,
an `ActorComponent` among them, rather than only a `RigidBodyComponent`;
a component that is not bridged is given a plane. `InstancedObject3dComponent`
has a `tint` and is an `OpacityProvider`, written into its slot's colour:
a hit flash on one invader of many.

**A game's own logic can run in fixed steps.** `HasFixedStep` on a
`FlameGame` spends each frame's time in steps of one size and calls
`fixedUpdate` on the game and on every `FixedStepUpdate` component in each
step, before Flame's once-a-frame `update`. The physics and the actors
already stepped so; a jet flown by `speed * dt` did not, and the same
second of play flew a different distance at 30 and at 120 frames a second.
`stepEnd` leaves the input step open after a frame with no step in it, so
a press is not closed before anything has read it. River Sortie's run, its
targets, bridges and shots are in fixed steps now.

**A body at rest costs nothing either.** `RigidBodyComponent` and
`ActorComponent` wrote their body's place onto the node every frame, and a
sleeping crate redrew every shadow as a still prop had. They write through
`placeNode` and `turnNodeTo`, which leave a node alone where it already is.

**The input step closes itself, and the pointer and swipes are input.**
`FlameInputBridge.stepEnd()` is a component that calls `endStep` once
everything has read the frame's input, which each game did by hand as the
last line of its `update`. `pointer(press:)` follows the pointer as an
`aim` and holds an action while a tap is down; `swipes(...)` turns a swipe
into one press of its direction's action.

**A still prop costs nothing, and no shadow is redrawn for it.** A node's
setters mark it changed whatever they are given, and the engine keeps its
shadow cascades and its bounds tree only while nothing changed. Every
bridged component rewrote its place every frame, twice, so one still
tanker had every shadow redrawn every frame. `Object3dComponent` and
`InstancedObject3dComponent` now write only when Flame's transform moved,
without making a vector or a quaternion to do it; `BridgePlane.to3dInto`
and `rotationInto` are the allocation-free forms. `rewriteScene` forces
the next write for a caller that moved the node itself.

**`BridgePriority` names the order a bridged frame runs in**: input, the
actors, the physics, the game's own components at Flame's default, the
camera, the sound, the clock. The bridge's components take those numbers
by default; each game had picked its own (the arcade -120 and -110).

**`ColliderRegistry` is the collider-to-component map every game with
contacts kept by hand.** An entry leaves when its component leaves the
game, and `bridge` makes a `CollisionBridge` that looks the other side up
there. The arcade's own map went.

**`Flutter3dFlameWidget` follows a rebuild.** A new camera or clear colour
handed in from above is drawn with, and a new camera is added to the
scene; both went into the view once and a rebuild changed nothing on
screen. In a debug build it says so when the game paints an opaque
background over the 3D layer, rather than leaving a screen of one colour.

**Flame's opacity and a tint reach the 3D layer.** `Object3dComponent`
is an `OpacityProvider`, so Flame's `OpacityEffect` fades every mesh under
its node, and its `tint` colours them, through `MeshNode.tint`; a model
dressed onto the node later takes them too. River Sortie's wrecks go down
charred and a fallen bridge fades under the water rather than blinking out.

**A tap lands on what the player sees.** Flame's `TapCallbacks` asks a
component whether a point is inside it on the plane the game plays on,
which under a perspective 3D camera is not where the component is drawn.
`Tap3dCallbacks` on a bridged component hears `onTap3d` when a tap falls on
the screen rectangle its node covers, through the game's projector, and a
`Taps3dComponent` in a `HasFlutter3d` game hands each tap to the nearest
such component under it, or lets it through to the rest of Flame.
`BridgeProjector.boundsOf` gives the screen rectangle of a box.

**Hitboxes can be seen where they are.** Flame's `debugMode` draws a hitbox
flat on its own canvas, nowhere near a craft drawn in perspective.
`HasFlutter3d.debugHitboxes3d` draws every bridged hitbox in the scene,
round its craft at its height, green, and red while it collides;
`addHitboxes3d` is the same for any `DebugDraw`. River Sortie shows them
with `--dart-define=RIVER_HITBOXES=true`.

**Physics and actors step in fixed steps.** `PhysicsStepComponent` and
`ActorSystemComponent` passed Flame's `dt` straight to the solver, so the
same jump reached a different height on a faster screen and a stalled frame
let a fast body step through a wall. Both now spend the frame's time in
steps of one size through `flutter3d_sim`'s `FixedStep` (a sixtieth of a
second unless given `step:`), at most five of them after a stall, and
dispatch contacts after each step. A `RigidBodyComponent` or an
`ActorComponent` given the component as its `stepper` is drawn `alpha` of
the way between its last two steps rather than jumping from one to the
next.

**`HasFlutter3d`: a Flame game owns its 3D world.** Mixed into a
`FlameGame`, it gives the game its `scene`, `device`, `camera3d`,
`renderer` and `projector`, a `clearColor` and `renderSettings()` the frame
is drawn with, and a transparent background. The game builds its world in
`onOpen3d` and uses the renderer in `onRenderer3d`, each run once, after
the game has loaded, whichever order the widget or a test opens things in.
`Flutter3dFlameWidget(game: game)` then needs nothing else: `camera` and
`buildScene` are optional for such a game, and still work for any other.
River Sortie's `main.dart` went from the scene, the camera, the lens, the
haze, the projector, the renderer and the chase camera to the game alone.

**A hidden parent hides its bridged children.** Flame does not draw the
children of a component it hides, and a child's scene node is not under its
parent's, so the child went on being drawn in 3D while the log it rode on
blinked. A bridged component now shows its node only while it and every
ancestor with `HasVisibility` are visible; `shownInFlame` answers that.

**A child under a scaled parent is scaled by both.** Its place already
carried the parent's scale, and its node was scaled by its own alone, so the
model and the hitbox disagreed about its size. The node takes Flame's
absolute scale. The same two fixes reach `InstancedObject3dComponent`.

**`ActorComponent` turns with its actor**, by the actor's yaw, and copies
the body only when the scene is authoritative. It and `RigidBodyComponent`
take a `size`, an `anchor` and an `elevation`, as `Object3dComponent` does:
a `RectangleHitbox()` on a bridged rigid body filled a size of nothing.

**`Flutter3dFlameWidget` is tested.** Its two tests were skipped as hanging
under `flutter_test`; run directly, both finish in seconds.

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
