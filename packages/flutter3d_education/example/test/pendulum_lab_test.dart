/// The pendulum laboratory's simulation, without a window: on the accurate
/// profile, stepped only when time is handed to it, and measuring the
/// period its series gives.
///
///     flutter test test/pendulum_lab_test.dart
library;

import 'package:chemlab/src/pendulum_lab.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the laboratory runs on the accurate profile', () {
    final loop = pendulumSimulation(null).loop;
    expect(loop.profile, SimulationProfile.accurate);
    expect(loop.simulationVersion.profile, SimulationProfile.accurate);
  });

  test('manual time: nothing moves until time is handed to it', () {
    final loop = pendulumSimulation(null).loop;
    final clock = ManualTime();
    loop.frame(
      clock.elapsed(
        FrameSpan(from: Duration.zero, to: const Duration(seconds: 1)),
      ),
    );
    expect(loop.step, 0);
    clock.advance(loop.stepSeconds * 3);
    loop.frame(
      clock.elapsed(FrameSpan(from: Duration.zero, to: Duration.zero)),
    );
    expect(loop.step, 3);
    final angle = loop.published.probe(PendulumLab.angleProbe)!;
    expect(angle.unit, Unit.radian);
    // Released at 0.1 rad and swinging back towards the vertical.
    expect(angle.value.single, inExclusiveRange(0.0, PendulumLab.releasedAt));
  });

  test('over a hundred periods it swings at the series period, to 1e-4', () {
    final loop = pendulumSimulation(null).loop;
    final series = PendulumLab.seriesPeriod();
    // A hundred periods and a little more, so the 201st crossing is in.
    loop.runSteps((series * 100.5 / loop.stepSeconds).ceil());
    final period = loop.published.probe(PendulumLab.periodProbe)!;
    expect(period.unit, Unit.second);
    expect(
      (period.value.single - series).abs() / series,
      lessThan(1e-4),
      reason: 'measured ${period.value.single} s against $series s',
    );
    // Mutation: run the loop on the deterministic profile, and the XPBD
    // step's damping takes the swing and misses the period by 4.6e-4.
  });
}
