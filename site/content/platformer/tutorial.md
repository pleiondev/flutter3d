---
description: Fourteen steps from an empty project to a third-person platformer — double jump, dash, wall slides, ice and conveyors, springs, checkpoints, enemies and a follow camera.
---

# Tutorial: build a platformer

Fourteen steps. The engine underneath is the one the [shooter tutorial](/shooter/tutorial/) uses, and not one line of it changes, which is the point of doing both.

<div class="goal">
<ul>
<li>A third-person runner with a double jump, dash, wall slide, mantle, slide, long jump and ground pound</li>
<li>Ice, mud and conveyor floors; one-way platforms, springs, crumbling ledges and breakable blocks</li>
<li>Coins, checkpoints, hazards, a kill plane and patrolling enemies you can stomp</li>
<li>A follow camera that gets out of walls, kicks on landing and cuts on death</li>
<li>An animated model with eighteen clips driven by a pure function</li>
</ul>
</div>

## Set the project up {.step}

```yaml
dependencies:
  flutter: { sdk: flutter }

  # The backend; why it is the one named line is covered in the quickstart.
  flutter3d_impeller:  { path: ../flutter3d/packages/flutter3d_impeller }
  flutter3d:           { path: ../flutter3d/packages/flutter3d }
  flutter3d_game:      { path: ../flutter3d/packages/flutter3d_game }
  flutter3d_game_platformer:{ path: ../flutter3d/packages/flutter3d_game_platformer }
  flutter3d_bridge:    { path: ../flutter3d/packages/flutter3d_bridge }
  flutter3d_audio:     { path: ../flutter3d/packages/flutter3d_audio }
  flutter3d_particles: { path: ../flutter3d/packages/flutter3d_particles }
  vector_math: ^2.2.0
```

Note what is *not* there: `flutter3d_game_shooter`. A genre is a package, and this game inherits none of the other one's vocabulary.

<div class="warn">
<p>The <code>path:</code> lines assume the flutter3d checkout is a sibling of this project. None of these packages is published, so those lines are true on the machine that wrote them and nowhere else; moving the project or the checkout means fixing them. <a href="/first-project/">Your first project</a> covers this and the deployment-target trap beside it.</p>
</div>

## Bind the two keys the genre adds {.step}

`GameAction` is not an enum, and this is the reason. A platformer needs actions the engine has never heard of, and it must be able to declare them without editing the engine.

```dart
abstract final class MyActions {
  // The engine's table plus this game's own two.
}

static Bindings _bindings() => DesktopInput.defaultBindings()
  ..bind(InputSource.key(LogicalKeyboardKey.controlLeft.keyId),
         PlatformerActions.dropThrough)
  ..bind(InputSource.key(LogicalKeyboardKey.keyC.keyId),
         PlatformerActions.dropThrough);
```

The dash is already the pointer's. Drop-through is bound to control, which is where a player looks for crouch and is what it becomes when crouching exists.

<div class="why">
<p>Drop-through is its own action rather than "down plus jump", because <strong>in a third-person game with a free camera there is no down</strong>: the stick is read against the camera, and pushing it towards yourself means walking backwards.</p>
</div>

## Read the settings before opening the devices {.step}

```dart
_config = SettingsFile(appName: 'ascent').read();
_devices = DesktopInput(
  state: _input,
  bindings: _config.bindings.length > 0 ? _config.bindings : _bindings(),
);
```

Settings first, devices second. The bindings a player saved are the ones the keyboard should be reading from the **first** key press, not from the first rebind.

<div class="note">
<p><code>SettingsFile</code> comes from <code>flutter3d_ui</code>, so add that package to the pubspec by path like the rest. The catalogues used later on this page (<code>Sounds</code>, <code>Effects</code>, <code>RunnerClips</code>) are exported by no package at all: they are the application's own definitions, and the demo's live in <code>apps/flutter3d_demo_platformer/lib/src/</code> as <code>sounds.dart</code>, <code>effects.dart</code> and <code>runner_clips.dart</code>.</p>
</div>

## Open the renderer, and keep the scene non-null {.step}

```dart
Scene _scene = Scene();   // empty until the level arrives, and never null

Future<void> _openGraphics() async {
  final device = await GpuRenderBackend.create();
  _device = device;

  setState(() {
    _renderer = Renderer.create(device: device);
    // One pool, one draw call, added once. Everything this game throws into
    // the air goes through it.
    _renderer?.addContributor(ParticleContributor(_particles));
  });

  _ticker = createTicker(_onTick)..start();
  unawaited(_openAudio());
  unawaited(_loadLevel());
}
```

