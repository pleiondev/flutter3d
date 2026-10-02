/// `N5`: a recorded run through the Ascent, replayed with no GPU and checked
/// by digest at every checkpoint and by golden at two steps.
///
///     flutter test test/replay_test.dart
///
/// **What a game built on flutter3d writes to keep its CI honest**, and the
/// shortest version of it: one [testReplay] call and the four methods of a
/// [ReplaySubject]. The tape is `tool/record_sample.dart`'s, written beside
/// the site's sample; when the simulation changes on purpose, that script
/// records it again and the goldens are deleted and re-recorded.
///
/// Built from what the game itself calls — `openLevel`, `stage`, the
/// runner's box from [RunnerVisuals], the [FollowCamera] — rather than from a
/// harness's idea of the game, for the reason `frame_test.dart` gives: a
/// picture is only worth checking if it is the picture that ships.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_demo_platformer/src/lens.dart';
import 'package:flutter3d_demo_platformer/src/run.dart';
import 'package:flutter3d_demo_platformer/src/runner_visuals.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Ascent, loaded and staged the way `PlatformerRun` does it.
final class _Ascent implements ReplaySubject {
  _Ascent._(this._loaded, this._staged, this._fixtures, this._runnerNode)
    : _follow = FollowCamera(world: _loaded.collision);

  static Future<_Ascent> open(ReplayStart start) async {
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
    return _Ascent._(loaded, staged, fixtures, runnerNode);
  }

  final LoadedLevel _loaded;
  final Staged _staged;
  final FixtureVisuals _fixtures;
  final SceneNode _runnerNode;
  final FollowCamera _follow;
  final CameraNode _camera = CameraNode(projection: Lens.base);
  double _elapsed = 0.0;

  @override
  String? get levelHash => _loaded.level.digestHex;

  @override
  void restore(Snapshot start) {
    _staged.sim.restore(start);
    _follow.cut();
  }

  @override
  void step(double dt) {
    _staged.sim.step(dt);
    _staged.sim.events.drain();
    _elapsed += dt;
    // Followed every step, as the game follows it every frame: a camera
    // placed only when a golden is drawn would start from where it was built.
    final runner = _staged.runner;
    _follow.follow(runner.position, dt, travelling: runner.body.velocity);
  }

  @override
  Snapshot save() => _staged.sim.save();

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
