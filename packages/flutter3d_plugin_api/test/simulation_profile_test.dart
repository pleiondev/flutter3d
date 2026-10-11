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

  group('a run recorded under a profile of its own', () {
    const reference = SimulationProfile(
      'reference',
      isBitExact: true,
      usesDoublePrecision: true,
      allowsAdaptiveSteps: false,
    );
    final recorded = const SimulationVersion(profile: reference).toJson();

    test('is read back exactly by a build that is told of it', () {
      // Mutation: drop `profiles:` from `fromJson` and the outside plugin's
      // own tape cannot be read by the plugin's own game.
      final read = SimulationVersion.fromJson(
        recorded,
        profiles: <SimulationProfile>[...SimulationProfile.values, reference],
      );
      expect(read.profile, reference);
      expect(read.refusalOn(const SimulationVersion(profile: reference)), null);
    });

    test('and by one that is not, as a promise of nothing, under its name', () {
      // Mutation: refuse the name, as `SimulationProfile.parse` does, and a
      // tape from an outside profile cannot even be opened to show its
      // poses; or give it the default's promises, and a server verifies
      // by replay a run that never promised bits.
      final read = SimulationVersion.fromJson(recorded);
      expect(read.profile.name, 'reference');
      expect(read.profile.isBitExact, isFalse);
      expect(read.profile.usesDoublePrecision, isFalse);
      expect(read.profile.allowsAdaptiveSteps, isFalse);
      // The file carries the name alone, so the name is what it is matched
      // by: a build running the profile replays it, another refuses it.
      expect(read.refusalOn(const SimulationVersion(profile: reference)), null);
      expect(read.refusalOn(const SimulationVersion()), contains('reference'));
      expect(read, const SimulationVersion(profile: reference));
    });

    test('a profile that is not a word is still refused', () {
      expect(
        () => SimulationVersion.fromJson(<String, Object?>{
          'engine': 1,
          'profile': 3,
        }),
        throwsA(isA<Flutter3dFormatException>()),
      );
    });
  });
}
