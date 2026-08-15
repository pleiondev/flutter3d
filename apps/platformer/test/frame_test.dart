/// The game, drawn. Not the simulation — the picture.
///
///     flutter test test/frame_test.dart
///
/// **Why this file exists.** Three bugs shipped in one afternoon that every one
/// of the seventy-eight tests passed: every coin in the level was invisible,
/// nothing made a sound when one was taken, and a locked gate could never be
/// opened. All three lived in the seam between a simulation that was right and
/// a picture that was wrong, and nothing looked at the picture.
///
/// So this renders one. `CpuDevice` is a `GraphicsDevice` with no GPU under it
/// and `readPixels` gives the frame back as bytes — the arrangement
/// `packages/flutter3d_cpu/test/engine_parity_test.dart` already uses. What is
/// assembled here is the real thing: the shipped level document, the real
/// registry, the real `FixtureVisuals` with the game's own `PlatformerLooks`,
/// and the real `PlatformerSimulation` stepping at sixty hertz. The only piece
/// left out is the runner's model, which loads through an isolate and is a box
/// in the first seconds of the real game anyway.
///
/// Assertions are on counted pixels rather than on a golden image, deliberately.
/// A golden of a scene this size fails on every brush anybody moves and teaches
/// nothing; "there is gold on the screen where a coin is" fails only when a coin
/// stops being drawn, which is the bug.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_platformer/flutter3d_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platformer/src/looks.dart';
import 'package:platformer/src/runner_looks.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 160;
const double _dt = 1.0 / 60.0;

/// Everything `main.dart` assembles, including the half that draws.
final class _Shown {
  _Shown._(this.device, this.renderer, this.level, this.scene, this.world,
      this.mechanisms, this.dynamics, this.fixtures, this.runner, this.sim,
      this.runnerNode, this.camera, this.actors);

  static Future<_Shown> build() async {
    final device = CpuDevice(
      width: _width,
      height: _height,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
    );
    TextureHandle texel(List<int> rgba) => device.createTextureFromPixels(
          width: 1,
          height: 1,
          format: TextureFormat.r8g8b8a8UNormInt,
          pixels: ByteData.sublistView(Uint8List.fromList(rgba)),
        )!;
    final renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel(<int>[255, 255, 255, 255]),
      fallbackNormal: texel(<int>[128, 128, 255, 255]),
    );

    // Loaded the way the game loads it, through the bridge: the same brush
    // geometry, the same textures, the same validation. A test that built its
    // own scene would be a test of a scene nobody ships.
    final kinds = platformerRegistry();
    final loaded = await LevelLoader().load(
      'assets/levels/ascent.json',
      device: device,
      registry: kinds,
      rules: platformerRules(),
    );

    final world = loaded.collision;
    final scene = loaded.scene;
    final level = loaded.level;
    final dynamics = Dynamics(world: world);
    (kinds[PlatformerEntities.crate] as CrateKind?)?.dynamics = dynamics;

    final mechanisms = MechanismWorld(world);
    final actors = ActorSystem(world: world);
    final fixtures = FixtureVisuals(
      scene,
      loaded,
      appearance: const PlatformerLooks(),
      device: device,
    )..bindLights();

    level.spawnInto(
      SpawnContext(
        world: world,
        actors: actors,
        mechanisms: mechanisms,
        onFixture: fixtures.add,
      ),
      registry: kinds,
    );

    final start = level.playerStart?.position ?? Vector3.zero();
    final runner = Runner(
      body: CharacterController(
        world: world,
        position: start + Vector3(0.0, 0.9, 0.0),
      ),
      surfaces: Surfaces.common(),
    );
    // A box, which is what the real game draws until the model arrives.
    final runnerNode = MeshNode(
      SharedMeshes(device).box(runner.body.halfExtents * 2.0),
      engine.Material(
        name: 'runner',
        baseColor: Vector4(0.90, 0.42, 0.28, 1.0),
        lighting: LightingModel.pbr,
      )..roughness = 0.5,
      name: 'runner box',
    );
    scene.add(runnerNode);

