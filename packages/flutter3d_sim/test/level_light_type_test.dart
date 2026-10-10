/// A level light's type: an open set with the format's own words.
///
///     dart test test/level_light_type_test.dart
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('every type reads back from the word a document writes for it', () {
    // Mutation: write `toString()` or a Dart identifier into the file, and a
    // rename here changes every saved level.
    for (final type in LevelLightType.values) {
      expect(LevelLightType.fromWireName(type.wireName), same(type));
      final light = LevelLight(type: type);
      expect(LevelLight.fromJson(light.toJson()).type, same(type));
    }
    expect(LevelLightType.values.map((t) => t.wireName), <String>[
      'directional',
      'point',
      'spot',
    ]);
  });

  test('a word that is no type is refused, naming the ones there are', () {
    expect(LevelLightType.fromWireName('area'), isNull);
    expect(
      () => LevelLight.fromJson(<String, Object?>{'type': 'area'}),
      throwsA(
        isA<LevelFormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"area"'), contains('directional, point, spot')),
        ),
      ),
    );
  });
}
