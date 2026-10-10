/// A level names what it changes of its world beside its fog — its gravity,
/// its air, its wind, its medium — or says nothing.
///
///     dart test test/level_gravity_test.dart
///
/// Saying nothing has to stay nothing: a level that names no world plays in
/// the game's own, and writes no `world` back.
library;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A game's own world: the platformer's, falling at 24.
final WorldProperties _game = WorldProperties(
  gravity: Vector3(0.0, -24.0, 0.0),
);

void main() {
  test('a level on the Moon says so, and reads back the same', () {
    // Mutation: write `world` whenever it is absent too — fails because the
    // document that never named one comes back with an empty one in it.
    final moon = Level.fromJson(<String, Object?>{
      'name': 'sea of tranquility',
      'world': <String, Object?>{
        'gravity': <double>[0.0, -1.62, 0.0],
      },
    });
    expect(moon.worldOver(_game).gravity.y, closeTo(-1.62, 1e-6));
    expect(
      Level.fromJson(moon.toJson()).worldOver(_game).gravity.y,
      closeTo(-1.62, 1e-6),
    );

    final plain = <String, Object?>{'version': 1, 'name': 'yard'};
    final level = Level.fromJson(plain);
    expect(level.world, isEmpty);
    expect(level.worldOver(_game), _game);
    expect(level.toJson().containsKey('world'), isFalse);
    expect(level.digestHex, Level.fromJson(plain).digestHex);
  });

  test("a level before version 4 said its gravity as a number, and still "
      'reads', () {
    final old = Level.fromJson(<String, Object?>{
      'version': 3,
      'name': 'sea of tranquility',
      'gravity': 1.62,
    });
    expect(old.world, <String, Object?>{'gravity': 1.62});
    expect(old.worldOver(_game).gravity.y, closeTo(-1.62, 1e-6));
    // Only what the level names: the game's air is still the game's.
    expect(old.worldOver(_game).airPressure, _game.airPressure);
  });

  test('no gravity is a level; a negative one is not', () {
    expect(
      Level.fromJson(<String, Object?>{
        'gravity': 0,
      }).worldOver(_game).gravityMagnitude,
      0.0,
    );
    expect(
      () => Level.fromJson(<String, Object?>{'gravity': -9.0}),
      throwsA(isA<LevelFormatException>()),
    );
    expect(
      () => Level.fromJson(<String, Object?>{'gravity': 'low'}),
      throwsA(isA<LevelFormatException>()),
    );
    expect(
      () => Level.fromJson(<String, Object?>{
        'version': 4,
        'world': <String, Object?>{'airPressure': -1},
      }),
      throwsA(isA<LevelFormatException>()),
    );
  });

  test('a level filled with a plugin\'s medium needs that plugin', () {
    final reef = Level.fromJson(<String, Object?>{
      'version': 4,
      'world': <String, Object?>{'medium': 'reef.brine'},
    });
    final materials = MaterialCatalog.builtIn();
    expect(
      () => reef.worldOver(_game, materials: materials),
      throwsA(
        isA<UnknownMaterialException>().having(
          (UnknownMaterialException e) => e.plugin,
          'plugin',
          'reef',
        ),
      ),
    );
    final sea = Level.fromJson(<String, Object?>{
      'version': 4,
      'world': <String, Object?>{'medium': Materials.seawater.id},
    });
    expect(
      sea.worldOver(_game, materials: materials).mediumDensity(materials),
      Materials.seawater.density,
    );
  });

  test("changing a level's world changes its simulation", () {
    // Mutation: leave `world` out of `diffLevel`'s simulation list — fails
    // because the edit is then patched into a running scene as if it were a
    // colour, and the bodies already falling keep the old gravity.
    final before = Level.fromJson(<String, Object?>{'name': 'yard'});
    final after = Level.fromJson(<String, Object?>{
      'name': 'yard',
      'gravity': 1.62,
    });
    expect(diffLevel(before, after).simulation, contains('world'));
    expect(diffLevel(before, before).simulation, isEmpty);
  });
}