    final sim = PlatformerSimulation(
      runner: runner,
      collision: world,
      input: InputState(),
      startAt: start,
      mechanisms: mechanisms,
      dynamics: dynamics,
      actors: actors,
    );

    return _Shown._(device, renderer, level, scene, world, mechanisms, dynamics,
        fixtures, runner, sim, runnerNode, CameraNode(), actors);
  }

  final CpuDevice device;
  final Renderer renderer;
  final Level level;
  final Scene scene;
  final CollisionWorld world;
  final MechanismWorld mechanisms;
  final Dynamics dynamics;
  final FixtureVisuals fixtures;
  final Runner runner;
  final PlatformerSimulation sim;
  final MeshNode runnerNode;
  final CameraNode camera;
  final ActorSystem actors;

  final InputState _input = InputState();
  double _elapsed = 0.0;
  bool _forward = false;

  void step({bool forward = false}) {
    _input.beginStep();
    if (forward != _forward) {
      forward
          ? _input.press(GameAction.moveForward)
          : _input.release(GameAction.moveForward);
      _forward = forward;
    }
    // The simulation reads the app's input object, not this one, so hand it
    // over the same way `main.dart` does: through the field it was built with.
    sim.input
      ..beginStep()
      ..press(GameAction.moveForward);
    if (!forward) sim.input.release(GameAction.moveForward);
    sim.step(_dt);
    sim.input.endStep();
    _input.endStep();
    pose.advance(runner, _dt);
    _elapsed += _dt;
  }

  void walk(int steps, {bool Function(_Shown it)? until}) {
    for (var i = 0; i < steps; i++) {
      if (until != null && until(this)) return;
      step(forward: true);
    }
  }

  void wait(int steps) {
    for (var i = 0; i < steps; i++) {
      step();
    }
  }

  /// Points the camera at [at] from [from], the way `_placeCamera` does.
  void look({required Vector3 from, required Vector3 at}) {
    camera
      ..setPosition(from.x, from.y, from.z)
      ..lookAt(at);
  }

  /// Draws frames until [enough] is happy with one, or gives up.
  ///
  /// The fixtures load their models asynchronously — a coin is a GLB, and
  /// `FixtureVisuals` starts the read and returns — so the first frame of a
  /// level is drawn before its coins exist, exactly as it is in the game. A
  /// fixed delay here was the first attempt and it was wrong the way fixed
  /// delays always are: fine alone, flaky under a full `ci.sh` where the
  /// machine has eleven other suites to run. This waits for the thing itself.
  Future<Uint8List> drawUntil(bool Function(Uint8List frame) enough,
      {int attempts = 120}) async {
    var frame = await draw();
    for (var i = 0; i < attempts && !enough(frame); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      frame = await draw();
    }
    return frame;
  }

  /// How the runner is posed, as `main.dart` poses it.
  final RunnerLooks pose = RunnerLooks();

  /// Draws a frame and gives back its pixels, RGBA.
  ///
  /// [hiding] takes a node out of the picture *after* the fixtures have been
  /// synchronised, which is the only moment it stays hidden: `sync` makes every
  /// fixture that is not spent visible again, so hiding one before the call is
  /// hiding it from nobody. Found the way these things are — by an A/B that
  /// reported the two frames identical.
  Future<Uint8List> draw({String? hiding}) async {
    fixtures.sync(_elapsed);
    final p = runner.position;
    final scale = pose.scale;
    runnerNode
      ..setPosition(p.x, p.y, p.z)
      ..setScale(scale.x, scale.y, scale.z);
    if (hiding != null) {
      for (final MeshNode piece in scene.meshes) {
        if (piece.name == hiding) piece.visible = false;
      }
    }
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: const RenderSettings(),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }
}

/// How many pixels read as gold: bright, warm, and green two thirds of the way
/// to red.
///
/// A coin is `baseColor` (0.98, 0.80, 0.22) — green is 0.82 of red. The first
/// draft of this only asked for "more red than blue", which is also true of the
/// runner's orange box (0.90, 0.42, 0.28), and the runner walking through the
/// shot counted as eight thousand coins. Green against red is what separates
/// them, and it is why the ratio is here rather than a brightness threshold.
int _goldPixels(Uint8List rgba) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    if (r > 110 && g > r * 0.62 && g < r * 0.95 && b < g * 0.6) count++;
  }
  return count;
}

