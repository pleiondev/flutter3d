/// A level light's type: an open set with the format's own words.
///
///     dart test test/level_light_type_test.dart
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('every type reads back from the word a document writes for it', () {
    // Mutation: write `toString()` or a Dart identifier into the file, and a
    // rename here changes every saved level.
    for (final type in LightType.values) {
      expect(LightType.byName(type.name), same(type));
      final light = LevelLight(type: type);
      expect(LevelLight.fromJson(light.toJson()).type, same(type));
    }
    expect(LightType.values.map((t) => t.name), <String>[
      'directional',
      'point',
      'spot',
      'area',
    ]);
  });

  // Mutation: write a custom kind's own name, and a level names a plugin it
  // cannot read back.
  test('a plugin\'s own kind is written as the shape it is lit as', () {
    const tube = LightType.custom('acme.tube', base: LightType.area);
    final light = LevelLight(type: tube);
    expect(light.toJson()['type'], 'area');
    expect(LevelLight.fromJson(light.toJson()).type, same(LightType.area));
  });

  test('a word that is no type is refused, naming the ones there are', () {
    expect(LightType.byName('tube'), isNull);
    expect(
      () => LevelLight.fromJson(<String, Object?>{'type': 'tube'}),
      throwsA(
        isA<LevelFormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('"tube"'), contains('directional, point, spot, area')),
        ),
      ),
    );
  });
}
