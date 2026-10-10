/// `N5`: a recorded run through the Ascent, replayed with no GPU and checked
/// by digest at every checkpoint and by golden at two steps.
///
///     flutter test test/replay_test.dart
///
/// **What a game built on flutter3d writes to keep its CI honest**, and the
/// shortest version of it: one [testReplay] call and a [ReplaySubject] — the
/// loop the run is stepped in, the genre whose run the tape is, and the
/// picture. The tape is `tool/record_sample.dart`'s, written beside
/// the site's sample; when the simulation changes on purpose, that script
/// records it again and the goldens are deleted and re-recorded.
///
/// Built from what the game itself calls — `openLevel`, `stage`, the
/// runner's box from [RunnerVisuals], the [FollowCamera] — rather than from a
/// harness's idea of the game, for the reason `frame_test.dart` gives: a
/// picture is only worth checking if it is the picture that ships.
library;

import 'package:flutter3d_demo_platformer/src/lens.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/run_elements.dart';
import 'package:flutter3d_demo_platformer/src/runner_visuals.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Ascent, loaded and staged the way `PlatformerRun` does it, and
/// stepped in a loop the way the game steps it: `platformer.step` in
/// `physics`, the level's water and fires in `elements` after it.
final class _Ascent extends ReplaySubject {
  _Ascent._(
    this._loaded,
    this._staged,
    this._fixtures,
    this._runnerNode,
    InputState input,
  ) : _follow = FollowCamera(world: _loaded.collision) {
    genre.simulation = _staged.sim;
    loop = EngineLoop(input: input, plugins: <Flutter3dPlugin>[genre])
      ..addSystem(
        'replay.elements',
        LoopPhase.fields,
        (step) => stepElements(_staged.sim, _staged.elements, step.dt),
      );
    // Followed every step, as the game follows it every frame: a camera
    // placed only when a golden is drawn would start from where it was
    // built. Cut first, so the first step's follow lands on the runner
    // wherever the tape's start put it.
    _follow.cut();
    loop.onStepEnd((_) {
      final dt = loop.stepSeconds;
      _elapsed += dt;
      final runner = _staged.runner;
      _follow.follow(runner.position, dt, traveling: runner.body.velocity);
    });
  }

  static Future<_Ascent> open(ReplayStart start) async {
    // On the backend it was recorded on: the two are not promised to agree.
    await startPhysics(asked: start.demo.physics ?? askedPhysics);
    final (:kinds, :loaded, :fixtures) = await openLevel(
      start.demo.level,
      device: start.device,
    );
    final staged = stage(
      loaded.level,
      loaded.collision,
      input: start.input,
      registry: kinds,
      onFixture: fixtures.add,
    );
    loaded.collision.update();
    final runnerNode = RunnerVisuals(
      model: '',
    ).box(start.device, loaded.scene, staged.runner);
    return _Ascent._(loaded, staged, fixtures, runnerNode, start.input);
  }

  final LoadedLevel _loaded;
  final Staged _staged;
  final FixtureVisuals _fixtures;
  final SceneNode _runnerNode;
  final FollowCamera _follow;
  final CameraNode _camera = CameraNode(projection: ascentLens.base);
  double _elapsed = 0.0;

  @override
  final PlatformerPlugin genre = PlatformerPlugin();

  @override
  late final EngineLoop loop;

  @override
  String? get levelHash => _loaded.level.digestHex;

  @override
  Future<FrameSubject> frame(int step) async {
    // The coins and the gates are models read in the background; drawn
    // before they arrive, the golden depends on how busy the machine was.
    await _fixtures.settled;
    _fixtures.sync(_elapsed);
    final p = _staged.runner.position;
    _runnerNode.setPosition(p.x, p.y, p.z);
    _camera
      ..setPositionFrom(_follow.eye)
      ..lookAt(_follow.target);
    if (_camera.parent == null) _loaded.scene.add(_camera);
    return (scene: _loaded.scene, camera: _camera);
  }
}

void main() {
  // Mutation: change a number in the runner's tuning — `jumpSpeed`, say — and
  // the first checkpoint after the first jump disagrees and names its step.
  // Move a brush in `ascent.json` and the test fails on the level's hash
  // before a step is taken.
  testReplay(
    'test/tapes/ascent.f3drun',
    start: _Ascent.open,
    goldensAt: <int>[120, 600],
  );
}