/// How many pixels differ between two frames of the same size.
int _differences(Uint8List a, Uint8List b, {int threshold = 12}) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > threshold ||
        (a[i + 1] - b[i + 1]).abs() > threshold ||
        (a[i + 2] - b[i + 2]).abs() > threshold) {
      count++;
    }
  }
  return count;
}

void main() {
  // `LevelLoader` reads through `rootBundle`, which needs the binding up.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a coin is drawn until it is taken, and then it is not', () async {
    // **The two bugs this is here for, and they fail differently.** Every coin
    // in the level was invisible from the first frame, because "has it finished
    // shrinking" asked of a coin that was never taken — `sinceTaken` is
    // infinity — says yes. And a coin that is drawn for ever is as wrong as one
    // that is never drawn; the simulation cannot see either, and did not.
    //
    // Mutations: drop `mechanism.isTaken` from `PlatformerLooks.isSpent` (the
    // first frame goes empty), or make `isSpent` return false (the second frame
    // stops changing).
    final it = await _Shown.build();
    final coin = it.mechanisms['coin one']!;

    // Behind the camera, so the runner's own box is not in either frame: what
    // is under test is the coin.
    it.runner.body.teleport(Vector3(0.0, 0.9, -26.0));
    it.look(from: Vector3(0.0, 1.2, -19.5), at: coin.origin!);

    final drawn =
        await it.drawUntil((Uint8List f) => _goldPixels(f) > 20);
    final gold = _goldPixels(drawn);
    expect(gold, greaterThan(20),
        reason: 'a coin three and a half metres in front of the camera never '
            'appeared, in two and a half seconds of frames');

    // Taken through the world, the way walking over it does it.
    expect(
      coin.activate(it.mechanisms.activationBy(it.runner.body.collider)),
      isA<Activated>(),
    );
    it.wait(30); // Half a second; the shrink lasts three hundred milliseconds.

    final gone = await it.draw();
    expect(_goldPixels(gone), lessThan(gold ~/ 4),
        reason: 'the coin is still on screen after it was collected');
    expect(_differences(drawn, gone), greaterThan(20),
        reason: 'the two frames are the same picture');
  });

  test('the runner is drawn, standing on the floor', () async {
    // Not "is the runner at y = 0.9" — the simulation already says that, and
    // said it while the model was buried in the floor and while it was a box
    // nobody had swapped. This asks the frame.
    //
    // Mutation: `runnerNode.visible = false`, or draw it at the body's feet
    // instead of its centre.
    final it = await _Shown.build();
    it.wait(30);
    final at = it.runner.position;
    it.look(from: at + Vector3(0.0, 1.6, -5.0), at: at);

    final withRunner = await it.draw();
    it.runnerNode.visible = false;
    final without = await it.draw();

    expect(_differences(withRunner, without), greaterThan(200),
        reason: 'hiding the runner changed nothing, so it was not drawn');
  });

  test('a one-way platform is drawn, like anything else the level places', () {
    // A new `EntityKind` that forgets `context.reveal` spawns a collider the
    // player walks into and cannot see, and every simulation test passes. This
    // is stage E1's assertion on the picture, per the rule the harness was
    // built for.
    //
    // Mutation: drop the `context.reveal(...)` call from `OneWayKind.spawn`.
    return _Shown.build().then((_Shown it) async {
      final gantry = it.level.entities
          .firstWhere((EntityDef e) => e.name == 'the gantry 1');
      it.runner.body.teleport(gantry.position + Vector3(0.0, 6.0, 0.0));
      it.look(
        from: gantry.position + Vector3(0.0, 1.6, -7.0),
        at: gantry.position,
      );

      final drawn = await it.draw();
      final without = await it.draw(hiding: 'the gantry 1');

      expect(_differences(drawn, without), greaterThan(150),
          reason: 'hiding the gantry changed nothing, so it was never drawn');
    });
  });

  test('a rope is drawn where it swings, not where it was authored', () {
    // Stage E2's assertion on the picture. A `Climbable` moves its own collider
    // and `FixtureVisuals` follows colliders, so a rope that swings in the
    // simulation and hangs still on the screen is a rope whose fixture was
    // placed from the document instead — which is exactly what happens if the
    // reveal passes a position rather than the collider.
    //
    // Mutation: hand `context.reveal` no collider in `ClimbableKind.spawn`.
    return _Shown.build().then((_Shown it) async {
      final rope = it.mechanisms['the rope']!;
      it.runner.body.teleport(Vector3(52.0, 20.0, 90.0));
      it.look(from: Vector3(52.0, 7.0, 96.0), at: rope.origin!);

      final atRest = await it.draw();
      // A quarter of the swing's period, which is where a pendulum is furthest
      // from the middle.
      it.wait(40);
      final swung = await it.draw();

      expect(_differences(atRest, swung), greaterThan(120),
          reason: 'the rope moved in the simulation and not on the screen');
    });
  });

  test('the pose reaches the screen, and a hard landing shows', () {
    // Stage E3's assertion on the picture. `RunnerLooks` is tested on its own
    // numbers in `runner_looks_test.dart`; what this asks is whether those
    // numbers ever arrive at a pixel, which is exactly the seam all three
    // shipped bugs lived in.
    //
    // Mutation: drop the `setScale` from where the runner is drawn.
    return _Shown.build().then((_Shown it) async {
      it.runner.body.teleport(Vector3(0.0, 0.9, -22.0));
      it.wait(40);
      final at = it.runner.position.clone();
      it.look(from: at + Vector3(0.0, 1.2, -4.0), at: at);
      final standing = await it.draw();

      // Dropped from a height, and drawn on the step it lands.
      it.runner.body.teleport(Vector3(0.0, 20.0, -22.0));
      for (var i = 0; i < 200; i++) {
        it.step();
        if (it.runner.landedThisStep) break;
      }
      final landed = await it.draw();

      expect(_differences(standing, landed), greaterThan(80),
          reason: 'the runner is drawn the same standing and squashed');
    });
  });

  test('a guard is drawn, and is gone once it is stomped', () {
    // Stage E4's assertion on the picture, and it covers the half nobody thinks
    // to check: an enemy that dies in the simulation and stays on the screen is
    // a corpse the player keeps trying to jump on.
    //
    // Mutation: never hide the fixture of a dead actor — the frames match and
    // this fails.
    return _Shown.build().then((_Shown it) async {
      final guard = it.actors.actors.first;
      final over = guard.position!;
      it.look(from: over + Vector3(0.0, 1.4, -5.0), at: over);

      final alive = await it.draw();
      expect(guard.isAlive, isTrue);

      it.runner.body.teleport(over + Vector3(0.0, 1.0, 0.0));
      for (var i = 0; i < 200 && guard.isAlive; i++) {
        it.step();
      }
      expect(guard.isAlive, isFalse, reason: 'it was never stomped');

      // Out of the way, so what changes is the guard and not the runner.
      it.runner.body.teleport(over + Vector3(0.0, 1.0, -14.0));
      final gone = await it.draw();

      expect(_differences(alive, gone), greaterThan(60),
          reason: 'the dead guard is still on the screen');
    });
  });

  test('the level is drawn at all', () async {
    // The cheapest guard in the file, and the one that would have caught the
    // renderer failing to allocate its targets: a frame that is one flat colour
    // everywhere is a frame nothing reached.
    final it = await _Shown.build();
    final at = it.runner.position;
    it.look(from: at + Vector3(0.0, 3.0, -8.0), at: at);

    final pixels = await it.draw();
    final grid = parityGrid(pixels, _width, _height);
    final low = grid.reduce((int a, int b) => a < b ? a : b);
    final high = grid.reduce((int a, int b) => a > b ? a : b);

    expect(high - low, greaterThan(20),
        reason: 'every cell of the frame is the same brightness');
  });
}
