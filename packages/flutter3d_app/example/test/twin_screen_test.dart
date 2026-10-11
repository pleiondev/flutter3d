/// The twin's screen on a device that draws nothing: the source's reading
/// reaches the panel through the probes, and the transport pauses, scrubs
/// and goes live again.
///
///     flutter test test/twin_screen_test.dart
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_app_example/src/twin/open_meteo.dart';
import 'package:flutter3d_app_example/src/twin/rest_poller.dart';
import 'package:flutter3d_app_example/twin_main.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

Future<void> _refreshes(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

void main() {
  testWidgets('the measured air reaches the panel, and the history scrubs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    var polls = 0;
    // The answer is held back until the run has stepped without it, so
    // there is a past before the first reading to scrub back to.
    final answer = Completer<void>();
    final source = RestPoller(
      uri: openMeteoUri(latitude: 52.52, longitude: 13.41),
      read: readOpenMeteo,
      client: MockClient((_) async {
        polls++;
        await answer.future;
        return http.Response(
          jsonEncode(<String, Object?>{
            'current': <String, Object?>{
              'time': '2026-10-11T12:00',
              'temperature_2m': 21.5,
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TwinScreen(
          source: source,
          device: DeviceSettings(
            device: FakeBackend(),
            presenter: _noPresenter,
          ),
        ),
      ),
    );
    await tester.pump();
    // A second at 60 Hz: ten steps at the twin's rate, the air as it began.
    await _refreshes(tester, 60);
    expect(polls, 1);
    expect(find.text('Air, measured: 15.0 °C'), findsOneWidget);
    expect(find.textContaining('waiting'), findsOneWidget);
    answer.complete();
    await _refreshes(tester, 30);
    expect(find.text('Air, measured: 21.5 °C'), findsOneWidget);
    expect(find.textContaining('Water, modelled: 15.'), findsOneWidget);
    expect(find.textContaining('taken 12:00 UTC'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await _refreshes(tester, 2);
    expect(find.text('Live'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNotNull);
    slider.onChanged!(slider.min);
    await _refreshes(tester, 2);
    // The scrub went back to before the first reading arrived.
    expect(find.text('Air, measured: 15.0 °C'), findsOneWidget);

    // Live again: the present is put back, and the next step publishes it.
    await tester.tap(find.text('Live'));
    await _refreshes(tester, 10);
    expect(find.text('Air, measured: 21.5 °C'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
