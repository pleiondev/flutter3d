/// A level carries the render settings it asks for, by slot id, as JSON.
///
///     dart test test/level_render_settings_test.dart
///
/// What an id means belongs to the addon that defined it, and a level is
/// read where there is no renderer, so the section is kept as written: an id
/// nobody here knows comes back exactly as it went in.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('the section reads and writes back unchanged', () {
    final section = <String, Object?>{
      'acme_frost.frost': <String, Object?>{'enabled': true, 'strength': 0.25},
    };
    final level = Level.fromJson(<String, Object?>{
      'name': 'cold',
      'renderSettings': section,
    });
    expect(level.renderSettings, section);
    expect(Level.fromJson(level.toJson()).renderSettings, section);

    // Mutation: write the section whenever it is absent — the document
    // that never named one comes back with an empty object, and its digest
    // moves.
    final plain = <String, Object?>{'version': 1, 'name': 'yard'};
    final quiet = Level.fromJson(plain);
    expect(quiet.renderSettings, isEmpty);
    expect(quiet.toJson().containsKey('renderSettings'), isFalse);
    expect(quiet.digestHex, Level.fromJson(plain).digestHex);
  });

  test('a section that is not an object is refused', () {
    expect(
      () => Level.fromJson(<String, Object?>{'renderSettings': 'warm'}),
      throwsA(isA<LevelFormatException>()),
    );
  });
}
