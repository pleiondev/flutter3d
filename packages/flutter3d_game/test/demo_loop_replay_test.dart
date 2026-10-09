/// A run recorded through an `EngineLoop`, with a plugin switched in the
/// middle of it, replayed from its file to the same state and the same
/// events.
///
///     flutter test test/demo_loop_replay_test.dart
///
/// On a toy whose position moves by the stick, and a "wind" plugin that
/// pushes it while on. Switching the wind off at step 20 changes every
/// step after it, so a replay that did not make the switch would part from
/// the run at the first checkpoint past 20 — which is what the mutation
/// below shows.
library;

import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Toy {
  double x = 0.0;

  Snapshot save() => Snapshot(<String, Object?>{'x': x, 'random': 0});

  void restore(Snapshot snapshot) => x = snapshot.data.number('x');
}

final class _Moved extends BusEvent {
  const _Moved(this.whole);

  final int whole;

  /// A step event is declared with its codec.
  static final EventCodec<_Moved> codec = EventCodec<_Moved>.of(
    encode: (event) => event.whole,
    decode: (data, _) => data is int ? _Moved(data) : null,
  );

  @override
  String get name => 'toy.crossed';

  @override
  void digestInto(EventDigestSink sink) => sink.add(whole);
}

/// Pushes the toy along while enabled.
final class _Wind extends Flutter3dPlugin {
  _Wind(this.toy);

  final _Toy toy;

  @override
  PluginManifest get manifest =>
      const PluginManifest(id: 'wind', apiVersion: PluginApiVersion(1, 0));

  @override
  void install(PluginHost host) {
    host.loop.addSystem('wind', LoopPhase.fields, (_) => toy.x += 0.25);
  }
}

/// [toy] stepped by a loop with the wind in it, and one part of the loop's
/// snapshots under `toy`: what a replay restores the file's start into.
EngineLoop _loopFor(_Toy toy, InputState input) =>
    EngineLoop(input: input, plugins: <Flutter3dPlugin>[_Wind(toy)])
      ..snapshots.add(
        SnapshotPart.of(
          id: 'toy',
          capture: () => toy.save().data,
          restore: (Object? data, int _) {
            if (data is Map) {
              toy.restore(Snapshot(data.cast<String, Object?>()));
            }
          },
        ),
      )
      ..events.declare<_Moved>('toy.crossed', codec: _Moved.codec)
      ..addSystem('move', LoopPhase.movers, (c) {
        final before = toy.x.floor();
        toy.x += c.dt * 60.0 * input.moveAxis.x;
        if (toy.x.floor() != before) c.publish(_Moved(toy.x.floor()));
      });

void main() {
  test('a plugin switched mid-run is switched again at the same step', () {
    final toy = _Toy();
    final input = InputState();
    final loop = _loopFor(toy, input);
    final recording = DemoRecording(
      level: 'assets/levels/toy.json',
      levelHash: 'toy',
      start: toy.save(),
      seed: 0,
      checkpointEvery: 5,
    )..attach(loop);
    loop.onStepEnd((_) => recording.observe(toy.save));

    for (var frame = 0; frame < 40; frame++) {
      input.setStickAxis(frame.isEven ? 1.0 : 0.5, 0.0);
      if (frame == 20) loop.plugins.disable('wind');
      loop.frame(1.0 / 60.0);
    }
    recording.detach();
    final demo = Demo.fromJson(
      jsonDecode(jsonEncode(recording.demo(buildStamp: 'test').toJson()))
          as Map<String, Object?>,
    );
    expect(demo.writtenVersion, 3);
    expect(
      demo.loopChanges.whereType<LoopPluginChange>().map((c) => c.step),
      <int>[0, 20],
    );
    expect(demo.events?.isEmpty, isFalse);

    // A fresh toy and loop, as a server would have them.
    final replayToy = _Toy();
    final replayed = replayDemoOnLoop(
      demo: demo,
      loop: _loopFor(replayToy, InputState()),
      part: 'toy',
    );
    expect(replayed.steps, 40);
    expect(replayed.divergence, isNull);
    expect(replayed.eventDivergence, isNull);
    expect(replayToy.x, toy.x);

    // Mutation: a replay that ignores the file's loop changes. The wind
    // keeps blowing past step 20, and the first checkpoint after says so —
    // and so, sooner, do the events.
    final ignoring = Demo.fromJson(demo.toJson()..remove('loopChanges'));
    final wrongToy = _Toy();
    final wrong = replayDemoOnLoop(
      demo: ignoring,
      loop: _loopFor(wrongToy, InputState()),
      part: 'toy',
    );
    expect(wrong.divergence?.step, 25);
    expect(wrong.eventDivergence, isNotNull);
    expect(wrong.eventDivergence!.step, greaterThanOrEqualTo(20));
  });
}
