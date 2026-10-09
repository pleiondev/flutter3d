/// A frame-rate cap held to an even cadence of display refreshes — `A1.5`.
///
///     dart test test/frame_cadence_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

const Duration _period = Duration(microseconds: 8333);

void main() {
  test('sixty on a 120 Hz screen is every other refresh', () {
    final cadence = FrameCadence(cap: 60.0, refreshRate: 120.0);
    final drawn = <bool>[
      for (var i = 0; i < 8; i++) cadence.due(_period * i) != null,
    ];
    // Mutation: draw whenever a sixtieth has passed on the wall. The
    // refreshes drawn then drift off the even ones.
    expect(drawn, <bool>[true, false, true, false, true, false, true, false]);
    expect(cadence.interval, 2);
    expect(cadence.skipped, 4);
    // A missed refresh counts towards the next frame, not against it.
    expect(cadence.due(_period * 11), isNotNull);
  });

  test('fifty on 120 Hz is every third refresh, never over the cap', () {
    expect(FrameCadence(cap: 50.0, refreshRate: 120.0).interval, 3);
    expect(FrameCadence(cap: 60.0, refreshRate: 59.94).interval, 1);
    expect(FrameCadence(refreshRate: 120.0).interval, 1);
  });

  test('the loop runs a frame only on a refresh the cadence draws', () {
    final loop = EngineLoop(input: InputState())
      ..cadence = FrameCadence(cap: 60.0, refreshRate: 120.0);
    final ran = <int?>[
      for (var i = 0; i < 4; i++) loop.frameAtVsync(_period * i),
    ];
    expect(ran[1], isNull);
    expect(ran[3], isNull);
    expect(ran[0], isNotNull);
    expect(ran[2], isNotNull);
    // The frame drawn is handed both refreshes' time.
    expect(loop.lastFrame, closeTo(2 * _period.inMicroseconds / 1e6, 1e-9));
  });
}
