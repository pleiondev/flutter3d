/// A run file that carries the loop's changes and each step's event digest.
///
///     dart test test/demo_loop_changes_test.dart
///
/// The version is the part with a promise on it: a run whose loop changes
/// alter the simulation is refused by a build that cannot replay them, and
/// every other run opens on the builds it opened on before.
library;

import 'dart:convert';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

Demo _demo({
  List<LoopChange> loopChanges = const <LoopChange>[],
  EventTrace? events,
}) => Demo(
  level: 'assets/levels/crypt.json',
  levelHash: 'deadbeef',
  start: const Snapshot(<String, Object?>{'random': 7}),
  tape: InputTape(
    seed: 7,
    frames: <InputFrame>[for (var i = 0; i < 10; i++) InputFrame()],
  ),
  buildStamp: 'test-build',
  checkpoints: DigestTrace(every: 5),
  loopChanges: loopChanges,
  events: events,
);

Demo _trip(Demo demo) => Demo.fromJson(
  jsonDecode(jsonEncode(demo.toJson())) as Map<String, Object?>,
);

void main() {
  test('loop changes and the event trace survive the file', () {
    final events = EventTrace()
      ..observe(2, count: 1, digest: 0xabc)
      ..observe(7, count: 3, digest: 0x1234);
    final read = _trip(
      _demo(
        loopChanges: const <LoopChange>[
          LoopTimeScale(step: 0, scale: 0.5),
          LoopPluginChange(
            PluginDisabled(step: 4, plugin: 'fire', affectsSimulation: true),
          ),
        ],
        events: events,
      ),
    );
    expect(read.loopChanges.map((c) => c.toJson()), <Map<String, Object?>>[
      const LoopTimeScale(step: 0, scale: 0.5).toJson(),
      const LoopPluginChange(
        PluginDisabled(step: 4, plugin: 'fire', affectsSimulation: true),
      ).toJson(),
    ]);
    expect(read.events?.divergenceFrom(events), isNull);
    expect(read.events?.steps, <int>[2, 7]);
  });

  test('3 is written only when a loop change alters the simulation', () {
    // Mutation: write `formatVersion` whenever there are loop changes. A
    // slowed-down run, which every older build replays correctly, would be
    // refused by all of them.
    expect(_demo().toJson()['version'], 1);
    expect(
      _demo(
        loopChanges: const <LoopChange>[LoopTimeScale(step: 3, scale: 0.25)],
        events: EventTrace()..observe(1, count: 1, digest: 1),
      ).toJson()['version'],
      1,
      reason: 'a time scale and an event trace only pace and check the run',
    );
    expect(
      _demo(
        loopChanges: const <LoopChange>[
          LoopPluginChange(
            PluginEnabled(step: 2, plugin: 'bloom', affectsSimulation: false),
          ),
        ],
      ).toJson()['version'],
      1,
      reason: 'a view plugin switched changes nothing a replay checks',
    );
    expect(
      _demo(
        loopChanges: const <LoopChange>[LoopStepRate(step: 1, rate: 120.0)],
      ).toJson()['version'],
      3,
    );
    expect(Demo.formatVersion, 3);
  });

  test('a run written before loop changes still reads, with none', () {
    final old = _demo().toJson()
      ..remove('loopChanges')
      ..remove('events')
      ..['version'] = 2;
    final read = Demo.fromJson(old);
    expect(read.loopChanges, isEmpty);
    expect(read.events, isNull);
  });

  test('a loop change this build does not know is refused with a sentence', () {
    final json = _demo().toJson()
      ..['loopChanges'] = <Object?>[
        <String, Object?>{'kind': 'gravityFlip', 'step': 1},
      ];
    expect(
      () => Demo.fromJson(json),
      throwsA(
        isA<DemoFormatException>().having(
          (e) => e.message,
          'message',
          contains('gravityFlip'),
        ),
      ),
    );
  });
}
