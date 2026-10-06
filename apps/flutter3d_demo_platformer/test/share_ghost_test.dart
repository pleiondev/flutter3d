/// N10's line done: a run shared from one window, opened by its code in
/// another and raced as a ghost — through the reference server, started here
/// under `dart run`.
///
///     flutter test test/share_ghost_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter3d/flutter3d.dart' show SceneNode;
import 'package:flutter3d_app/flutter3d_app.dart' show Storage;
import 'package:flutter3d_demo_platformer/src/ghost.dart';
import 'package:flutter3d_demo_platformer/src/staging.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Storage implements Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  String? read(String name) => documents[name];
  @override
  bool write(String name, String contents) {
    documents[name] = contents;
    return true;
  }

  @override
  void remove(String name) => documents.remove(name);
}

const double _dt = 1.0 / 60.0;

Map<String, Object?> _document() =>
    jsonDecode(File('assets/levels/ascent.json').readAsStringSync())
        as Map<String, Object?>;

/// The first window: the ascent played for [steps], recorded, with where the
/// runner's feet were at every step written down beside it.
({Demo demo, List<Vector3> feet}) _played(int steps) {
  final level = Level.fromJson(_document());
  final world = CollisionWorld();
  level.addTo(world);
  final input = InputState();
  final staged = stage(level, world, input: input);
  world.update();
  // Begun a second in, as a run picked up from a save is: what is shared
  // starts where the run did, not at the top of the level.
  input.press(GameAction.moveForward);
  for (var i = 0; i < 60; i++) {
    input.beginStep();
    staged.sim.step(_dt);
    input.endStep();
  }
  input.release(GameAction.moveForward);
  final start = staged.sim.save();
  final recorder = InputTapeRecorder(seed: start.data.integer('random'));
  final checkpoints = DigestTrace();
  Vector3 feet() =>
      staged.runner.position.clone()..y -= staged.runner.body.halfExtents.y;
  final at = <Vector3>[feet()];
  for (var i = 0; i < steps; i++) {
    if (i % 30 < 22) {
      input.press(GameAction.moveForward);
    } else {
      input.release(GameAction.moveForward);
    }
    if (i % 60 == 0) input.press(GameAction.jump);
    if (i % 60 == 3) input.release(GameAction.jump);
    recorder.record(input);
    input.beginStep();
    staged.sim.step(_dt);
    checkpoints.observe(recorder.tape.steps, staged.sim.save().toJson());
    input.endStep();
    at.add(feet());
  }
  return (
    demo: Demo(
      level: 'assets/levels/ascent.json',
      levelHash: level.digestHex,
      start: start,
      tape: recorder.tape,
      buildStamp: 'share-ghost-test',
      checkpoints: checkpoints,
      physics: PhysicsBackend.current.name,
    ),
    feet: at,
  );
}

void main() {
  Process? server;
  late String address;

  setUpAll(() async {
    // `dart`, not this process's own executable, which under `flutter test`
    // is the tester rather than the VM.
    final started = await Process.start('dart', <String>[
      'run',
      'tool/share_server.dart',
    ], workingDirectory: '../../cloud/server');
    server = started;
    final listening = Completer<String>();
    started.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
          final port = RegExp(r'listening on (\d+)').firstMatch(line);
          if (port != null && !listening.isCompleted) {
            listening.complete('http://127.0.0.1:${port.group(1)}/');
          }
        });
    unawaited(started.stderr.drain<void>());
    address = await listening.future.timeout(const Duration(minutes: 4));
  });

  tearDownAll(() => server?.kill());

  test('shared from one window, raced as a ghost in another', () async {
    final played = _played(240);

    // The first window shares it: the level and the run, as one bundle.
    final sharing = GameCloud(
      game: 'platformer',
      storage: _Storage(),
      server: address,
    );
    final filed = await sharing.shares!.share(
      ShareBundle(game: 'platformer', level: _document(), run: played.demo),
    );
    final code = switch (filed) {
      ServiceDone<SharedBundle>(:final value) => value.code,
      ServiceRefused<SharedBundle>(:final reason) => fail(reason),
    };

    // The second knows only the code.
    final watching = GameCloud(
      game: 'platformer',
      storage: _Storage(),
      server: address,
    );
    final opened = await watching.shares!.open(code);
    final bundle = switch (opened) {
      ServiceDone<ShareBundle>(:final value) => value,
      ServiceRefused<ShareBundle>(:final reason) => fail(reason),
    };
    final (:ghost, :says) = ghostOf(Level.fromJson(bundle.level), bundle.run!);
    expect(ghost, isNotNull, reason: says);

    // Wherever the ghost was sampled, it is where the runner was, to the bit:
    // the same steps, played again on the same physics.
    // Mutation: playing the tape from a fresh level rather than the run's
    // own start, or one step out of phase — either puts it elsewhere.
    expect(ghost!.poses.length, greaterThan(100));
    for (final pose in ghost.poses) {
      final step = (pose.time / _dt).round();
      expect(pose.position, played.feet[step], reason: 'step $step');
    }
    // And it went somewhere: a ghost that stands at the start races nobody.
    expect(
      ghost.poses.last.position.distanceTo(ghost.poses.first.position),
      greaterThan(3.0),
    );
  });

  test('a run of another version of the level is no ghost', () {
    final played = _played(30);
    final edited = _document()..['name'] = 'Another ascent';
    expect(ghostOf(Level.fromJson(edited), played.demo).ghost, isNull);
  });

  test('the ghost is drawn where the track was, and nowhere outside it', () {
    final track = Tape(
      poses: <Pose>[
        Pose(time: 0.0, yaw: 0.0)..position.setValues(0.0, 0.0, 0.0),
        Pose(time: 1.0, yaw: 0.0)..position.setValues(4.0, 0.0, 0.0),
      ],
      seconds: 1.0,
    );
    final ghost = GhostRunner(SceneNode(name: 'ghost'), modelFloor: -0.5);
    ghost.showAt(0.5, track);
    expect(ghost.node.visible, isTrue);
    // Halfway in time is halfway along; lifted by the model's own floor.
    expect(ghost.node.worldMatrix.getTranslation().x, closeTo(2.0, 1e-6));
    expect(ghost.node.worldMatrix.getTranslation().y, closeTo(0.5, 1e-6));
    // Mutation: leaving it where it was once the run is over, which reads as
    // a runner standing at the finish.
    ghost.showAt(1.5, track);
    expect(ghost.node.visible, isFalse);
  });

  test('the game shares where a run is over, and draws the ghost it races', () {
    // A scan: the screen is a widget no test mounts without a window.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ShareStrip('));
    expect(main, contains('_haunt(level, device)'));
    expect(main, contains('ghost.showAt(sim.elapsed, track)'));
  });
}
