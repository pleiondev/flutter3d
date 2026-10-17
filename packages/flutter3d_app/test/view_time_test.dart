/// Where a view's time comes from (`Flutter3dView.time`, `Scene3D.time`):
/// the source answers for every frame drawn, the loop steps by its answer,
/// and the view never resets a source it was handed.
///
///     flutter test test/view_time_test.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

/// A view on [time], counting its loop's steps into [steps] and its frames'
/// seconds into [seconds].
Widget _view({
  required TimeSource? time,
  required List<int> steps,
  required List<double> seconds,
  bool continuous = true,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 32,
    height: 24,
    child: Flutter3dView(
      time: time,
      device: DeviceSettings(device: FakeBackend(), presenter: _noPresenter),
      view: ViewSettings(continuous: continuous, warmUp: false),
      onCreated: (engine) => engine.loop.addSystem(
        'test.count',
        LoopPhase.rules,
        (context) => steps.add(context.step),
      ),
      onFrame: (EngineFrame frame) => seconds.add(frame.seconds),
    ),
  ),
);

/// Pumps [count] refreshes of a 60 Hz display.
Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

double _sum(List<double> values) => values.fold(0.0, (a, b) => a + b);

void main() {
  testWidgets('a world at half speed steps half as often', (tester) async {
    // Mutation: step the loop by the ticker's own gaps, as the view did
    // before it had a source. Sixty refreshes then bring a second, and the
    // loop runs sixty steps rather than thirty.
    final steps = <int>[];
    final seconds = <double>[];
    await tester.pumpWidget(
      _view(time: TimeSource.scaled(0.5), steps: steps, seconds: seconds),
    );
    await tester.pump();
    await _refreshes(tester, 60);
    expect(_sum(seconds), closeTo(0.5, 0.02));
    expect(steps.length, inInclusiveRange(28, 31));
    // Every refresh is still drawn: the source slows the world, not the
    // picture.
    expect(seconds.length, greaterThanOrEqualTo(59));
  });

  testWidgets('a hand-moved clock steps only when it is moved', (tester) async {
    // Mutation: hand `FrameCadence` no source. The view's frames then step
    // by the display's clock, and the world runs with nobody pressing
    // "step".
    final time = ManualTime();
    final steps = <int>[];
    final seconds = <double>[];
    await tester.pumpWidget(_view(time: time, steps: steps, seconds: seconds));
    await tester.pump();
    await _refreshes(tester, 30);
    expect(steps, isEmpty);
    // Four steps' worth (within the loop's catch-up of five a frame), and a
    // hair more so the fourth is not lost to rounding.
    time.advance(4 / 60 + 1e-9);
    await _refreshes(tester, 3);
    expect(_sum(seconds), closeTo(4 / 60, 1e-6));
    expect(steps.length, 4);
    expect(time.pending, 0.0);
  });

  testWidgets('a log goes on where it was when the ticker starts again', (
    tester,
  ) async {
    // Mutation: reset the cadence (and with it the source) when the ticker
    // starts, as the view did before it had a source. The log then starts
    // again from its first timestamp, and the replay runs its first second
    // twice.
    final log = LogTime(<double>[for (var i = 0; i <= 100; i++) i * 0.01]);
    final steps = <int>[];
    final seconds = <double>[];
    await tester.pumpWidget(_view(time: log, steps: steps, seconds: seconds));
    await tester.pump();
    await _refreshes(tester, 10);
    final reached = log.position;
    expect(reached, greaterThan(5));
    await tester.pumpWidget(
      _view(time: log, steps: steps, seconds: seconds, continuous: false),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(_view(time: log, steps: steps, seconds: seconds));
    await _refreshes(tester, 5);
    expect(log.position, greaterThanOrEqualTo(reached));
    expect(log.position, lessThanOrEqualTo(reached + 6));
    expect(_sum(seconds), closeTo(log.position * 0.01, 1e-9));
  });

  testWidgets('another source takes over from the next frame', (tester) async {
    // Mutation: leave the cadence's source as it was built. The view keeps
    // stepping by the display's clock after it was handed a still one.
    final steps = <int>[];
    final seconds = <double>[];
    await tester.pumpWidget(_view(time: null, steps: steps, seconds: seconds));
    await tester.pump();
    await _refreshes(tester, 10);
    expect(steps, isNotEmpty);
    final before = steps.length;
    await tester.pumpWidget(
      _view(time: TimeSource.scaled(0.0), steps: steps, seconds: seconds),
    );
    await _refreshes(tester, 20);
    expect(steps.length, lessThanOrEqualTo(before + 1));
  });

  testWidgets('a scene of widgets runs on the source it is given', (
    tester,
  ) async {
    // Mutation: leave `time:` off the view `Scene3D` builds. Its frames
    // then bring the display's seconds, and a laboratory slowed to a tenth
    // animates at full speed.
    final seconds = <double>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 32,
          height: 24,
          child: Scene3D(
            device: DeviceSettings(
              device: FakeBackend(),
              presenter: _noPresenter,
            ),
            time: TimeSource.scaled(0.1),
            onFrame: (EngineFrame frame) => seconds.add(frame.seconds),
          ),
        ),
      ),
    );
    await tester.pump();
    await _refreshes(tester, 60);
    expect(_sum(seconds), closeTo(0.1, 0.01));
  });
}
