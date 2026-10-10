import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';

void main() {
  test('the two profiles say what they promise', () {
    // Mutation: make `accurate` bit-exact, and a server would verify a
    // laboratory's run by a replay that cannot agree.
    expect(SimulationProfile.deterministic.isBitExact, isTrue);
    expect(SimulationProfile.deterministic.usesDoublePrecision, isFalse);
    expect(SimulationProfile.deterministic.allowsAdaptiveSteps, isFalse);
    expect(SimulationProfile.accurate.isBitExact, isFalse);
    expect(SimulationProfile.accurate.usesDoublePrecision, isTrue);
    expect(SimulationProfile.accurate.allowsAdaptiveSteps, isTrue);
  });

  test('the wire names are written down, not taken from Dart', () {
    expect(SimulationProfile.deterministic.name, 'deterministic');
    expect(SimulationProfile.accurate.name, 'accurate');
    expect(SimulationProfile.deterministic.toJson(), 'deterministic');
    expect(
      SimulationProfile.parse('accurate'),
      same(SimulationProfile.accurate),
    );
    expect(SimulationProfile.values, <SimulationProfile>[
      SimulationProfile.deterministic,
      SimulationProfile.accurate,
    ]);
  });

  test('an unknown name is refused, not read as the default', () {
    expect(
      () => SimulationProfile.parse('fast'),
      throwsA(isA<Flutter3dFormatException>()),
    );
  });

  test('the set is open: a profile of its own is a value like these', () {
    // A later release may add one, and so may an outside package; what
    // decides a question is a capability, never which profile it is.
    const reference = SimulationProfile(
      'reference',
      isBitExact: true,
      usesDoublePrecision: true,
      allowsAdaptiveSteps: false,
    );
    expect(reference.isBitExact, isTrue);
    expect(reference, isNot(SimulationProfile.deterministic));
    expect(
      const SimulationProfile(
        'deterministic',
        isBitExact: true,
        usesDoublePrecision: false,
        allowsAdaptiveSteps: false,
      ),
      SimulationProfile.deterministic,
    );
    expect(
      SimulationProfile.parse(
        'reference',
        known: <SimulationProfile>[...SimulationProfile.values, reference],
      ),
      reference,
    );
  });
}
