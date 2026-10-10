/// N7: a run leaves the machine only with the player's yes, and what the
/// server reads off it comes from playing it again.
///
///     dart test test/telemetry_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const String _policy = '2026-10';

/// A body that walks along x as the stick says: past x = 4 the run is won,
/// below x = -2 it is lost.
final class _Walk extends HeadlessRun {
  _Walk(this.input, {required this.start});

  final InputState input;
  final double start;
  late final Vector3 _at = Vector3(start, 0.0, 0.0);

  @override
  RunOutcome outcome = RunOutcome.playing;

  @override
  void step(double dt) {
    if (outcome.isOver) return;
    _at
      ..x += input.moveAxis.x * 3.0 * dt
      ..z += input.moveAxis.y * 3.0 * dt;
    if (_at.x > 4.0) outcome = RunOutcome.won;
    if (_at.x < -2.0) outcome = RunOutcome.lost;
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{
    'x': _at.x,
    'z': _at.z,
    'outcome': outcome.name,
  });

  @override
  WorldPosition get position => _at.toWorldPosition();

  @override
  WorldPosition get eye => _at.toWorldPosition();

  @override
  void aim(Vector3 out) => out.setValues(1.0, 0.0, 0.0);

  @override
  String get summary => 'at ${_at.x}';

  @override
  Map<String, Object?> get reading => <String, Object?>{'x': _at.x};
}

final class _WalkGame extends HeadlessGame {
  const _WalkGame({this.from = 0.0});

  final double from;

  @override
  String get name => 'walk';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _Walk(input, start: from);
}

Level _level({double width = 20.0}) => Level(
  name: 'strip',
  materials: <String, LevelMaterial>{'stone': LevelMaterial()},
  brushes: <Brush>[
    Brush(
      center: Vector3(0.0, -0.5, 0.0),
      size: Vector3(width, 1.0, 4.0),
      material: 'stone',
    ),
  ],
  entities: const <EntityDef>[],
);

/// Plays [level] with the stick at [stick] for [steps] steps, recording as a
/// game does: the tape before the step, the checkpoint after it.
Demo _record(Level level, {required double stick, int steps = 120}) {
  final input = InputState();
  final world = CollisionWorld();
  level.addTo(world);
  final run = const _WalkGame().start(level, world, input);
  final start = run.save();
  final recorder = InputTapeRecorder(seed: 1);
  final trace = DigestTrace(every: 10);
  for (var step = 1; step <= steps; step++) {
    input.setStickAxis(stick, 0.2);
    recorder.record(input);
    input.beginStep();
    run.step(1.0 / 60.0);
    trace.observe(step, run.save().toJson());
    input.endStep();
  }
  return Demo(
    level: 'levels/strip.json',
    levelHash: level.digestHex,
    start: start,
    tape: recorder.tape,
    buildStamp: 'test',
    checkpoints: trace,
    recordedBy: 'somebody',
  );
}

TelemetryConsent _granted([String policy = _policy]) =>
    TelemetryConsent.granted(policy: policy, at: DateTime.utc(2026, 10, 1));

final class _Sink extends TelemetrySink {
  final List<TelemetryUpload> delivered = <TelemetryUpload>[];

  @override
  Future<TelemetrySent> deliver(TelemetryUpload upload) async {
    delivered.add(upload);
    return (
      did: true,
      says: 'taken',
      receipt: const TelemetryReceipt(run: 1, eraseKey: 'k'),
    );
  }
}

