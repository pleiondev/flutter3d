/// A level material that names a file, and a document that keeps what it does
/// not understand.
///
///     dart test test/level_material_test.dart
///
/// A `LevelMaterial` is eight fields — colour, roughness, metallic, a glow, a
/// tiling density and three maps — and that smallness is deliberate: it is the
/// vocabulary a level author blocks a room out in. The one key added here does
/// not grow it; it points at a document written in the engine's own material
/// format instead, and this package never reads that document. What it must do
/// is carry the key through a read and a write without losing it, which is the
/// property every level already on disk depends on for its own keys.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

void main() {
  test('a material naming a .fmat keeps the name through a save', () {
    final read = LevelMaterial.fromJson(<String, Object?>{
      'fmat': 'assets/materials/steel.fmat',
      'texelsPerMeter': 2.0,
    });

    expect(read.fmat, 'assets/materials/steel.fmat');
    expect(read.toJson()['fmat'], 'assets/materials/steel.fmat');
    expect(
      read.texelsPerMeter,
      2.0,
      reason: 'tiling is geometry and belongs to the level either way',
    );
  });

  test('and a material given one in Dart writes it into a fresh document', () {
    // **The half `writeThrough` cannot do by itself, and the reason the field
    // is listed rather than merely parsed.** A key the document already carried
    // is copied through untouched whether this build knows it or not — the test
    // below measures that — so reading and saving preserves `fmat` either way.
    // Setting one does not: a material an editor built, or one whose file an
    // editor changed, has nothing in its source to copy.
    //
    // Mutation: drop the `WriteThroughField('fmat', ...)` line from `toJson` —
    // the key never reaches the document and this fails, while the round trip
    // above goes on passing.
    expect(
      LevelMaterial(fmat: 'assets/materials/brass.fmat').toJson()['fmat'],
      'assets/materials/brass.fmat',
    );
    expect(
      LevelMaterial(
        fmat: 'assets/materials/brass.fmat',
        source: <String, Object?>{'fmat': 'assets/materials/steel.fmat'},
      ).toJson()['fmat'],
      'assets/materials/brass.fmat',
      reason: 'a changed file name must replace the one the document carried',
    );
  });

  test('and a build that has never heard of a key still writes it back', () {
    // The claim the key rests on, measured rather than assumed. `writeThrough`
    // copies what it does not recognise, so a level authored against a later
    // version of this package survives a round trip through this one — which
    // is why `fmat` could be added at all without every older editor quietly
    // stripping it out of the levels it opens.
    //
    // Mutation: have `writeThrough` emit only the fields it was given — the
    // unknown key disappears and this fails.
    final written = LevelMaterial.fromJson(<String, Object?>{
      'roughness': 0.4,
      'somethingOnlyNextYearKnows': <String, Object?>{'depth': 3},
    }).toJson();

    expect(written['somethingOnlyNextYearKnows'], <String, Object?>{
      'depth': 3,
    });
    expect(written['roughness'], 0.4);
    expect(
      written.containsKey('fmat'),
      isFalse,
      reason: 'a material with nothing to say must go on saying nothing',
    );
  });

  test('a material instance keeps its values and the version they were '
      'written for', () {
    // The loader lifts the values through the material's updates; the level
    // keeps the version as the document said it, so a level written for an
    // older material is not read as if it were current.
    //
    // Mutation: drop `materialVersion` from `toJson`, and the save forgets
    // which version the values belong to.
    final document = <String, Object?>{
      'fmat': 'assets/materials/hatch.fmat',
      'parameters': <String, Object?>{
        'ink': <num>[0.1, 0.2, 0.3],
        'roughness': 0.5,
      },
      'materialVersion': 2,
    };
    final read = LevelMaterial.fromJson(document);
    expect(read.parameters, <String, List<double>>{
      'ink': <double>[0.1, 0.2, 0.3],
      'roughness': <double>[0.5],
    });
    expect(read.materialVersion, 2);
    expect(read.toJson(), document);

    final built = LevelMaterial(
      parameters: const <String, List<double>>{
        'inkColor': <double>[1, 0, 0],
      },
      materialVersion: 3,
    ).toJson();
    expect(built['parameters'], <String, Object?>{
      'inkColor': <double>[1, 0, 0],
    });
    expect(built['materialVersion'], 3);

    final plain = LevelMaterial.fromJson(const <String, Object?>{});
    expect(plain.parameters, isEmpty);
    expect(plain.materialVersion, isNull);
    expect(plain.toJson().containsKey('parameters'), isFalse);
    expect(plain.toJson().containsKey('materialVersion'), isFalse);
  });

  test('a material instance that is not one is refused, saying why', () {
    expect(
      () => LevelMaterial.fromJson(const <String, Object?>{
        'parameters': <String, Object?>{'ink': 'red'},
      }),
      throwsA(isA<LevelFormatException>()),
    );
    expect(
      () =>
          LevelMaterial.fromJson(const <String, Object?>{'materialVersion': 0}),
      throwsA(isA<LevelFormatException>()),
    );
  });
}
