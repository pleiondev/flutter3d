/// The twin, without a window: what it makes of the real source's answer,
/// how the poller hands it to the loop, what the model does between
/// readings, and its history on the tape and under the timeline.
///
///     flutter test test/twin_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_app_example/src/twin/open_meteo.dart';
import 'package:flutter3d_app_example/src/twin/rest_poller.dart';
import 'package:flutter3d_app_example/src/twin/site_twin.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show RunTimeline, ScrubMoved;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What Open-Meteo answers for the current weather, trimmed to the fields
/// the twin reads.
String _answer({String time = '2026-10-11T12:00', double celsius = 13.4}) =>
    jsonEncode(<String, Object?>{
      'latitude': 52.52,
      'longitude': 13.42,
      'current_units': <String, Object?>{
        'time': 'iso8601',
        'interval': 'seconds',
        'temperature_2m': '°C',
      },
      'current': <String, Object?>{
        'time': time,
        'interval': 900,
        'temperature_2m': celsius,
      },
    });

/// A reading of the air, as the poller would have queued it.
ExternalStateInput _air(double celsius, {double at = 0}) =>
    ExternalStateInput.quantity(
      SiteTwin.airSource,
      Quantity(celsius, Unit.celsius),
      sourceTime: at,
      quality: ReadingQuality.good,
      kind: ReadingKind.measured,
    );

/// A loop at the twin's rate with the twin in it, fed from [queue].
(EngineLoop, SiteTwin) _twin(List<ExternalStateInput> queue) {
  final loop = EngineLoop(
    input: InputState(),
    timing: const WorldTiming(stepRate: SiteTwin.stepRate),
  );
  final twin = SiteTwin.install(
    loop,
    readings: () {
      final taken = List<ExternalStateInput>.of(queue);
      queue.clear();
      return taken;
    },
  );
  return (loop, twin);
}

double _celsius(EngineLoop loop, String probe) =>
    loop.published.probe(probe)!.value.single;