void main() {
  group('consent', () {
    test('nothing is sent until the player is asked and says yes', () async {
      // Mutation: `allows` answering true for notAsked sends every run of a
      // player who never saw the question.
      final sink = _Sink();
      var consent = const TelemetryConsent.notAsked();
      final uploader = TelemetryUploader(
        game: 'walk',
        policy: _policy,
        consent: () => consent,
        sink: sink,
      );
      final demo = _record(_level(), stick: 1.0);

      final unasked = await uploader.send(demo);
      expect(unasked.did, isFalse);
      expect(unasked.says, contains('has not been asked'));

      consent = TelemetryConsent.declined(
        policy: _policy,
        at: DateTime.utc(2026, 10, 1),
      );
      final declined = await uploader.send(demo);
      expect(declined.says, contains('said no'));
      expect(sink.delivered, isEmpty);

      consent = _granted();
      expect((await uploader.send(demo)).did, isTrue);
      expect(sink.delivered, hasLength(1));
    });

    test('a yes to an older wording is not a yes to this one', () {
      // Mutation: comparing only the answer and not the policy.
      final prepared = TelemetryUpload.prepare(
        game: 'walk',
        demo: _record(_level(), stick: 1.0),
        consent: _granted('2025-01'),
        policy: _policy,
      );
      expect(prepared.upload, isNull);
      expect(prepared.says, contains('"2025-01"'));
      expect(prepared.says, contains('ask again'));
    });

    test('a settings file damaged where the yes was reads as not asked', () {
      // Mutation: defaulting an unreadable answer to granted.
      for (final Object? damaged in <Object?>[
        null,
        'granted',
        <String, Object?>{'answer': 'granted'},
        <String, Object?>{'answer': 'granted', 'policy': _policy, 'at': 'x'},
        <String, Object?>{'answer': 'maybe', 'policy': _policy, 'at': '2026'},
      ]) {
        expect(
          TelemetryConsent.fromJson(damaged).wasAsked,
          isFalse,
          reason: '$damaged',
        );
      }
      final kept = TelemetryConsent.fromJson(
        jsonDecode(jsonEncode(_granted().toJson())),
      );
      expect(kept.allows(_policy), isTrue);
      expect(kept.at, DateTime.utc(2026, 10, 1));
      final no = TelemetryConsent.fromJson(
        jsonDecode(
          jsonEncode(
            TelemetryConsent.declined(
              policy: _policy,
              at: DateTime.utc(2026, 10, 1),
            ).toJson(),
          ),
        ),
      );
      expect((no.wasAsked, no.isGranted), (true, false));
    });
  });

  group('the upload', () {
    test('drops who recorded the run, and carries the consent', () {
      // Mutation: passing the demo through unchanged sends the player's name.
      final upload = TelemetryUpload.prepare(
        game: 'walk',
        demo: _record(_level(), stick: 1.0),
        consent: _granted(),
        policy: _policy,
      ).upload!;
      final read = TelemetryUpload.fromJson(
        jsonDecode(jsonEncode(upload.toJson())) as Map<String, Object?>,
      );
      expect(read.demo.recordedBy, isNull);
      expect(jsonEncode(upload.toJson()), isNot(contains('somebody')));
      expect(read.game, 'walk');
      expect(read.policy, _policy);
      expect(read.demo.steps, 120);
    });

    test('carries the physics the run was played on', () {
      // Mutation: rebuilding the demo without it, which a server reads as
      // "whatever I run" and replays a run from the reference on the core.
      final demo = _record(_level(), stick: 1.0);
      final upload = TelemetryUpload.prepare(
        game: 'walk',
        demo: Demo.fromJson(demo.toJson()..['physics'] = 'dart'),
        consent: _granted(),
        policy: _policy,
      ).upload!;
      final read = TelemetryUpload.fromJson(
        jsonDecode(jsonEncode(upload.toJson())) as Map<String, Object?>,
      );
      expect(read.demo.physics, 'dart');
    });

    test('one that arrives without consent is refused by the reader', () {
      // Mutation: a server reading uploads that never carried a grant.
      final json = TelemetryUpload.prepare(
        game: 'walk',
        demo: _record(_level(), stick: 1.0),
        consent: _granted(),
        policy: _policy,
      ).upload!.toJson()..remove('consent');
      expect(
        () => TelemetryUpload.fromJson(json),
        throwsA(
          isA<TelemetryUploadFormatException>().having(
            (e) => e.message,
            'message',
            contains('no consent'),
          ),
        ),
      );
    });

    test('over HTTP, a receipt comes back from a 201 and the server\'s '
        'sentence from anything else', () async {
      // Mutation: treating any 2xx or any JSON as accepted.
      final upload = TelemetryUpload.prepare(
        game: 'walk',
        demo: _record(_level(), stick: 1.0),
        consent: _granted(),
        policy: _policy,
      ).upload!;
      final endpoint = Uri.parse('http://localhost/api/telemetry/runs');
      String? sent;
      final taken = await HttpTelemetrySink(
        endpoint: endpoint,
        post: (url, json) async {
          sent = json;
          return (status: 201, body: '{"run":7,"eraseKey":"abc","says":"ok"}');
        },
      ).deliver(upload);
      expect(taken.did, isTrue);
      expect(taken.receipt!.run, 7);
      expect(taken.receipt!.eraseKey, 'abc');
      expect(jsonDecode(sent!), containsPair('game', 'walk'));

      final refused = await HttpTelemetrySink(
        endpoint: endpoint,
        post: (url, json) async =>
            (status: 422, body: '{"says":"this server plays no walk"}'),
      ).deliver(upload);
      expect(refused.did, isFalse);
      expect(refused.says, 'this server plays no walk');

      final down = await HttpTelemetrySink(
        endpoint: endpoint,
        post: (url, json) async => throw StateError('connection refused'),
      ).deliver(upload);
      expect(down.did, isFalse);
      expect(down.says, contains('could not reach'));
    });
  });

  group('re-simulation', () {
    test('retraces the run and reads where it went and how it ended', () {
      // Mutation: sampling the trail from the recording client rather than
      // the replay would make an empty trail here, since a demo has none.
      final level = _level();
      final demo = _record(level, stick: 1.0);

      final found = resimulate(
        game: const _WalkGame(),
        level: level,
        demo: demo,
        sampleEvery: 20,
      );

      final retraced = found as ResimulationRetraced;
      expect(retraced.steps, 120);
      expect(retraced.checkpoints, 12);
      expect(retraced.outcome, RunOutcome.won);
      expect(retraced.trail, hasLength(6));
      // Twenty steps of a stick at (1, 0.2), which the input normalises.
      expect(retraced.trail.first.$1, closeTo(0.98, 0.001));
      expect(retraced.trail.last.$1, greaterThan(4.0));
    });

    test('a level edited since the recording is refused, naming both', () {
      // Mutation: skipping the hash check replays a tape into other geometry.
      final demo = _record(_level(), stick: 1.0);
      final found = resimulate(
        game: const _WalkGame(),
        level: _level(width: 30.0),
        demo: demo,
      );
      final changed = found as ResimulationLevelChanged;
      expect(changed.recorded, demo.levelHash);
      expect(changed.found, _level(width: 30.0).digestHex);
    });

    test('a run recorded on other physics is refused, naming both', () {
      // Mutation: playing it on whatever this process runs, which diverges
      // with nothing to say why.
      final level = _level();
      final other = const DartPhysics().name == 'dart' ? 'native' : 'dart';
      final found = resimulate(
        game: const _WalkGame(),
        level: level,
        demo: Demo.fromJson(
          _record(level, stick: 1.0).toJson()..['physics'] = other,
        ),
      );
      final refused = found as ResimulationOnOtherPhysics;
      expect(refused.recorded, other);
      expect(refused.running, const DartPhysics().name);
    });

    test('a run that does not start where the recording did is refused', () {
      final level = _level();
      final found = resimulate(
        game: const _WalkGame(from: 1.0),
        level: level,
        demo: _record(level, stick: 1.0),
      );
      expect(found, isA<ResimulationStartDiffers>());
    });

    test('a tape edited after it was recorded diverges, and says where', () {
      // Mutation: trusting the client's checkpoints rather than comparing
      // the replay's own against them.
      final level = _level();
      final honest = _record(level, stick: 1.0);
      final forged = Demo(
        level: honest.level,
        levelHash: honest.levelHash,
        start: honest.start,
        tape: InputTape(
          seed: honest.tape.seed,
          frames: <InputFrame>[
            ...honest.tape.frames.take(44),
            const InputFrame(stickX: -1.0),
            ...honest.tape.frames.skip(45),
          ],
        ),
        buildStamp: honest.buildStamp,
        checkpoints: honest.checkpoints,
      );
      final found = resimulate(
        game: const _WalkGame(),
        level: level,
        demo: forged,
      );
      final diverged = found as ResimulationDiverged;
      expect(diverged.divergence.step, 50);
      expect(diverged.agreedUntil, 40);
    });
  });

  group('the heatmap', () {
    final trails = <HeatmapTrail>[
      const HeatmapTrail(
        run: 1,
        steps: 30,
        outcome: 'lost',
        positions: <(double, double)>[(0.5, 0.5), (0.6, 0.4), (1.5, 0.5)],
        endedBadly: true,
      ),
      const HeatmapTrail(
        run: 2,
        steps: 20,
        outcome: 'won',
        positions: <(double, double)>[(0.2, 0.2), (2.5, -0.5)],
      ),
    ];

    test('counts samples and distinct runs per cell, and marks only the '
        'runs that were lost', () {
      // Mutation: counting samples under `runs` would make the first cell
      // three runs from two trails.
      final map = Heatmap.bin(
        trails,
        outcomeNames: const <String>['won', 'lost', 'unfinished'],
      );
      final origin = map.cells.singleWhere((c) => c.x == 0 && c.z == 0);
      expect(origin.samples, 3);
      expect(origin.runs, 2);
      expect(map.cells.singleWhere((c) => c.x == 2).z, -1);
      expect(map.ends.single.run, 1);
      expect(map.ends.single.x, 1.5);
      expect(map.outcomes, <String, int>{'won': 1, 'lost': 1, 'unfinished': 0});
      expect(map.runs, 2);
    });

    test('writes the playtest report\'s keys, and reads them back', () {
      // Mutation: renaming `deaths`/`seed` breaks every report already on
      // disk and the editor that reads them.
      final json =
          jsonDecode(jsonEncode(Heatmap.bin(trails, cellSize: 2.0).toJson()))
              as Map<String, Object?>;
      expect(json.keys, containsAll(<String>['cellSize', 'cells', 'deaths']));
      expect((json['deaths']! as List).single, containsPair('seed', 1));

      final read = Heatmap.fromJson(json);
      expect(read.cellSize, 2.0);
      expect(read.cells.map((c) => c.samples), <int>[4, 1]);
      expect(read.ends.single.step, 30);

      expect(
        () => Heatmap.fromJson(<String, Object?>{'cellSize': 1.0}),
        throwsA(isA<HeatmapFormatException>()),
      );
    });
  });
}
