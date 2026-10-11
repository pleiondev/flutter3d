import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  group('ExternalStateInput', () {
    test('round-trips every field, and keeps what a later build wrote', () {
      final input = ExternalStateInput.fromJson(<String, Object?>{
        'step': 4,
        'source': 'boiler.t1',
        'value': <double>[351.25],
        'unit': 'K',
        'sourceTime': 12.5,
        'receivedTime': 12.75,
        'quality': 'good',
        'kind': 'measured',
        'tag': 'line 2',
        'confidence': 0.9,
      });
      expect(input.quantity, const Quantity(351.25, Unit.kelvin));
      expect(input.quality, ReadingQuality.good);
      expect(input.kind, ReadingKind.measured);
      final written = input.toJson();
      expect(written['confidence'], 0.9);
      expect(written.containsKey('step'), isFalse);
      expect(ExternalStateInput.fromJson(written), input);
    });

    test('keeps a quality and a kind this build does not know', () {
      final input = ExternalStateInput.fromJson(<String, Object?>{
        'source': 'valve',
        'value': 0.5,
        'quality': 'substituted',
        'kind': 'interpolated',
      });
      expect(input.quality!.name, 'substituted');
      expect(ReadingQuality.values, isNot(contains(input.quality)));
      expect(input.toJson()['quality'], 'substituted');
      expect(input.toJson()['kind'], 'interpolated');
    });

    test('refuses a reading with no source or no numbers, naming it', () {
      expect(
        () => ExternalStateInput.fromJson(<String, Object?>{'value': 1}),
        throwsA(isA<PluginFormatException>()),
      );
      expect(
        () => ExternalStateInput.fromJson(<String, Object?>{
          'source': 'valve',
          'value': 'open',
        }),
        throwsA(
          isA<PluginFormatException>().having(
            (e) => e.message,
            'message',
            contains('valve'),
          ),
        ),
      );
    });
  });

  group('ProbeReading', () {
    test('round-trips, a field and all', () {
      final reading = ProbeReading(
        probe: 'tank.level',
        step: 30,
        value: <double>[1.5],
        unit: Unit.meter,
        quality: ReadingQuality.uncertain,
        field: ProbeField(
          shape: <int>[2, 2],
          values: Float32List.fromList(<double>[1, 2, 3, 4]),
          unit: Unit.kelvin,
        ),
      );
      final read = ProbeReading.fromJson(reading.toJson());
      expect(read, reading);
      expect(read.kind, ReadingKind.simulated);
      expect(read.field!.values, <double>[1, 2, 3, 4]);
      expect(read.quantity, const Quantity(1.5, Unit.meter));
    });

    test('a field holds exactly as many values as its shape', () {
      expect(
        () => ProbeField(
          shape: <int>[3],
          values: Float32List(2),
          unit: Unit.kelvin,
        ),
        throwsArgumentError,
      );
    });
  });

  test('a published state carries its probe readings across the wire', () {
    final state = PublishedState(
      step: 3,
      seconds: 0.05,
      probes: <ProbeReading>[
        ProbeReading(
          probe: 'p',
          step: 3,
          value: <double>[2],
          unit: Unit.kelvin,
        ),
      ],
    );
    final back = PublishedState.fromWire(state.toWire());
    expect(back.probes, state.probes);
    expect(back.probe('p')!.value, <double>[2]);
    expect(back.probe('q'), isNull);
    expect(
      PublishedState(step: 0, seconds: 0).toWire(),
      isNot(contains('probes')),
    );
  });

  group('SimulationVersion carries the profile', () {
    test('the default writes and describes what it did before', () {
      const version = SimulationVersion(genre: 'racing', genreVersion: 2);
      expect(version.toJson(), <String, Object?>{
        'engine': 1,
        'genre': 'racing',
        'genreVersion': 2,
      });
      expect(version.describe(), 'engine 1, racing 2');
    });

    test('another profile is written, read back and named', () {
      final accurate = SimulationVersion.engineOnly.withProfile(
        SimulationProfile.accurate,
      );
      expect(accurate.toJson()['profile'], 'accurate');
      expect(SimulationVersion.fromJson(accurate.toJson()), accurate);
      expect(accurate.describe(), 'engine 1, accurate profile');
      expect(accurate, isNot(SimulationVersion.engineOnly));
      expect(
        accurate.withPlugins(<String, int>{'fire': 2}).profile,
        SimulationProfile.accurate,
      );
      expect(
        accurate.withGenre('racing', 1).profile,
        SimulationProfile.accurate,
      );
    });

    test('a run on one profile is refused on the other, naming both', () {
      final accurate = SimulationVersion.engineOnly.withProfile(
        SimulationProfile.accurate,
      );
      expect(
        accurate.refusalOn(SimulationVersion.engineOnly),
        allOf(contains('accurate'), contains('deterministic')),
      );
      expect(accurate.refusalOn(accurate), isNull);
    });

    test('a profile this build does not know is refused, not guessed', () {
      expect(
        () => SimulationVersion.fromJson(<String, Object?>{
          'engine': 1,
          'profile': 'reference',
        }),
        throwsA(isA<PluginFormatException>()),
      );
    });
  });

  test('an assimilation made of a function calls it', () {
    final heard = <int>[];
    Assimilation.of(
      (context) => heard.add(context.step),
    ).assimilate(_Context());
    expect(heard, <int>[7]);
  });
}

final class _Context extends AssimilationContext {
  @override
  int get step => 7;

  @override
  double get dt => 1 / 60;

  @override
  List<ExternalStateInput> get inputs => const <ExternalStateInput>[];

  @override
  bool get isResimulated => false;

  @override
  SimWorld get world => throw UnimplementedError();

  @override
  void publish(BusEvent event) {}
}
