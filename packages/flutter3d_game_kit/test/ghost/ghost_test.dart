/// A ghost drawn from a track, the track read off a shared run, and the best
/// run kept between launches.
///
///     flutter test test/ghost_test.dart
///
/// Moved here from the platformer's `ghost.dart` and racing's `ghost_car.dart`,
/// which drew the same thing two ways: the platformer's stood on a model's
/// floor and turned by a model's facing, racing's leaned along the road's up.
/// One [Ghost] does both, and these hold each half.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show SharedMeshes, Storage;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_game_kit/ghost.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Storage extends Storage {
  final Map<String, String> documents = <String, String>{};
  @override
  Future<String?> read(String name) async => documents[name];
  @override
  Future<void> write(String name, String contents) async {
    documents[name] = contents;
  }

  @override
  Future<void> remove(String name) async => documents.remove(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Four metres along x in one second, facing nought.
Tape _straight() => Tape(
  poses: <Pose>[
    Pose(time: 0.0, yaw: 0.0)..position.setValues(0.0, 0.0, 0.0),
    Pose(time: 1.0, yaw: 0.0)..position.setValues(4.0, 0.0, 0.0),
  ],
  seconds: 1.0,
);

Vector3 _at(Ghost ghost) => ghost.node.worldMatrix.getTranslation();

/// [seconds] of a body moving along x, sampled by a [BestRun].
void _play(BestRun run, {double seconds = 4.0, double speed = 1.0}) {
  for (var t = 0.0; t <= seconds; t += 1.0 / 60.0) {
    run.watch(t, position: Vector3(t * speed, 0.0, 0.0), yaw: 0.0);
  }
}

Level _level() => Level(name: 'yard');

Demo _run(
  Level level, {
  String? physics,
  SimulationVersion? simulation,
  PoseRecord? poses,
}) => Demo(
  level: 'yard.json',
  levelHash: level.digestHex,
  start: const Snapshot(<String, Object?>{'x': 0}),
  tape: InputTape(seed: 3, frames: <InputFrame>[const InputFrame()]),
  buildStamp: 'test',
  checkpoints: DigestTrace(every: 1)..observe(1, 0),
  physics: physics,
  simulation: simulation,
  poses: poses,
);

PoseRecord _poses() {
  final recorder = PoseRecorder(every: 1);
  for (var step = 0; step < 30; step++) {
    recorder.record(step, <BodyPose>[
      BodyPose('body', Vector3(step * 0.1, 0.0, 0.0), Quaternion.identity()),
    ]);
  }
  return recorder.recorded;
}

const SimulationVersion _game = SimulationVersion(genre: 'yard');

void main() {
  group('a ghost', () {
    test('is drawn where the track was, and nowhere outside it', () {
      final ghost = Ghost(SceneNode(name: 'ghost'), floor: -0.5);
      expect(ghost.showAt(0.5, _straight()), isTrue);
      expect(ghost.node.isVisible, isTrue);
      // Halfway in time is halfway along; lifted by the model's own floor.
      expect(_at(ghost).x, closeTo(2.0, 1e-6));
      expect(_at(ghost).y, closeTo(0.5, 1e-6));
      // Mutation: leave it where it was once the track is over — this fails,
      // and reads as something parked where the run ended.
      expect(ghost.showAt(1.5, _straight()), isFalse);
      expect(ghost.node.isVisible, isFalse);
    });

    test('is lifted along the track\'s own up, not the world\'s', () {
      // On a banked corner the two differ by most of a metre.
      //
      // Mutation: add `lift` to y alone — this fails.
      final tilted = Vector3(1.0, 1.0, 0.0)..normalize();
      final track = Tape(
        poses: <Pose>[
          Pose(time: 0.0, yaw: 0.0)..up.setFrom(tilted),
          Pose(time: 1.0, yaw: 0.0)..up.setFrom(tilted),
        ],
        seconds: 1.0,
      );
      final ghost = Ghost(SceneNode(name: 'ghost'))
        ..showAt(0.5, track, lift: 1.0);
      expect(_at(ghost).x, closeTo(tilted.x, 1e-6));
      expect(_at(ghost).y, closeTo(tilted.y, 1e-6));
    });

    test('turns by the model\'s own facing', () {
      // Mutation: drop `facing` from the rotation — this fails.
      final ghost = Ghost(SceneNode(name: 'ghost'), facing: 1.0)
        ..showAt(0.5, _straight());
      final forward = ghost.node.worldMatrix.transformed3(Vector3(0, 0, 1))
        ..sub(_at(ghost));
      // A turn of one radian about +Y carries +Z to (sin 1, 0, cos 1). Not
      // `Quaternion.rotated`: vector_math's applies the inverse rotation
      // (conjugate · v · q), and would expect the ghost to turn the other way.
      final expected = Vector3(math.sin(1.0), 0.0, math.cos(1.0));
      expect(forward.x, closeTo(expected.x, 1e-6));
      expect(forward.z, closeTo(expected.z, 1e-6));
    });

    test('is one translucent shape, every part of it', () {
      // Mutation: haunt only the first mesh — the second keeps its own
      // material and this fails.
      final look = Ghost.look();
      expect(look.alphaMode, MaterialAlphaMode.blend);
      expect(look.depthWrite, isFalse);
      expect(look.lighting, LightingModel.unlit);
      final device = CpuDevice(
        width: 4,
        height: 4,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      final parts = <MeshNode>[
        for (var i = 0; i < 2; i++)
          MeshNode(
            SharedMeshes(device).box(Vector3.all(1.0)),
            RenderMaterial(name: 'paint $i'),
          ),
      ];
      Ghost.haunt(parts, look);
      for (final part in parts) {
        expect(identical(part.material, look), isTrue);
      }
    });
  });

  group('the best run', () {
    test('is kept against the record, not against the session', () async {
      // The first run of a launch is the best of the session by definition,
      // and a warm-up would overwrite the record somebody spent an evening on.
      //
      // Mutation: drop the comparison with `record` in `finished` — the
      // second launch's slower run is kept and this fails.
      final storage = _Storage();
      final first = BestRun(storage: storage, name: 'best-yard.json');
      _play(first);
      expect(first.finished(4.0), isTrue);

      await first.saved;
      final again = BestRun(storage: storage, name: 'best-yard.json');
      await again.load();
      expect(again.record, closeTo(4.0, 1e-9));
      _play(again, seconds: 9.0);
      expect(again.finished(9.0), isFalse);
      expect(again.record, closeTo(4.0, 1e-9));
    });

    test('is not a run with almost nothing in it', () {
      // Mutation: drop the `fewestPoses` check — this fails.
      final run = BestRun(storage: _Storage(), name: 'best.json')
        ..watch(0.0, position: Vector3.zero(), yaw: 0.0);
      expect(run.finished(0.1), isFalse);
      expect(run.best, isNull);
    });

    test('reads back what it wrote, in the game\'s own format', () {
      // Mutation: ignore `encode` and write the default — the document has no
      // `took` and this fails.
      final storage = _Storage();
      final run = BestRun(
        storage: storage,
        name: 'best.json',
        encode: (Tape tape) => <String, Object?>{
          ...tapeToJson(tape),
          'took': tape.seconds,
        },
      );
      _play(run);
      run.finished(4.0);
      final written = jsonDecode(storage.documents['best.json']!) as Map;
      expect(written['took'], 4.0);
      final back = tapeFromJson(written.cast<String, Object?>());
      expect(back.poses.length, run.best!.poses.length);
    });

    test('the version 1 fixture and the shape before the envelope read', () {
      // Minted on 2026-10-09, when the best run went into the envelope as
      // `f3d.ghostTape`. Mutation: give the spec `f3d.ghost`'s id and the
      // racing lap's reader would claim this file.
      final fixture =
          jsonDecode(File('test/fixtures/v1/run.best.json').readAsStringSync())
              as Map<String, Object?>;
      final tape = tapeFromJson(fixture);
      expect(tape.seconds, 4.0);
      expect(tape.poses, hasLength(4));

      final bare = <String, Object?>{
        'version': 1,
        'seconds': fixture['seconds'],
        'frames': fixture['frames'],
      };
      expect(tapeFromJson(bare).poses, hasLength(4));
      expect(
        () => tapeFromJson(<String, Object?>{...fixture, 'version': 2}),
        throwsA(isA<DocumentFormatException>()),
      );
      expect(
        () =>
            tapeFromJson(<String, Object?>{...fixture, 'format': 'f3d.ghost'}),
        throwsA(isA<DocumentFormatException>()),
      );
    });

    test('never throws on a document it cannot read, and drops it', () async {
      // Mutation: rethrow from `load` — this fails.
      final storage = _Storage()..documents['best.json'] = '{"frames": 3}';
      final run = BestRun(storage: storage, name: 'best.json');
      await expectLater(run.load(), completes);
      expect(run.best, isNull);
      expect(storage.documents, isNot(contains('best.json')));
    });
  });

  group('the ghost of a run', () {
    test('is refused in another version of the level', () {
      // Mutation: drop the level check — the replay is played and this fails.
      final level = _level();
      final other = Level(name: 'another yard');
      var replayed = false;
      final (:ghost, :note) = ghostOfRun(
        other,
        _run(level),
        body: 'body',
        simulation: _game,
        replay: () {
          replayed = true;
          return _straight();
        },
      );
      expect(ghost, isNull);
      expect(replayed, isFalse);
      expect(note.id, GhostNote.otherLevel);
      expect(note.say(), contains('another version of this level'));
    });

    test('is the tape played again when it can be', () {
      final level = _level();
      final (:ghost, :note) = ghostOfRun(
        level,
        _run(level, simulation: _game),
        body: 'body',
        simulation: _game,
        replay: _straight,
      );
      expect(ghost?.seconds, 1.0);
      expect(note.say(), 'a ghost of 1.0 s');
    });

    test('is the pose record when the tape cannot be played', () {
      // Another version of the game's rules: the tape would come out somewhere
      // else, the poses are where the body was.
      //
      // Mutation: drop the simulation check — the replay is played instead of
      // the record and this fails.
      final level = _level();
      final later = const SimulationVersion(genre: 'yard', genreVersion: 2);
      final (:ghost, :note) = ghostOfRun(
        level,
        _run(level, simulation: later, poses: _poses()),
        body: 'body',
        simulation: _game,
        replay: () => fail('a run on another simulation was replayed'),
      );
      expect(ghost, isNotNull);
      expect(ghost!.isEmpty, isFalse);
      expect(note.say(), contains('from its pose record'));
    });

    test('is refused with the reason when there is no pose record either', () {
      // Mutation: hand back an empty track rather than null — this fails.
      final level = _level();
      final (:ghost, :note) = ghostOfRun(
        level,
        _run(level, physics: 'elsewhere'),
        body: 'body',
        simulation: _game,
        replay: () => fail('a run on other physics was replayed'),
      );
      expect(ghost, isNull);
      expect(note.say(), contains('elsewhere physics'));
    });
  });
}
