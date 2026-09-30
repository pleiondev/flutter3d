# Keep your Flame game, get a 3D world: how I bridged Flame and flutter3d

*How flame_flutter3d puts a real 3D renderer under a Flame game, what crosses between the two engines, and a step-by-step tutorial for your own project.*

![River Sortie: a jet over a river, "+30" and "+60" over targets it hit, a helicopter going down in smoke. Jet model: Poly by Google, CC BY 3.0](https://flutter3d.pleion.dev/assets/articles/medium-flame/01_river_sortie.png)

In my [previous article](https://medium.com/@dzolotov/i-wrote-a-3d-game-engine-for-flutter-from-scratch-and-you-can-ship-a-game-with-it-today-e635f1c1b8ed) I introduced flutter3d, a 3D engine for Flutter. This one is about making it work together with Flame.

The screenshot above is River Sortie, a River Raid-style shooter you can [play in the browser](https://flutter3d.pleion.dev/river/demo/). Everything that moves in it is an ordinary Flame component with a Flame hitbox. Nothing in the game logic knows it is being drawn in 3D.

The original River Raid was designed and programmed by Carol Shaw and published by Activision for the Atari 2600 in 1982. Shaw was one of the first women to design video games professionally, and her river was generated from a pseudo-random sequence rather than stored, so the whole course came out the same on every play without the cartridge having to store it.

I built it to see whether that holds up in a real game. Flame is the 2D engine a lot of Flutter developers already write games with, and for a while it and flutter3d lived side by side without talking to each other. If you had a Flame game and wanted light, shadows, and depth, you were looking at a rewrite. flame_flutter3d is the package that joins them. Below is how it works, and then a small game built on it, from an empty project to a boat collecting buoys on a lake.

## The idea: each engine keeps its job

Both renderers stay as they are, and your game stays in Flame. Flame keeps running it: components, collisions, input, effects, the clock. flutter3d draws a 3D world under it. The bridge keeps the two in agreement about where things are, when a frame happens, and what the player pressed, and it rests on four decisions.

### 1. Two layers in one Stack

![Two engines in one Stack: Flame moves the orange square, flutter3d turns the cube, and nothing connects them yet](https://flutter3d.pleion.dev/assets/articles/medium-flame/02_two_layers.png)

`Flutter3dFlameWidget` is a Flutter `Stack`. flutter3d's `SceneSurface` is at the bottom and Flame's own `GameWidget` is on top. Flame goes on top because it needs raw input: on the web the 3D surface is a platform view that swallows pointer events, so anything that wants touches and clicks has to sit above it.

One side effect catches everyone once. `GameWidget` paints the game's background colour as an opaque rectangle, black by default, and in this Stack that rectangle covers the 3D layer completely. A game with the `HasFlutter3d` mixin returns a transparent background for you. If you use the widget without the mixin, extend `TransparentFlameGame`.

### 2. One clock

This was the decision I cared about most. Flame already has a ticker synced to vsync. A second ticker for the 3D side would drift from it sooner or later, and I don't know a reliable way to stop two timers drifting except not having two. So a bridged game runs on Flame's clock and nothing else.

![One frame of a hybrid game: Flame's clock, and everything else stepped from it](https://flutter3d.pleion.dev/assets/articles/medium-flame/03_frame_loop.png)

The widget adds a `BridgeClock` component to the game with a very high priority (`1 << 20`), so it updates after everything the game adds. Every frame goes like this:

1. Flame updates its components. The ones that step physics and actors run here, and collision callbacks fire in Flame during this pass.
2. Bridge components copy positions between the layers.
3. `BridgeClock` calls `onTick`, the cameras are synced, and a redraw of the 3D layer is requested.
4. `SceneSurface` draws the 3D frame.

The redraw in step 3 is deferred to the end of the frame, because asking Flutter to rebuild in the middle of a build throws. For a long time I assumed that cost a frame of lag and even wrote that in the docs. It doesn't. The deferred call only marks the 3D layer dirty, and the next frame starts with the tickers, so Flame's ticker updates the game before Flutter gets to the scene. Both layers always draw the same state.

A second rule follows from the first: exactly one component steps any shared simulation. If a hundred physics-backed boxes each stepped the world, the world would step a hundred times a frame.

### 3. One plane

Flame thinks in `Vector2`, flutter3d in `Vector3`, and somewhere you have to decide which axis becomes which. I put that decision in one class, `BridgePlane`, and every bridged component takes one in its constructor. When each component invents its own convention, they drift apart.

There are two planes. `BridgePlane.ground()` is a floor for top-down games: Flame's `y` becomes the scene's `z`, and height is constant. `BridgePlane.backdrop()` is a wall for side-scrollers: Flame's `y` stays `y` and depth is constant. Flame's `y` grows down the screen and the scene's grows up, so the backdrop flips it by default.

![Two cubes: the blue one is moved by the scene and read by Flame, the orange one is moved by Flame and read by the scene. The map in the corner is Flame's view of both](https://flutter3d.pleion.dev/assets/articles/medium-flame/04_transform_bridge.png)

Who writes and who reads is chosen once, when the component is created, with `SyncDirection.flameToScene` or `SyncDirection.sceneToFlame`. I didn't try to guess the direction from whatever changed last. Two systems can easily both decide the other one is reading, and that kind of guess fails silently. A physics body is written from the scene side by default, because its position belongs to the solver and Flame only reads it.

### 4. One input

`FlameInputBridge` takes the keys, drags, joystick, and buttons Flame receives and writes them into `Bindings` and `InputState` from `flutter3d_game`, the same objects a native flutter3d game reads. The bridge has no key table of its own. If a player remaps jump in your settings menu, the remap has to work in the Flame build too, and two tables that disagree look exactly like a remap that silently did nothing.

![One key, read by both engines: Flame's key handler takes the press, and the flutter3d side sees the same action held](https://flutter3d.pleion.dev/assets/articles/medium-flame/06_input_bridge.png)

On a phone this pays off. The on-screen stick is a plain Flame `JoystickComponent`, `followJoystick` feeds its deflection into the same move axis a gamepad stick would, and `bindButton` turns a Flame `HudButtonComponent` into an action. The code that moves the player never learns which it was.

## What crosses the bridge

With those four pieces in place, most of the package is components that carry one kind of thing across.

Most of the work is done by `Object3dComponent`, a Flame `PositionComponent` that owns a scene node. Position, angle, scale, visibility, opacity, and tint cross. Flame's effects reach the scene in the frame they happen, a nested component lands where Flame draws it, and `elevation` lifts a component off its plane. It also exposes `visual`, a node under it that the game can turn freely and the bridge leaves alone, which is how the jet in River Sortie banks without Flame knowing.

For physics there are two directions, and River Sortie and the arcade demo use one each. In River Sortie everything is decided by Flame: hitboxes are Flame hitboxes and `onCollisionStart` says who hit whom, while the 3D layer only draws. In the arcade demo collisions are computed by flutter3d's 3D physics, and `CollisionBridge` relays them to Flame's `CollisionCallbacks`, so a ram computed in 3D arrives in Flame as a normal `onCollisionStart`.

![A crate falls in the 3D scene; when it lands on the pad, an ordinary Flame component hears it and the pad turns green on both layers](https://flutter3d.pleion.dev/assets/articles/medium-flame/05_physics_bridge.png)

Two things don't line up there, and I chose not to paper over them. flutter3d reports a pair of colliders, while Flame wants a `PositionComponent`, so you say which component a collider belongs to with `resolveOther`. When it returns null (a level wall, say), the bridge calls nothing, because inventing a component would tell Flame it collided with something that doesn't exist for it. And Flame's callback has room for intersection points, not a normal or a depth, so the bridge passes one approximate point. The real normal and depth stay available on the flutter3d side.

For cameras, `ChaseCamera` follows a bridged component in perspective and can shake, and `CameraSyncController` keeps an orthographic camera and Flame's `Viewfinder` framed the same, or lets Flame's own camera drive a perspective one when you give it an eye offset. Beyond those there are instanced components (a hundred shots in one draw call), particles on Flame's clock, Flame sprites and text standing in the 3D scene as billboards, taps on 3D objects under a perspective camera, a Tiled level stood up in 3D, and a separate package, `flame_flutter3d_audio`, for sound that comes from where things happen.

## How River Sortie uses it

River Sortie is the biggest user of the bridge, and it shaped a lot of it. The game mixes in `HasFlutter3d`, so it owns its 3D world: scene, device, camera, and renderer are fields of the game, and it builds the river once in `onOpen3d`. It also mixes in `HasFixedStep`, so its logic runs in fixed steps and a second of play comes out the same at any frame rate. Together with a seeded river generator, the river is the same on every run.

Every tanker, helicopter, and fuel depot is an `Object3dComponent` on one `BridgePlane.ground()` laid over the water. Its Flame position is `x` across the river and `y` along it, and helicopters get an elevation that lifts them to flight height. The banks aren't hitboxes at all: the river generator answers whether any point is water or land, and the jet asks it every step. Stretches of river are built ahead of the jet and released behind it by `ChunkStreamer`. Shots are drawn as instances of one mesh, fire and smoke are 3D particles, reeds on the banks and the flash of an explosion are Flame sprites standing in the scene, and explosions are heard from where they happen.

![A bridge hit in the middle breaks in two, each half going down on its own pier. The "+500" is Flame's text, drawn over a point in the scene](https://flutter3d.pleion.dev/assets/articles/medium-flame/08_river_bridge_down.png)

The game also showed me what the bridge was missing, and most of what's listed above arrived because River Sortie needed it: the fixed step, particles, Flame sprites in the scene, and positional sound.

## Tutorial: a boat, a lake, and some buoys

We'll build a small game where you steer a boat across a lake and collect buoys. It's about 170 lines and uses every piece described above: a game that owns a 3D world, components with bodies in the scene, Flame collisions, the input bridge, a chase camera, and a fixed step.

![The finished tutorial: a boat about to collect a buoy, with Flame's score text over the 3D scene](https://flutter3d.pleion.dev/assets/articles/medium-flame/07_buoy_run.png)

### Step 1. Dependencies

Start from any Flutter project and add:

```yaml
dependencies:
  flame: ^1.38.2
  flame_flutter3d: ^0.8.4
  flutter3d: ^0.8.3
  flutter3d_game: ^0.8.0   # Bindings, the key table
  flutter3d_sim: ^0.8.1    # InputState and GameAction
```

### Step 2. Switch on Flutter GPU

flutter3d draws through Flutter GPU, and Flutter GPU is switched on per app, in the platform settings. Skip this and the app starts, opens a window, and draws no 3D at all, because it can't load its shader library.

On macOS and iOS, add to `macos/Runner/Info.plist` and `ios/Runner/Info.plist`:

```xml
<key>FLTEnableFlutterGPU</key>
<true/>
<key>FLTEnableImpeller</key>
<true/>
```

On Android, inside `<application>` in `AndroidManifest.xml`:

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableFlutterGPU"
    android:value="true" />
```

### Step 3. A game that owns a 3D world

The game is a normal `FlameGame` with four mixins. `HasFlutter3d` gives it a scene, a device, and a camera, `HasFixedStep` gives it fixed steps, and the other two are plain Flame.

```dart
class BuoyRun extends FlameGame
    with HasFlutter3d, HasFixedStep, HasCollisionDetection, KeyboardEvents {
  /// Flame's 2D world, laid flat on the water: Flame's y runs along the
  /// scene's z.
  static final BridgePlane water = BridgePlane.ground();

  late final Boat boat;
  final TextComponent score = TextComponent(
    text: 'Buoys: 0',
    position: Vector2(16, 16),
  );
  int collected = 0;

  MeshNode _mesh(Shape shape, Vector4 colour) => MeshNode(
    DeviceMesh.upload(device, shape.build()),
    engine.Material(name: 'paint', baseColor: colour, roughness: 0.5),
  );
```

The world is built in `onOpen3d`, which runs once, after both the game has loaded and the 3D device is open. Before that there is no device to upload meshes to.

```dart
  @override
  void onOpen3d() {
    clearColor.setValues(0.55, 0.75, 0.95, 1); // the sky
    scene
      ..add(
        _mesh(PlaneShape(width: 400, depth: 400), Vector4(0.15, 0.35, 0.55, 1)),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3)
          ..setLocalForward(Vector3(-0.4, -1, -0.3)),
      );

    boat = Boat(
      node: _mesh(
        CuboidShape(size: Vector3(0.8, 0.4, 1.6)),
        Vector4(0.9, 0.9, 0.85, 1),
      ),
      scene: scene,
    );
    add(boat);
    for (final (x, y) in <(double, double)>[
      (3, -6), (-4, -12), (2, -18), (-2, -24), (5, -30),
    ]) {
      add(
        Buoy(
          node: _mesh(SphereShape(radius: 0.4), Vector4(0.95, 0.35, 0.1, 1)),
          scene: scene,
          position: Vector2(x, y),
        ),
      );
    }
    add(score);
  }
```

The meshes come from code: `PlaneShape`, `CuboidShape`, and `SphereShape` are flutter3d's built-in shapes. A glTF model works the same way, as the node a component owns. The score is a regular Flame `TextComponent`, drawn on Flame's layer over the scene.

### Step 4. The widget

The game is created once and kept in the state. A game created in `build` starts over on every rebuild and never draws a frame.

```dart
void main() => runApp(const MaterialApp(home: BuoyRunScreen()));

class BuoyRunScreen extends StatefulWidget {
  const BuoyRunScreen({super.key});

  @override
  State<BuoyRunScreen> createState() => _BuoyRunScreenState();
}

class _BuoyRunScreenState extends State<BuoyRunScreen> {
  final BuoyRun _game = BuoyRun();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Flutter3dFlameWidget(game: _game));
}
```

Because the game has `HasFlutter3d`, the widget needs nothing but the game.

### Step 5. Components with a body in the scene

A buoy is an `Object3dComponent`: a Flame component with a size, an anchor, and a hitbox, plus the scene node it owns.

```dart
class Buoy extends Object3dComponent {
  Buoy({required super.node, required super.scene, super.position})
    : super(
        plane: BuoyRun.water,
        direction: SyncDirection.flameToScene,
        elevation: 0.2,
        size: Vector2.all(0.8),
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(CircleHitbox());
  }
}
```

Set `direction` explicitly. The default is `SyncDirection.sceneToFlame`, which suits a physics body whose position the solver decides, and with that default your Flame movement would be overwritten from the scene every frame. Size and hitbox are in the same units as the scene, metres here, because the plane maps Flame's units one to one.

The boat is the same kind of component, with two Flame mixins added:

```dart
class Boat extends Object3dComponent
    with CollisionCallbacks, FixedStepUpdate, HasGameReference<BuoyRun> {
  Boat({required super.node, required super.scene})
    : super(
        plane: BuoyRun.water,
        direction: SyncDirection.flameToScene,
        elevation: 0.2,
        size: Vector2(0.8, 1.6),
        anchor: Anchor.center,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }
```

### Step 6. Collisions are just Flame collisions

```dart
  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    if (other is Buoy) game.collect(other);
  }
}
```

And in the game:

```dart
  void collect(Buoy buoy) {
    buoy.removeFromParent();
    score.text = 'Buoys: ${++collected}';
  }
```

Removing the component removes its node from the scene too. Nothing in this step is 3D-specific. The collision is Flame's own, between two hitboxes on a 2D plane, exactly as it would be in a flat game.

### Step 7. Input and a fixed step

The input bridge writes Flame's key events into an `InputState`, through a `Bindings` table that maps keys to actions:

```dart
  final InputState input = InputState();
  late final FlameInputBridge inputBridge = FlameInputBridge(
    bindings: Bindings(<InputSource, GameAction>{
      InputSource.key(LogicalKeyboardKey.arrowUp.keyId): GameAction.moveForward,
      InputSource.key(LogicalKeyboardKey.arrowDown.keyId): GameAction.moveBack,
      InputSource.key(LogicalKeyboardKey.arrowLeft.keyId): GameAction.moveLeft,
      InputSource.key(LogicalKeyboardKey.arrowRight.keyId):
          GameAction.moveRight,
    }),
    inputState: input,
  );

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) => inputBridge.onGameKeyEvent(event, keysPressed);
```

The boat reads the move axis in `fixedUpdate`, which `FixedStepUpdate` calls at a fixed rate instead of once per frame, so the boat covers the same distance per second whether the screen runs at 60 Hz or 120:

```dart
  @override
  void fixedUpdate(double dt) {
    final axis = game.input.moveAxis;
    // Forward is up the screen in Flame, which is -y.
    position.add(Vector2(axis.x, -axis.y) * (6 * dt));
  }
```

To add touch controls, put a Flame `JoystickComponent` in `camera.viewport` and add `inputBridge.followJoystick(stick)` to the game. The boat code stays the same.

### Step 8. A camera that follows the boat

The last piece goes at the end of `onOpen3d`:

```dart
    add(
      ChaseCameraComponent(
        ChaseCamera(
          camera: camera3d,
          target: boat,
          offset: Vector3(0, 6, 8),
          lookOffset: Vector3(0, 0, -6),
        ),
      ),
    );
```

`camera3d` is the 3D camera `HasFlutter3d` created and added to the scene. The chase camera sits six metres up and eight behind the boat and looks six metres ahead of it.

Run it with `flutter run -d macos` (or your platform), and the arrow keys sail the boat. Each buoy it touches disappears, and the score goes up.

## When you see black instead of 3D

These are the checks I'd go through first:

- Flutter GPU isn't switched on for the platform you're running (step 2).
- The game uses the widget without `HasFlutter3d` and extends plain `FlameGame`, so Flame's opaque background covers the scene. Use `HasFlutter3d` or `TransparentFlameGame`.
- The game is created in `build` instead of once in `State`.
- The camera is inside an object. A bare `CameraNode` sits at the origin.
- An orthographic camera driven by Flame's `Viewfinder` has no zoom set. The bridge maps zoom to the camera's height as `1 / zoom`, and Flame's default zoom of 1 gives a frame one metre tall.

## What it doesn't do yet

Flame is always on top. The layers don't interleave by depth, so HUDs, maps, and sprites over the scene work, but a 3D pillar hiding a 2D sprite behind it does not. And Flame's collision callback carries no contact normal or depth, so when you need them you read them on the flutter3d side.

## Try it

- Play River Sortie in the browser: https://flutter3d.pleion.dev/river/demo/
- The showcase has one page per mechanism, each with a live scene and a step-by-step guide: https://flutter3d.pleion.dev/showcase/
- The package on pub.dev: https://pub.dev/packages/flame_flutter3d
- The source, including River Sortie and the package's minimal example: https://github.com/pleiondev/flutter3d
- A longer write-up with the arcade demo and more pitfalls, in Russian: https://habr.com/ru/articles/1087246/

If you try it with your own Flame game and something doesn't work, I'd rather hear about it than guess. Issues are open on GitHub.
