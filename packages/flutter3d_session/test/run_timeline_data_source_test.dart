/// `edu-05`: a twin's bound value recorded into a [DataSourceTrace] beside
/// the ordinary tape, and a "what if" branched at the exact step `rp-02`'s
/// own [RunTimeline.releaseAt] already rewinds live state to — not a second
/// rewind mechanism, the same one, with the trace branched alongside it
/// rather than threaded invisibly through it.
///
///     flutter test test/run_timeline_data_source_test.dart
///
/// The toy below is `run_timeline_test.dart`'s own `_Toy`, with one field
/// added: `temperature`, a value this test drives from a
/// [DataSourceRegistry] the same way a joystick axis already drives `x` —
/// `edu-00` §9's own "input to the tape", recorded every step it is read.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:test/test.dart';

const GameAction _fire = GameAction('fire');

final class _Twin {
  _Twin(int seed) : dice = GameRandom(seed);

  final GameRandom dice;
  double x = 0.0;
  int shots = 0;
  int rolls = 0;
  double temperature = 0.0;

  void step(InputState input, double boundTemperature) {
    x += input.moveAxis.x;
    if (input.pressed(_fire)) {
      shots++;
      rolls += dice.nextInt(1000);
    }
    temperature = boundTemperature;
  }

  Snapshot save() => Snapshot(<String, Object?>{
    'x': x,
    'shots': shots,
    'rolls': rolls,
    'random': dice.state,
    'temperature': temperature,
  });

  void restore(Snapshot snapshot) {
    final data = snapshot.data;
    x = data.number('x');
    shots = data.integer('shots');
    rolls = data.integer('rolls');
    dice.state = data.integer('random');
    temperature = data.number('temperature');
  }

  String get state => '$x/$shots/$rolls/${dice.state}';
}

void _play(InputState input, int step) {
  input.setStickAxis(step % 3 == 0 ? 1.0 : -0.5, 0.0);
  if (step % 11 == 0) input.press(_fire);
  if (step % 11 == 4) input.release(_fire);
}

double _sample(EduDataSource source, int step) {
  final payload = source.sample(step)! as Map<String, Object?>;
  return payload['temperature']! as double;
}

void main() {
  test(
    'a bound value is recorded per step, and a what-if branched at the '
    'step RunTimeline rewound to diverges after it without touching the '
    'trace it branched from',
    () {
      final registry = DataSourceRegistry(<String, EduDataSource>{
        'lathe-broker': SamplerDataSource(
          (step) => <String, Object?>{'temperature': 20.0 + step * 0.1},
        ),
      });
      final trace = DataSourceTrace();

      final toy = _Twin(7);
      final input = InputState();
      final rewind = RewindBuffer(stepsPerSecond: 60, history: 10.0);

      // `stepSim` is what `releaseAt` calls internally to reconstruct live
      // state — it samples whatever the registry currently holds, which is
      // the whole mechanism: swap the registry before releasing, and the
      // reconstructed state (and everything played after it) sees the
      // swap. It does not touch `trace` — `trace` is this test's own
      // record of what actually happened, kept separately on purpose (see
      // the module doc).
      var replaySteps = 0;
      final timeline = RunTimeline(
        rewind: rewind,
        input: input,
        stepSim: (dt) {
          final value = _sample(registry['lathe-broker']!, replaySteps);
          toy.step(input, value);
          replaySteps++;
        },
        restore: toy.restore,
      );

      // Five seconds of real play, recording both the ordinary tape (via
      // `rewind`, exactly as `run_timeline_test.dart` does) and the bound
      // value (via `trace`, `edu-05`'s own addition) at every step.
      for (var step = 0; step < 300; step++) {
        _play(input, step);
        rewind.recorder.record(input);
        input.beginStep();
        if (rewind.keyframeDue) rewind.keyframe(toy.save());
        final value = _sample(registry['lathe-broker']!, step);
        toy.step(input, value);
        trace.record(step, <String, Object?>{'temperature': value});
        input.endStep();
      }

      final recordedBeforeBranch = trace.toJson();

      // The what-if: three seconds back, and `rp-02`'s own `releaseAt` —
      // already proven in `run_timeline_test.dart` to land exactly where an
      // independent replay would — relocates the live twin there and keeps
      // playing from that point, not bouncing back to it.
      final point = timeline.preview(3.0)!;
      timeline.releaseAt(point);
      expect(
        timeline.history.last,
        isA<TimelineBranched>().having((c) => c.step, 'step', point.step),
      );

      // The source is swapped only now — after the branch point is settled,
      // not before — and the branch trace is built by playing thirty more
      // steps for real, reading the swapped source exactly as the original
      // loop above read the un-swapped one.
      registry.replace('lathe-broker', const SamplerDataSource(_hotOverride));
      final branch = DataSourceTrace();
      for (var s = point.step + 1; s <= point.step + 30; s++) {
        _play(input, s);
        final value = _sample(registry['lathe-broker']!, s);
        toy.step(input, value);
        branch.record(s, <String, Object?>{'temperature': value});
      }

      expect(toy.temperature, 90.0, reason: 'the override, not the sampler');
      for (var s = point.step + 1; s <= point.step + 30; s++) {
        expect(branch.valueAt(s), <String, Object?>{'temperature': 90.0});
        expect(branch.valueAt(s), isNot(trace.valueAt(s)));
      }

      // What "without touching the trace it branched from" actually means:
      // the original, recorded before any of the above, reads back
      // identically after it — the branch is a second object, played
      // forward from the same point, not a rewrite of the first.
      expect(trace.toJson(), recordedBeforeBranch);
    },
  );
}

Object? _hotOverride(int step) => <String, Object?>{'temperature': 90.0};
