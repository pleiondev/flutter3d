/// A patch of a world: what a level changes of the world it is played in.
///
///     dart test test/world_properties_patch_test.dart
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final game = WorldProperties(gravity: Vector3(0.0, -24.0, 0.0));

  test('lays what it names over a world and leaves the rest', () {
    final moon = WorldPropertiesPatch.fromJson(<String, Object?>{
      'gravity': 1.62,
    });
    final played = moon.over(game);
    // Mutation: lay the patch over the standard world instead of the one
    // handed in — the air stays, but at the standard pressure, not the game's.
    expect(played.gravity.y, closeTo(-1.62, 1e-6));
    expect(played.airPressure, game.airPressure);
    expect(moon.gravity!.y, closeTo(-1.62, 1e-6));
    expect(moon.wind, isNull);
    expect(WorldPropertiesPatch.empty.over(game), same(game));
  });

  test('writes back what it read, keys it does not know included', () {
    final json = <String, Object?>{'airPressure': 300, 'stepRate': 120};
    // Mutation: write `toJson` from the typed fields, and both `300` (an
    // integer) and `stepRate` are lost.
    expect(WorldPropertiesPatch.fromJson(json).toJson(), json);
    expect(
      WorldPropertiesPatch.fromJson(json),
      WorldPropertiesPatch.fromJson(<String, Object?>{...json}),
    );
  });

  test('refuses a value a world would refuse, naming the key', () {
    expect(
      () => WorldPropertiesPatch.fromJson(<String, Object?>{'airPressure': -1}),
      throwsA(
        isA<WorldPropertiesFormatException>().having(
          (e) => e.message,
          'message',
          contains('airPressure'),
        ),
      ),
    );
    expect(
      () => WorldPropertiesPatch(airTemperature: 0.0),
      throwsArgumentError,
    );
  });
}
