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
import 'package:flutter3d/parity_scene.dart';
import 'package:flutter3d_bridge/flutter3d_bridge.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/runner_looks.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 240;
const int _height = 160;
const double _dt = 1.0 / 60.0;

/// Everything `main.dart` assembles, including the half that draws.
final class _Shown {
  _Shown._(
    this.device,
    this.renderer,
    this.level,
    this.scene,
    this.world,
    this.staged,
    this.fixtures,
    this.runnerNode,
    this.camera,
    this._input,
  );

  static Future<_Shown> build({
    String level = 'assets/levels/ascent.json',
  }) async {
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

    // Loaded and dressed by the game's own `openLevel`, not by a copy of it
    // here. The four lines this replaces were right; the crypt's equivalent
    // four were not — its copy had lost `bindLights()` — and a frame test that
    // assembles its own picture is a frame test of a picture nobody ships.
    final (:kinds, :loaded, :fixtures) = await openLevel(level, device: device);

    final world = loaded.collision;
    final scene = loaded.scene;
    final document = loaded.level;

    // Assembled by `stage`, which is the call `main.dart` makes on the line
    // after this one. The forty lines that used to be here were the game's
    // assembly copied by hand, and the copy is what a frame test cannot afford
    // to be: the picture is only worth checking if it is the picture of the
    // game.
    final input = InputState();
    final staged = stage(
      document,
      world,
      input: input,
      registry: kinds,
      onFixture: fixtures.add,
    );
    final runner = staged.runner;

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

    return _Shown._(
      device,
      renderer,
      document,
      scene,
      world,
      staged,
      fixtures,
      runnerNode,
      CameraNode(),
      input,
    );
  }

  final CpuDevice device;
  final Renderer renderer;
  final Level level;
  final Scene scene;
  final CollisionWorld world;
  final Staged staged;
  final FixtureVisuals fixtures;
  final MeshNode runnerNode;
  final CameraNode camera;

  MechanismWorld get mechanisms => staged.mechanisms;
  Dynamics get dynamics => staged.dynamics;
  ActorSystem get actors => staged.actors;
  Runner get runner => staged.runner;
  PlatformerSimulation get sim => staged.sim;

  final InputState _input;
  double _elapsed = 0.0;
  bool _forward = false;

