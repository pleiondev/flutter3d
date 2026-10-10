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

  test('a display that drops from 120 to 60 Hz is measured within a '
      'second', () {
    // A laptop leaving its charger, a phone in low-power mode. Mutation: the
    // 1 % a refresh it cooled by — about 690 refreshes, eleven seconds of a
    // cap computed for a screen twice as fast.
    final cadence = FrameCadence();
    var at = Duration.zero;
    for (var i = 0; i < 120; i++) {
      cadence.due(at);
      at += _period;
    }
    expect(cadence.refreshRate, closeTo(120.0, 0.1));
    const slow = Duration(microseconds: 16667);
    for (var i = 0; i < 60; i++) {
      cadence.due(at);
      at += slow;
    }
    expect(cadence.refreshRate, closeTo(60.0, 0.1));
  });

  test('and one late frame does not halve it', () {
    final cadence = FrameCadence();
    var at = Duration.zero;
    for (var i = 0; i < 300; i++) {
      // Every fiftieth refresh is missed: a gap of two periods.
      at += i % 50 == 49 ? _period * 2 : _period;
      cadence.due(at);
    }
    expect(cadence.refreshRate, closeTo(120.0, 0.1));
  });

  test('a cap of nought or less, or not a number, is no cap', () {
    // `cap` was a public field and a view wrote its setting into it
    // unchecked; nought divided the refresh rate by zero. Mutation: keep
    // the assert alone — in a release build the interval is infinite.
    for (final off in <double>[0.0, -30.0, double.nan, double.infinity]) {
      final cadence = FrameCadence(refreshRate: 120.0)..cap = off;
      expect(cadence.cap, isNull, reason: '$off');
      expect(cadence.interval, 1, reason: '$off');
      expect(FrameCadence(cap: off, refreshRate: 120.0).cap, isNull);
    }
  });

  test('a refresh rate of nought or less is one not known', () {
    final cadence = FrameCadence(cap: 60.0, refreshRate: 0.0);
    expect(cadence.refreshRate, 60.0, reason: 'measured, or sixty');
    expect(cadence.interval, 1);
    cadence.refreshRate = -1.0;
    expect(cadence.refreshRate, 60.0);
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
