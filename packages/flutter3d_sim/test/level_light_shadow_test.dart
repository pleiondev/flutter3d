/// A level light's `castsShadow`, when the document does not name it.
///
///     dart test test/level_light_shadow_test.dart
///
/// The renderer reads the flag on the sun since 0.7.1, where it used to cast
/// the sun regardless. Two shipped levels never name the flag on their sun,
/// so an absent key has to keep meaning what it drew: a sun casts, a torch
/// does not.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('absent, a directional light casts and the others do not', () {
    // Mutation: go back to `json.flagOr('castsShadow')` with no fallback, and
    // the sun of `map_a.json` loses its shadow.
    expect(
      LevelLight.fromJson(<String, Object?>{'type': 'directional'}).castsShadow,
      isTrue,
    );
    expect(
      LevelLight.fromJson(<String, Object?>{'type': 'point'}).castsShadow,
      isFalse,
    );
    expect(
      LevelLight.fromJson(<String, Object?>{'type': 'spot'}).castsShadow,
      isFalse,
    );
  });

  test('and a sun that says false keeps saying it', () {
    final sun = LevelLight.fromJson(<String, Object?>{
      'type': 'directional',
      'castsShadow': false,
    });
    expect(sun.castsShadow, isFalse);
    expect(sun.toJson()['castsShadow'], isFalse);
  });

  test(
    'a light made in code writes the flag only when it is not the default',
    () {
      expect(
        LevelLight(type: LevelLightType.directional).toJson(),
        isNot(contains('castsShadow')),
      );
      expect(
        LevelLight(
          type: LevelLightType.directional,
          castsShadow: false,
        ).toJson(),
        containsPair('castsShadow', false),
      );
      expect(LevelLight().toJson(), isNot(contains('castsShadow')));
      expect(
        LevelLight(castsShadow: true).toJson(),
        containsPair('castsShadow', true),
      );
    },
  );
}
