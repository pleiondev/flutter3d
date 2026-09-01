/// How long since the last frame.
///
///     flutter test test/frame_clock_test.dart
///
/// Five applications had written this out and disagreed about the first frame
/// — three said a sixtieth of a second, in three different spellings, and one
/// said nought.
library;

import 'package:clock/clock.dart' show Clock;
import 'package:fake_async/fake_async.dart' show FakeAsync;
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void main() {
  test('the first frame is nought, because nothing has happened yet', () {
    // A sixtieth is a guess about a machine nobody has measured: at launch the
    // application has run for no time at all, and a simulation advanced by an
    // assumed frame advances through a world the player has not been shown.
    expect(FrameClock().secondsSince(_ms(0)), 0.0);
    expect(
      FrameClock().secondsSince(_ms(4000)),
      0.0,
      reason: 'a ticker that starts late is still on its first frame',
    );
  });

  test('and the second is the distance between them', () {
    final clock = FrameClock()..secondsSince(_ms(1000));

    expect(clock.secondsSince(_ms(1016)), closeTo(0.016, 1e-9));
  });

  test('and a ticker handing out zero is still a first frame', () {
    // **The bug the five copies were one frame away from.** They compared
    // against `Duration.zero`, and a ticker may legitimately hand that out — at
    // which point the frame after it is measured from nought, and the clock
    // reports however long the ticker has been running as one frame.
    final clock = FrameClock()..secondsSince(Duration.zero);

    expect(
      clock.secondsSince(_ms(16)),
      closeTo(0.016, 1e-9),
      reason: 'the frame at zero was not taken as the first one',
    );
  });

  test('and it does not clamp a long frame', () {
    // A window that was dragged or a laptop that was shut. Refusing it is the
    // simulation's business — `GameLoop` refuses it and says how much it took —
    // and a clock that quietly shortened it would leave everything reading it
    // in disagreement with everything reading the loop.
    final clock = FrameClock()..secondsSince(_ms(0));

    expect(clock.secondsSince(_ms(3000)), closeTo(3.0, 1e-9));
  });

  test('elapsed is the sum of what was handed out', () {
    // Not the ticker's own elapsed: a fog that alternates and a torch that
    // flickers have to agree exactly with what everything else this frame was
    // told, including on the first frame, which was nought.
    final clock = FrameClock();
    var sum = 0.0;
    for (var frame = 1; frame <= 10; frame++) {
      sum += clock.secondsSince(_ms(frame * 16));
    }

    expect(clock.elapsed, closeTo(sum, 1e-12));
    expect(
      clock.elapsed,
      closeTo(9 * 0.016, 1e-9),
      reason: 'the first frame contributed time nobody lived through',
    );
  });

  test('frames a second are smoothed rather than reported raw', () {
    // The raw number is unreadable: one long frame in sixty makes a counter
    // jump to a figure that was true for a sixtieth of a second.
    final clock = FrameClock();
    for (var frame = 0; frame <= 200; frame++) {
      clock.secondsSince(_ms(frame * 16));
    }
    expect(clock.fps, closeTo(62.5, 1.0));

    // One frame four times as long moves it a little, not all the way.
    clock.secondsSince(_ms(200 * 16 + 64));

    expect(
      clock.fps,
      greaterThan(50.0),
      reason: 'one slow frame threw the counter at the reader',
    );
    expect(
      clock.fps,
      lessThan(62.5),
      reason: 'a slow frame has to show up at all',
    );
  });

  test('tick reads the wall, not the ticker', () {
    // What a ticker passes its callback is the frame's scheduled time. Under
    // GPU load frames get scheduled in pairs, and the timestamps step by a whole
    // interval, then by almost nothing, then by a whole interval again — while
    // the callbacks themselves keep arriving one frame apart. A clock that
    // subtracts the timestamps reports the stagger as if it were real; one that
    // reads the wall reports the frames as they were lived.
    FakeAsync().run((async) {
      final byTimestamp = FrameClock();
      final byWall = FrameClock();
      final staggered = <double>[];
      final lived = <double>[];

      // Timestamps 0, 33, 33, 66, 66 ms — pairs — at wall 0, 16, 32, 48, 64.
      for (var frame = 0; frame < 5; frame++) {
        final scheduled = _ms(((frame + 1) ~/ 2) * 33);
        staggered.add(byTimestamp.secondsSince(scheduled));
        lived.add(byWall.tick());
        async.elapse(_ms(16));
      }

      expect(staggered.sublist(1), [
        closeTo(0.033, 1e-9),
        0.0,
        closeTo(0.033, 1e-9),
        0.0,
      ], reason: 'the ticker path reports the pairing as motion');
      expect(
        lived.sublist(1),
        everyElement(closeTo(0.016, 1e-9)),
        reason: 'the wall path reports the frames as they were lived',
      );
    });
  });

  test('and tick takes a clock of its own', () {
    // For a driver that owns time — a golden run, a replay — rather than the
    // ambient one.
    var micros = 0;
    final clock = FrameClock(
      wallClock: Clock(() => DateTime.fromMicrosecondsSinceEpoch(micros)),
    );

    clock.tick();
    micros += 20000;

    expect(clock.tick(), closeTo(0.020, 1e-9));
  });

  test('and starting again makes the next frame a first frame', () {
    // For a game that was away — a level loading, a window not drawing — where
    // the honest answer is the one it gave at launch.
    final clock = FrameClock()
      ..secondsSince(_ms(0))
      ..secondsSince(_ms(16));
    final elapsed = clock.elapsed;

    clock.reset();

    expect(clock.secondsSince(_ms(9000)), 0.0);
    expect(
      clock.elapsed,
      elapsed,
      reason: 'the time it was away was counted as time that passed',
    );
  });
}