The renderer must build its frame targets before anything else has taken device memory; the failure mode behind that, and the one line worth copying verbatim, are in the [first-scene tutorial](/core/tutorial/#a-scene-that-is-never-null).

## Author a level with the genre's floors {.step}

```json
{
  "version": 1,
  "name": "Ascent",
  "fogColor": [0.05, 0.07, 0.12],
  "fogDensity": 0.004,
  "materials": {
    "moss":  { "roughness": 1.0, "albedo": "assets/textures/moss_albedo.png",
               "normal": "assets/textures/moss_normal.png",
               "orm": "assets/textures/moss_orm.png", "texelsPerMetre": 0.5 },
    "ice":   { "roughness": 1.0, "albedo": "assets/textures/ice_albedo.png",
               "normal": "assets/textures/ice_normal.png",
               "orm": "assets/textures/ice_orm.png", "texelsPerMetre": 0.4 }
  },
  "brushes": [
    {"at": [0, -0.5, -2.5],  "size": [120, 1, 55], "material": "moss"},
    {"at": [0, -0.5, 124.5], "size": [120, 1, 7],  "material": "ice",
     "surface": "ice"}
  ],
  "entities": [
    {"type": "player_spawn", "at": [0, 0, -20], "yaw": 0},
    {"type": "collectible",  "at": [4, 1, 8],   "what": "coin", "howMany": 1},
    {"type": "checkpoint",   "at": [0, 0, 40],  "order": 1},
    {"type": "spring",       "at": [12, 0.2, 52], "speed": 16.0},
    {"type": "oneway",       "at": [6, 4, 60],  "size": [4, 0.3, 4]},
    {"type": "conveyor",     "at": [0, 0.2, 70], "size": [8, 0.4, 4],
     "velocity": [0, 0, 4]},
    {"type": "crumbling",    "at": [10, 6, 84], "delay": 0.4, "gone": 2.5},
    {"type": "breakable",    "at": [0, 3, 96]},
    {"type": "hazard",       "at": [-8, 0.5, 30], "size": [6, 1, 6],
     "damagePerSecond": 40.0},
    {"type": "enemy",        "at": [3, 0, 45],  "route": [[3,0,45],[9,0,45]],
     "speed": 2.2},
    {"type": "exit",         "at": [0, 1, 200], "size": [6, 4, 1]}
  ]
}
```

The `surface` word on a brush is the whole of the ice mechanic in the document. What it means lives in `Surfaces.common()`, in code, where it belongs.

<div class="note">
<p>The textures, the level and the model this page names are not shipped as a starter kit; the real ones live in the demo at <code>apps/flutter3d_demo_platformer/assets/</code>, including <code>textures/moss_*.png</code> and <code>ice_*.png</code>, <code>levels/ascent.json</code> and the runner model <code>models/penguin.glb</code>. Point your paths there, or at your own files. The box-runner fallback below means the game runs before any of them exist.</p>
</div>

## Load the level, and spawn into it {.step}

```dart
Future<void> _loadLevel() async {
  final kinds = platformerRegistry();

  final loaded = await LevelLoader().load(
    'assets/levels/ascent.json',
    device: _device!,
    registry: kinds,
    rules: platformerRules(),
  );

  final dynamics = Dynamics(world: loaded.collision);
  // The crate kind is told where bodies go *after* there is a world, exactly
  // as the shooter tells its monster kind where the bestiary is.
  (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;

  final actors = ActorSystem(world: loaded.collision);
  final mechanisms = MechanismWorld(loaded.collision);
  final fixtures = FixtureVisuals(
    loaded.scene, loaded,
    appearance: const PlatformerLooks(),
    device: _device!,
  )..bindLights();

  loaded.level.spawnInto(
    SpawnContext(
      world: loaded.collision,
      actors: actors,
      mechanisms: mechanisms,
      onFixture: fixtures.add,
    ),
    registry: kinds,
  );
  // ...
}
```

## Build the runner {.step}

```dart
// The authored point is where the feet go; the body is a box about its middle.
final start = loaded.level.playerStart?.position ?? Vector3.zero();

final runner = Runner(
  body: CharacterController(
    world: loaded.collision,
    position: start + Vector3(0.0, 0.9, 0.0),
  ),
  // What this game's floors are made of. The names live in the level
  // document, on the brushes, beside the material that paints them.
  surfaces: Surfaces.common(),
  tuning: const RunnerTuning(
    jumpSpeed: 9.5,
    airJumpSpeed: 8.2,     // weaker: a double jump is a recovery, not a stair
    airJumps: 1,
    jumpCut: 0.45,         // variable jump height — the one control that matters
    coyoteTime: 0.12,
    jumpBufferTime: 0.12,
    dashSpeed: 18.0,
    dashCooldown: 0.55,
    wallJumpUp: 9.0,
    wallJumpPush: 7.5,     // the push is what stops a chimney becoming a ladder
    mantleHigh: 1.5,       // under a jump's 1.88 m, on purpose
    stompBounceHeld: 11.0, // above a standing jump, so stomps chain upwards
  ),
);
```

<div class="why">
<p><code>jumpCut</code> is the single control that separates a platformer from a shooter that happens to have gaps in the floor. The height of every jump has to be a decision the player makes, not one the tuning made for them.</p>
</div>

## The simulation, and the camera that owns "forward" {.step}

```dart
_sim = PlatformerSimulation(
  runner: runner,
  collision: loaded.collision,
  input: _input,
  startAt: start,              // the feet, as authored — see Runner.reviveAt
  mechanisms: mechanisms,
  dynamics: dynamics,
  actors: actors,
  levelNext: loaded.level.next,
  killPlane: -20.0,
);
_followCamera = FollowCamera(world: loaded.collision);
```

```dart
void _step(double dt) {
  // The camera owns "forward", and the simulation takes it as a number.
  _sim!.cameraYaw = _followCamera!.yaw;
  _sim!.step(dt);

  if (_sim!.deaths != _deathsSeen) {
    _deathsSeen = _sim!.deaths;
    // A cut instead of a chase.
    _followCamera!.cut();
    _drawnAt.jumpTo(runner.body.position);
  } else {
    _drawnAt.push(runner.body.position);
  }
  _drawnYaw.push(runner.yaw);
}
```

<div class="warn">
<p>Pass <code>ActorSystem</code> to the simulation, or there are no enemies. It was built by the application from the day the package existed and never stepped — the system was there, the brains were there, and nothing called them.</p>
</div>

## Run the loop {.step}

```dart
void _onTick(Duration now) {
  final dt = _lastTick == Duration.zero
      ? 1.0 / 60.0
      : (now - _lastTick).inMicroseconds / 1e6;
  _lastTick = now;
  _elapsed += dt;

  // Paused whenever the mouse is not ours: a game that keeps running behind a
  // menu is a game that kills the player while they are reading it.
  _loop.paused = !_devices.isCaptured || _sim == null;
  _loop.advance(dt.clamp(0.0, 0.25));

  _particles.advance(dt);
  _animateRunner(dt);
  _placeCamera(dt);
  _fixtures?.sync(_elapsed);
  _burnLamps();
  if (mounted) setState(() {});
}
```

Simulation in `_step`, presentation in `_onTick`. Nothing in `_step` draws and nothing in `_onTick` decides.

## Place the camera, and pose the runner {.step}

```dart
void _placeCamera(double dt) {
  final camera = _followCamera!;
  camera.look(_input.lookDelta);

  _drawnAt.read(_loop.alpha, _scratch);   // interpolated, not the last step
  camera.follow(_scratch, dt);

  // Squash, stretch, lean, and the flip a double jump turns. Built from what
  // the runner did this step and applied here, because this is what draws.
  _pose.advance(runner, dt);
  final scale = _pose.scale;

  node
    ..setPosition(_scratch.x, _scratch.y - _runnerDrop, _scratch.z)
    ..setScale(scale.x, scale.y, scale.z)
    ..setRotation(
      Quaternion.axisAngle(Vector3(0, 1, 0),
              _drawnYaw.read(_loop.alpha) + _runnerFacing + _pose.spin) *
          Quaternion.axisAngle(Vector3(1, 0, 0), _pose.lean) *
          Quaternion.axisAngle(Vector3(0, 0, 1), _pose.roll),
    );

  // Speed widens the view a little, the cheapest way to make fast feel fast.
  // Read off the drawn body so it moves at the display's rate.
  final speed = runner.body.velocity.length;
  if (speed > 9.0) camera.widen(((speed - 9.0) / 14.0).clamp(0.0, 0.12));

  _camera
    ..setPositionFrom(camera.eye)
    ..lookAt(camera.target)
    ..projection = _lens.copyWith(fovYRadians: _lens.fovYRadians + camera.extraFov);

  // Along the camera's own forward rather than through a yaw: aimAt reads an
  // angle as a first-person camera's, and this one is not.
  _ears.aimAlong(camera.eye, camera.target - camera.eye);
  _audio.update(_ears);
}
```

`_runnerDrop` is one number reconciling two conventions: a body is a box about its middle, a model of somebody standing has its feet at the origin.

```dart
_runnerDrop = runner.body.halfExtents.y - asset.localBounds.min.y;
```

## Dress the runner, and let the clips drive themselves {.step}

A box now, the model when it arrives — the game is playable either way, and a missing asset should not be the difference between playing and staring at an error.

```dart
SceneNode _boxRunner(GraphicsDevice device, Scene scene, Runner runner) {
  final box = MeshNode(
    SharedMeshes(device).box(runner.body.halfExtents * 2.0),
    Material(name: 'runner', baseColor: Vector4(0.90, 0.42, 0.28, 1.0),
             lighting: LightingModel.pbr)..roughness = 0.5,
    name: 'runner box',
  );
  scene.add(box);
  return box;
}

Future<void> _dressRunner(GraphicsDevice device, Scene scene, Runner runner) async {
  final document = await decodeModelInIsolate(
    ModelLoadRequest(source: const BundleAssetSource('assets/models/hero.glb')),
  );
  final asset = await ModelAsset.fromDocument(document,
      device: device,
      name: 'hero');
  if (!mounted) return;

  final instance = asset.instantiate(scene, name: 'runner');
  setState(() {
    _runnerNode = instance.root;
    _runnerAnimation = instance.player;      // null when the file has no clips
    _runnerDrop = runner.body.halfExtents.y - asset.localBounds.min.y;
  });
  scene.remove(box);
}
```

Which clip to play is a pure function of what the runner is doing, which makes it testable without a device:

```dart
void _animateRunner(double dt) {
  final player = _runnerAnimation;
  if (player == null) return;

  final wanted = RunnerClips.forRunner(runner);   // pure, and tested as one
  if (wanted != _clip) {
    // A short fade, and shorter still into a jump: a quarter of a second of
    // blending into a take-off is a quarter of a second of the runner still
    // standing there while the body is already in the air.
    player.crossFadeToNamed(wanted,
        duration: wanted == RunnerClips.jump ? 0.06 : 0.14);
    _clip = wanted;
  }

  final speed = math.sqrt(runner.body.velocity.x * runner.body.velocity.x +
      runner.body.velocity.z * runner.body.velocity.z);
  player
    ..speed = RunnerClips.rateFor(wanted, speed)
    ..update(dt);
}
```

<div class="note">
<p>Once a frame, not once a step. The simulation runs at 60 Hz and the animation should run at whatever the display does.</p>
</div>

## Turn the step's events into sound and light {.step}

```dart
void _hear(PlatformerSimulation sim, Runner runner) {
  final at = runner.position;
  final camera = _followCamera;

  if (runner.jumpedThisStep) {
    _audio.play(runner.airJumpsLeft < 1 ? Sounds.airJump : Sounds.jump, at);
  }
  if (runner.dashedThisStep) {
    _audio.play(Sounds.dash, at);
    _particles.burst(Effects.dash, at);
    camera?.widen(0.1);
  }
  if (runner.wallJumpedThisStep) _particles.burst(Effects.dust, at);

  for (final taken in sim.takenThisStep) {
    _audio.play(Sounds.coin, taken.origin);
    _particles.burst(Effects.coin, taken.origin);
  }
  if (sim.reachedCheckpointThisStep) {
    _audio.play(Sounds.checkpoint, at);
    _particles.burst(Effects.checkpoint, at, direction: _up);
  }
  if (sim.deaths != _deathsSeen) {
    _audio.play(Sounds.death, at);
    _particles.burst(Effects.death, at);
    camera?.shake(0.5, seconds: 0.4);
  }

  // Everything the level's own machinery did this step.
  for (final Mechanism m in sim.mechanisms?.all ?? const <Mechanism>[]) {
    if (m is Spring && m.firedThisStep) {
      _particles.burst(Effects.spring, m.origin, direction: _up);
    }
    if (m is Crumbling && m.crumbledThisStep) {
      _particles.burst(Effects.crumble, m.origin);
    }
    if (m is Breakable && m.brokeThisStep) {
      _particles.burst(Effects.slam, m.origin);
    }
  }

  // Landing reports how hard, which is something only the simulation knows.
  if (runner.landedThisStep) {
    _audio.play(Sounds.land, at);
    _feelLanding(runner.landingSpeed, pounded: runner.poundedThisStep);
    if (runner.poundedThisStep) {
      _particles.burst(Effects.slam, at);
    } else if (runner.landingSpeed > 6.0) {
      _particles.burst(Effects.dust, at);
    }
  }
}

void _feelLanding(double speed, {required bool pounded}) {
  // Below walking pace nothing happens: a camera that dips every time the
  // player steps off a kerb is a camera nobody can look at.
  if (speed < 6.0 && !pounded) return;
  final hardness = (speed / 20.0).clamp(0.0, 1.0);
  _followCamera?.kick(Vector3(0.0, -0.18 * hardness, 0.0));
  if (pounded) _followCamera?.shake(0.22, seconds: 0.3);
}
```

Keep every lamp alight by restating its rate, rather than starting it once:

```dart
void _burnLamps() {
  for (final MapEntry<LightFixture, TorchFire> lamp in _fixtures!.flames.entries) {
    final fire = lamp.value;
    _particles.emit(fire, Effects.flame, fire.originInto(_flameAt),
        perSecond: 34.0 * lamp.key.brightness, direction: _up);
  }
}
```

A rate that is not restated goes out, which is how a lamp that was destroyed stops smoking without anybody telling it to.

## Draw it, with three cascades {.step}

```dart
final frame = renderer.render(
  width: (constraints.maxWidth * dpr).round().clamp(1, 8192),
  height: (constraints.maxHeight * dpr).round().clamp(1, 8192),
  scene: scene,
  views: <RenderView>[view],
  settings: RenderSettings(
    fog: FogSettings(
      color: loaded?.level.fogColor ?? Vector3(0.05, 0.07, 0.12),
      density: loaded?.level.fogDensity ?? 0.0,
    ),
    shadows: const ShadowSettings(cascades: 3, resolution: 1024),
  ),
);
return renderer.device.present(frame.frame);
```

<div class="why">
<p>This level is 120 m by 260 m, and one shadow map over that spends its resolution on ground the camera cannot see. Three cascades put the nearest one around the camera instead; the numbers are under <a href="/core/rendering/#cascades">cascades</a>.</p>
<p>1024 instead of the default 2048, because the atlas is <code>resolution × cascades</code> wide: three cascades at the default would be a six-thousand-pixel HDR texture and a hundred megabytes, on the machine that already had to be taught not to allocate its frame targets late. Three tiles of 1024 cover about forty metres each, four centimetres of world per texel against the old fourteen.</p>
</div>

## Test the whole thing without a device {.step}

```dart
test('the ascent can be run to its exit', () {
  final game = loadAscent();     // no renderer anywhere in here

  for (var i = 0; i < 3600; i++) {
    game.input.press(GameAction.moveForward);
    if (i % 90 == 0) game.input.press(GameAction.jump);
    game.loop.advance(1 / 60);
    game.input.endStep();
  }

  expect(game.sim.state, RunState.finished);
  expect(game.runner.purse['coin'], greaterThan(0));
});
```

And draw one frame in a test through the software backend, because there are failures a simulation test cannot see:

```dart
test('a frame renders', () {
  final device = CpuRenderBackend();      // flutter3d_cpu, a dev dependency
  final renderer = Renderer.create(device: device, /* ... */);
  final frame = renderer.render(width: 320, height: 180, scene: scene,
      views: <RenderView>[view], settings: const RenderSettings());
  expect(frame.drawCalls, greaterThan(0));
});
```

<div class="why">
<p>Three bugs shipped that every simulation test passed and a single rendered frame would have caught. That is why <code>flutter3d_cpu</code> is a dev dependency of the games rather than a curiosity.</p>
</div>

## Where to go from here

- [What a platformer adds](/platformer/): the reference for every type used here
- [Shooter tutorial](/shooter/tutorial/): the same core, a completely different game
- [Simulation layer](/core/simulation/): the machinery both share
- [Testing](/reference/testing/): how the tests are written, and why