void main() {
  group('Open-Meteo', () {
    test('its current temperature is one measured reading in °C', () {
      final reading = readOpenMeteo(jsonDecode(_answer()), receivedTime: 99)!;
      expect(reading.source, SiteTwin.airSource);
      expect(reading.quantity.value, 13.4);
      expect(reading.unit, Unit.celsius);
      expect(reading.kind, ReadingKind.measured);
      expect(reading.quality, ReadingQuality.good);
      expect(
        reading.sourceTime,
        DateTime.utc(2026, 10, 11, 12).millisecondsSinceEpoch / 1000,
      );
      expect(reading.receivedTime, 99);
    });

    test('an answer without the temperature is no reading', () {
      expect(
        readOpenMeteo(<String, Object?>{'error': true}, receivedTime: 0),
        isNull,
      );
    });

    test('the address asks for the current temperature at the site', () {
      final uri = openMeteoUri(latitude: 59.94, longitude: 30.31);
      expect(uri.host, 'api.open-meteo.com');
      expect(uri.queryParameters['current'], 'temperature_2m');
      expect(uri.queryParameters['latitude'], '59.94');
    });
  });

  group('the poller', () {
    test(
      'queues what each poll reads, once per time the source took it',
      () async {
        var celsius = 10.0;
        var time = '2026-10-11T12:00';
        final poller = RestPoller(
          uri: Uri.parse('https://example.test/now'),
          read: readOpenMeteo,
          client: MockClient(
            (_) async => http.Response(
              _answer(time: time, celsius: celsius),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            ),
          ),
          clock: () => 5,
        );
        await poller.pollOnce();
        // The source has not taken a new one: the same answer is not fed twice.
        await poller.pollOnce();
        expect(poller.take().map((r) => r.quantity.value), <double>[10]);
        celsius = 11;
        time = '2026-10-11T12:15';
        await poller.pollOnce();
        final taken = poller.take();
        expect(taken.single.quantity.value, 11);
        expect(taken.single.receivedTime, 5);
        expect(poller.take(), isEmpty);
        expect(poller.lastError, isNull);
      },
    );

    test('a failed poll queues nothing and says why', () async {
      final poller = RestPoller(
        uri: Uri.parse('https://example.test/now'),
        read: readOpenMeteo,
        client: MockClient((_) async => http.Response('busy', 503)),
      );
      await poller.pollOnce();
      expect(poller.take(), isEmpty);
      expect(poller.lastError, contains('503'));
    });
  });

  group('the model', () {
    test('the air is what the sensor says, the tank follows it', () {
      final queue = <ExternalStateInput>[_air(30)];
      final (loop, _) = _twin(queue);
      loop.runSteps(1);
      expect(_celsius(loop, SiteTwin.airProbe), closeTo(30, 1e-9));
      final first = _celsius(loop, SiteTwin.waterProbe);
      // One time constant later the tank has closed 1 − 1/e of the gap.
      loop.runSteps((SiteTwin.timeConstant * SiteTwin.stepRate).round());
      final start = SiteTwin.startCelsius;
      final expected = 30 - (30 - start) * 0.36788;
      expect(_celsius(loop, SiteTwin.waterProbe), closeTo(expected, 0.05));
      expect(_celsius(loop, SiteTwin.waterProbe), greaterThan(first));
    });

    test('a bad reading leaves the air as the model had it', () {
      final queue = <ExternalStateInput>[_air(30)];
      final (loop, _) = _twin(queue);
      loop.runSteps(1);
      queue.add(
        ExternalStateInput.quantity(
          SiteTwin.airSource,
          const Quantity(90, Unit.celsius),
          quality: ReadingQuality.bad,
        ),
      );
      loop.runSteps(1);
      expect(_celsius(loop, SiteTwin.airProbe), closeTo(30, 1e-9));
    });
  });

  group('the history', () {
    test('is on the tape, and replays without the source', () {
      final queue = <ExternalStateInput>[_air(25, at: 1)];
      final (loop, _) = _twin(queue);
      final recorder = InputTapeRecorder(seed: 0);
      loop.recorders.add(recorder);
      loop.runSteps(20);
      queue.add(_air(5, at: 2));
      loop.runSteps(30);
      final live = _celsius(loop, SiteTwin.waterProbe);
      expect(recorder.tape.frames[0].external.single.quantity.value, 25);
      expect(recorder.tape.frames[20].external.single.quantity.value, 5);

      // Nobody feeds this one: the tape is its whole input.
      final (replay, _) = _twin(<ExternalStateInput>[]);
      replay.playback = InputTapePlayback.tape(recorder.tape);
      replay.runSteps(50);
      expect(_celsius(replay, SiteTwin.waterProbe), live);
    });

    test('the timeline scrubs back to a reading and returns', () {
      final queue = <ExternalStateInput>[_air(25)];
      final (loop, twin) = _twin(queue);
      final rewind = twin.keepHistory();
      final timeline = RunTimeline(rewind: rewind, loop: loop);
      loop.runSteps(40);
      final before = _celsius(loop, SiteTwin.airProbe);
      queue.add(_air(5));
      loop.runSteps(40);
      double water() =>
          loop.world.get<MaterialStateComponent>(twin.tank)!.state.temperature;
      final now = water();
      expect(_celsius(loop, SiteTwin.airProbe), closeTo(5, 1e-9));

      timeline.pause();
      expect(timeline.scrubTo(30), isA<ScrubMoved>());
      expect(_celsius(loop, SiteTwin.airProbe), before);
      expect(loop.published.probe(SiteTwin.waterProbe)!.step, lessThan(31));

      expect(water(), isNot(now));

      // The present comes back as it was. What was published stays the
      // scrub's until the next step runs, so the world is asked here.
      timeline.returnToPresent();
      expect(water(), now);
      // Mutation: feed the queue from a system rather than through the
      // loop's step input. The reading lands on no tape, and the scrub
      // back to step 30 replays a run without the 25 °C air.
    });
  });
}
