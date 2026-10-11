/// State from outside the simulation: fed as input, assimilated inside the
/// step, recorded on the tape with its step and replayed with it.
///
///     dart test test/external_state_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// What the plant says the tank holds, as the model keeps it.
final class _Tank {
  const _Tank(this.level);

  final double level;
}

/// Takes the sensor's level when it is trusted, keeps the model's otherwise.
final Assimilation _trustTheSensor = Assimilation.of((context) {
  for (final input in context.from('tank.level')) {
    if (input.quality == ReadingQuality.bad) continue;
    context.world.setResource<_Tank>(_Tank(input.quantity.value));
  }
});

ExternalStateInput _level(double metres, {ReadingQuality? quality}) =>
    ExternalStateInput.quantity(
      'tank.level',
      Quantity(metres, Unit.meter),
      sourceTime: metres,
      quality: quality ?? ReadingQuality.good,
      kind: ReadingKind.measured,
    );

/// The levels fed at each step of the recorded run: nothing at step 1, a
/// bad reading at step 2, which the assimilation passes over.
final Map<int, List<ExternalStateInput>> _fed = <int, List<ExternalStateInput>>{
  0: <ExternalStateInput>[_level(1.25)],
  2: <ExternalStateInput>[_level(9, quality: ReadingQuality.bad)],
  3: <ExternalStateInput>[_level(1.5), _level(1.75)],
};

EngineLoop _loop() {
  final loop = EngineLoop(input: InputState())
    ..world.setResource<_Tank>(const _Tank(0));
  loop.addAssimilation('test.tank', _trustTheSensor);
  return loop;
}

void main() {
  test('an assimilation sees each step\'s inputs, and the tape keeps them', () {
    final loop = _loop();
    final recorder = InputTapeRecorder(seed: 0);
    loop.recorders.add(recorder);
    var step = 0;
    loop.onStepInput((input) {
      for (final reading in _fed[step] ?? const <ExternalStateInput>[]) {
        input.feedExternal(reading);
      }
      step++;
    });
    final levels = <double>[];
    for (var i = 0; i < 4; i++) {
      loop.runSteps(1);
      levels.add(loop.world.resource<_Tank>()!.level);
    }
    // Mutation: drop the quality check and step 2 reads 9.
    expect(levels, <double>[1.25, 1.25, 1.25, 1.75]);
    final frames = recorder.tape.frames;
    expect(frames[0].external, _fed[0]);
    expect(frames[1].external, isEmpty);
    expect(frames[3].external, _fed[3]);

    // Played back into a loop nobody feeds, the run is the same run.
    final replay = _loop()..playback = InputTapePlayback(recorder.tape);
    final replayed = <double>[];
    for (var i = 0; i < 4; i++) {
      replay.runSteps(1);
      replayed.add(replay.world.resource<_Tank>()!.level);
    }
    expect(replayed, levels);
  });

  test('a tape writes its external inputs beside its frames and requires '
      'them', () {
    final tape = InputTape(
      seed: 1,
      frames: <InputFrame>[
        InputFrame(external: _fed[0]!),
        const InputFrame(),
        InputFrame(external: _fed[3]!),
      ],
    );
    final json = jsonDecode(jsonEncode(tape.toJson())) as Map<String, Object?>;
    expect(json['requires'], <String>['externalInputs']);
    expect(json['frames'], <Object?>[<String, Object?>{}, {}, {}]);
    expect(
      (json['externalInputs']! as List<Object?>).map(
        (e) => (e! as Map)['step'],
      ),
      <int>[0, 2, 2],
    );
    final back = InputTape.fromJson(json);
    expect(back.frames[2].external, _fed[3]);
    expect(back.frames[1].external, isEmpty);
  });

  test('a tape refuses an external input past its last frame', () {
    expect(
      () => InputTape.fromJson(<String, Object?>{
        'seed': 0,
        'frames': <Object?>[<String, Object?>{}],
        'externalInputs': <Object?>[
          <String, Object?>{'step': 3, 'source': 'a', 'value': 1},
        ],
      }),
      throwsA(isA<InputTapeFormatException>()),
    );
  });

  group('a run', () {
    test('lifts the external inputs to its top level and back', () {
      final run = _run();
      final json = jsonDecode(jsonEncode(run.toJson())) as Map<String, Object?>;
      expect(json['version'], 5);
      expect((json['tape']! as Map).containsKey('externalInputs'), isFalse);
      expect(json['externalInputs'], hasLength(4));
      expect(json['probes'], hasLength(2));
      final back = Demo.fromJson(json);
      expect(back.tape.frames[0].external, _fed[0]);
      expect(back.tape.frames[3].external, _fed[3]);
      expect(back.probes, run.probes);
      expect(back.unknown, isEmpty);
    });

    test('the fixture with external frames opens and replays its inputs', () {
      final run = Demo.fromJson(
        jsonDecode(File('test/fixtures/v5/external.f3drun').readAsStringSync())
            as Map<String, Object?>,
      );
      expect(run.steps, 4);
      expect(run.tape.frames[0].external.single.quantity.value, 1.25);
      expect(run.tape.frames[2].external.single.quality, ReadingQuality.bad);
      expect(run.tape.frames[3].external, hasLength(2));
      expect(run.probes.map((p) => p.probe), <String>['tank', 'tank']);
      final loop = _loop()..playback = InputTapePlayback(run.tape);
      loop.runSteps(run.steps);
      expect(loop.world.resource<_Tank>()!.level, 1.75);
    });
  });
}

/// The run the fixture `test/fixtures/v5/external.f3drun` was minted from.
Demo _run() => Demo(
  level: 'assets/levels/plant.json',
  levelHash: 'feedf00d',
  start: const Snapshot(<String, Object?>{}),
  tape: InputTape(
    seed: 0,
    frames: <InputFrame>[
      for (var step = 0; step < 4; step++)
        InputFrame(external: _fed[step] ?? const <ExternalStateInput>[]),
    ],
  ),
  buildStamp: 'fixture-external',
  checkpoints: DigestTrace(every: 2),
  simulation: SimulationVersion.engineOnly,
  probes: <ProbeReading>[
    ProbeReading(
      probe: 'tank',
      step: 1,
      value: <double>[1.25],
      unit: Unit.meter,
    ),
    ProbeReading(
      probe: 'tank',
      step: 4,
      value: <double>[1.75],
      unit: Unit.meter,
    ),
  ],
);

/// Writes the fixture: `dart run test/external_state_test.dart mint`, once.
void mint() => File('test/fixtures/v5/external.f3drun').writeAsStringSync(
  '${const JsonEncoder.withIndent('  ').convert(_run().toJson())}\n',
);