  void step({bool forward = false, bool pound = false}) {
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
    if (pound) sim.input.press(PlatformerActions.dropThrough);
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
  Future<Uint8List> drawUntil(
    bool Function(Uint8List frame) enough, {
    int attempts = 120,
  }) async {
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
  /// Draws without asking the appearance anything, so a test can force a node
  /// visible and see what difference that node makes on its own.
  Future<Uint8List> drawAsIs() async {
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

  /// The drawn piece nearest [at], which is how a fixture's node is found
  /// without the bridge having to hand out its bookkeeping.
  MeshNode? pieceNear(Vector3 at, {double within = 3.0}) {
    MeshNode? best;
    var nearest = within;
    for (final MeshNode piece in scene.meshes) {
      final away = (piece.readWorldPosition() - at).length;
      if (away < nearest) {
        nearest = away;
        best = piece;
      }
    }
    return best;
  }

  /// The same frame with the shadow pass turned off, for asking what a shadow
  /// is actually contributing.
  Future<Uint8List> drawWithout({required bool shadows}) async {
    fixtures.sync(_elapsed);
    final result = renderer.render(
      width: _width,
      height: _height,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: RenderSettings(shadows: ShadowSettings(enabled: !shadows)),
    );
    final pixels = await device.readPixels(result.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    return pixels!.buffer.asUint8List();
  }

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
/// Twelve rather than the shared default of eight: what these tests ask is
/// "did the picture change", and this backend's own dithering moves a channel
/// by a few steps between frames that are meant to be identical.
int _differences(Uint8List a, Uint8List b, {int threshold = 12}) =>
    differingPixels(a, b, channel: threshold);

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

    final drawn = await it.drawUntil((Uint8List f) => _goldPixels(f) > 20);
    final gold = _goldPixels(drawn);
    expect(
      gold,
      greaterThan(20),
      reason:
          'a coin three and a half metres in front of the camera never '
          'appeared, in two and a half seconds of frames',
    );

    // Taken through the world, the way walking over it does it.
    expect(
      coin.activate(it.mechanisms.activationBy(it.runner.body.collider)),
      isA<Activated>(),
    );
    it.wait(30); // Half a second; the shrink lasts three hundred milliseconds.

    final gone = await it.draw();
    expect(
      _goldPixels(gone),
      lessThan(gold ~/ 4),
      reason: 'the coin is still on screen after it was collected',
    );
    expect(
      _differences(drawn, gone),
      greaterThan(20),
      reason: 'the two frames are the same picture',
    );
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

    expect(
      _differences(withRunner, without),
      greaterThan(200),
      reason: 'hiding the runner changed nothing, so it was not drawn',
    );
  });

  test('a one-way platform is drawn, like anything else the level places', () {
    // A new `EntityKind` that forgets `context.reveal` spawns a collider the
    // player walks into and cannot see, and every simulation test passes. This
    // is stage E1's assertion on the picture, per the rule the harness was
    // built for.
    //
    // Mutation: drop the `context.reveal(...)` call from `OneWayKind.spawn`.
    return _Shown.build().then((_Shown it) async {
      final gantry = it.level.entities.firstWhere(
        (EntityDef e) => e.name == 'the gantry 1',
      );
      it.runner.body.teleport(gantry.position + Vector3(0.0, 6.0, 0.0));
      it.look(
        from: gantry.position + Vector3(0.0, 1.6, -7.0),
        at: gantry.position,
      );

      final drawn = await it.draw();
      final without = await it.draw(hiding: 'the gantry 1');

      expect(
        _differences(drawn, without),
        greaterThan(150),
        reason: 'hiding the gantry changed nothing, so it was never drawn',
      );
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

      expect(
        _differences(atRest, swung),
        greaterThan(120),
        reason: 'the rope moved in the simulation and not on the screen',
      );
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

      expect(
        _differences(standing, landed),
        greaterThan(80),
        reason: 'the runner is drawn the same standing and squashed',
      );
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

      expect(
        _differences(alive, gone),
        greaterThan(60),
        reason: 'the dead guard is still on the screen',
      );
    });
  });

  test('a shelf that gives way stops being drawn', () {
    // **The third time this question has been answered one type at a time.**
    // The coin was first, the stomped guard second, and five crumbling shelves
    // and three breakable caps in the shipped level were still keeping their
    // meshes after their colliders left — so a player falls through geometry
    // that looks perfectly solid.
    //
    // Mutation: take `Crumbling` back out of `PlatformerLooks.isSpent`. The two
    // frames match and this fails.
    return _Shown.build().then((_Shown it) async {
      final shelf = <Crumbling>[
        for (final m in it.mechanisms.all)
          if (m is Crumbling) m,
      ].first;
      final over = shelf.origin;
      it.look(from: over + Vector3(0.0, 2.5, -6.0), at: over);

      expect(shelf.hasFallen, isFalse);

      // Stood on until it goes. The runner is put on top rather than teleported
      // through, because what makes a shelf crumble is being stood on.
      it.runner.body.teleport(over + Vector3(0.0, 1.2, 0.0));
      for (var i = 0; i < 400 && !shelf.hasFallen; i++) {
        it.step();
      }
      expect(shelf.hasFallen, isTrue, reason: 'it never gave way');

      // **Both frames from the same instant**, differing only in whether the
      // shelf is drawn. The first version of this compared a frame from before
      // the collapse with one from after, and four hundred steps had passed in
      // between — barges had moved and lamps had flickered, so the two differed
      // by plenty whether the shelf was hidden or not, and deleting the fix
      // left the test green.
      it.runner.body.teleport(over + Vector3(0.0, 1.0, -20.0));
      final asDrawn = await it.draw();

      final piece = it.pieceNear(over);
      if (piece == null) fail('no drawn piece near the shelf');
      piece.visible = true;
      final forced = await it.drawAsIs();

      expect(
        _differences(asDrawn, forced),
        greaterThan(40),
        reason:
            'forcing the shelf visible changed nothing, so it was being '
            'drawn all along',
      );
    });
  });

  test('and so does a cap that is pounded through', () {
    // The other half of the same fix, and it needed its own test: with only the
    // shelf covered, deleting `Breakable` from `isSpent` left everything green.
    // Three caps in the shipped level, each hiding coins, each still drawn
    // after the runner had smashed it.
    //
    // Mutation: take `Breakable` back out of `PlatformerLooks.isSpent`.
    return _Shown.build().then((_Shown it) async {
      final cap = <Breakable>[
        for (final m in it.mechanisms.all)
          if (m is Breakable && m.name == 'the cap 2') m,
      ].first;
      final over = cap.origin;
      it.look(from: over + Vector3(0.0, 3.0, -7.0), at: over);

      // A ground pound, which is the only thing that opens one — see the
      // playthrough's own test that a landing does not.
      it.runner.body.teleport(over + Vector3(0.0, 6.0, 0.0));
      for (var i = 0; i < 4; i++) {
        it.step();
      }
      it.step(pound: true);
      for (var i = 0; i < 200 && !cap.isBroken; i++) {
        it.step();
      }
      expect(cap.isBroken, isTrue, reason: 'the pound did not break it');

      it.runner.body.teleport(over + Vector3(0.0, 1.0, -22.0));
      final asDrawn = await it.draw();

      final piece = it.pieceNear(over);
      if (piece == null) fail('no drawn piece near the cap');
      piece.visible = true;
      final forced = await it.drawAsIs();

      expect(
        _differences(asDrawn, forced),
        greaterThan(40),
        reason:
            'forcing the cap visible changed nothing, so it was being '
            'drawn all along',
      );
    });
  });

  test('the way out is something you can see', () {
    // **The goal of a 260 m level was marked by nothing.** `ExitKind` was the
    // one kind that spawned no fixture, so a player found the finish by walking
    // into an invisible volume, and the only clue was whatever coins the author
    // happened to scatter near it. `PlatformerLooks` has had a material for an
    // exit all along — pale and emissive — and it could never apply to
    // anything.
    //
    // Mutation: drop the `context.reveal` from `ExitKind.spawn`. There is
    // nothing near the exit to hide, and this fails on the first expectation.
    return _Shown.build().then((_Shown it) async {
      final exit = <Exit>[
        for (final m in it.mechanisms.all)
          if (m is Exit) m,
      ].first;
      final at = exit.origin;
      it.look(from: at + Vector3(0.0, 2.0, -8.0), at: at);

      // Out of shot, so what is measured is the exit and not the runner.
      it.runner.body.teleport(at + Vector3(0.0, 1.0, -30.0));
      final asDrawn = await it.draw();

      final piece = it.pieceNear(at);
      if (piece == null) fail('nothing is drawn at the way out');
      piece.visible = false;
      final without = await it.drawAsIs();

      expect(
        _differences(asDrawn, without),
        greaterThan(40),
        reason:
            'hiding the piece at the exit changed nothing, so what is '
            'there is not the exit',
      );
    });
  });

  test('the fence around the level does not shade a third of it', () {
    // **A fence is not architecture, and this one was lighting the level.** The
    // teaching level's boundary walls are sixteen metres tall — raised from six
    // when an autopilot climbed a chimney and walked off the top of the world —
    // and at this game's sun they laid a hard-edged band of shade across a
    // third of a twenty-two metre level. It was reported as a shadow that
    // follows you, which is what it looks like when you walk along one.
    //
    // Mutation: take `casts=False` off the walls in `make_first_steps.py` and
    // regenerate. The shadowed frame darkens by about eight per cent of itself
    // and this fails.
    return _Shown.build(level: 'assets/levels/first_steps.json').then((
      _Shown it,
    ) async {
      final at = Vector3(0.0, 0.9, 2.0);
      it.look(from: at + Vector3(0.0, 2.6, -7.0), at: at);
      // The runner out of shot: its own shadow is about three per cent of the
      // frame and entirely welcome, and leaving it in would mean choosing a
      // threshold that admits a character and excludes a wall — which is a
      // threshold that stops meaning anything.
      it.runner.body.teleport(Vector3(0.0, 0.9, -60.0));
      // Two crates and two lamps stand in this room and rightly cast; what is
      // measured is that nothing casts a *band*, so the comparison is against
      // the same frame with the fences put back rather than against zero.

      final asShipped = _darkFraction(await it.draw());

      // The fences put back into the shadow pass, and nothing else touched.
      for (final MeshNode piece in it.scene.meshes) {
        piece.castsShadow = true;
      }
      final withFences = _darkFraction(await it.drawAsIs());

      expect(
        withFences - asShipped,
        greaterThan(0.04),
        reason:
            'putting the fences back changed the frame by only '
            '${((withFences - asShipped) * 100).toStringAsFixed(1)}%, so '
            'either they were never the problem or they are still casting',
      );
      expect(
        asShipped,
        lessThan(withFences),
        reason: 'the shipped frame is the darker of the two',
      );
    });
  });

  test('the level a finished level names is one that loads and draws', () async {
    // The end of E5, asserted where it can actually go wrong. `sim.nextLevel`
    // is a string in a document; the failure it invites is a typo, or a level
    // that loads and shows nothing because its own lights never spawned. Both
    // of those look identical from the simulation's side — the state is
    // `finished` and the name is a name.
    //
    // Mutation: point `next` at a level that does not exist, or at one with no
    // lights. The first throws here; the second draws a flat frame.
    final first = await _Shown.build(level: 'assets/levels/first_steps.json');
    final next = first.level.next;
    expect(next, isNotNull, reason: 'the teaching level leads nowhere');

    final second = await _Shown.build(level: next!);
    final at = second.runner.position;
    second.look(from: at + Vector3(0.0, 3.0, -8.0), at: at);

    final grid = parityGrid(await second.draw(), _width, _height);
    final low = grid.reduce((int a, int b) => a < b ? a : b);
    final high = grid.reduce((int a, int b) => a > b ? a : b);
    expect(
      high - low,
      greaterThan(20),
      reason: 'the first frame of the next level is fog',
    );
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

    expect(
      high - low,
      greaterThan(20),
      reason: 'every cell of the frame is the same brightness',
    );
  });
}

/// How much of a frame reads as unlit.
double _darkFraction(Uint8List rgba) {
  var dark = 0;
  var total = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    total++;
    if (rgba[i] + rgba[i + 1] + rgba[i + 2] < 90) dark++;
  }
  return dark / total;
}
