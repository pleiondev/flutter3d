/// The four answers a brush may give about the shadow passes.
///
///     dart test test/brush_shadow_casting_test.dart
///
/// The engine has had four since `ShadowCastingMode` was written and the level
/// format had two, so the two a document could not ask for were the two it
/// most needed: `doubleSided` for a wall one brush thick, whose lit face and
/// dark face are a metre apart, and `shadowsOnly` for a proxy that casts
/// without being drawn. Both were reachable from Dart and unauthorable.
///
/// What is pinned here is the whole of that: the word is read, the boolean
/// still means what it meant, an unknown word is refused rather than quietly
/// taken as `off`, the document keeps its own spelling through a save, and a
/// batch is still the smallest thing that can answer — a `doubleSided` wall
/// does not share one with a solid pillar of the same stone.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Map<String, Object?> _document(Map<String, Object?> extra) => <String, Object?>{
  'at': <double>[0.0, 2.0, 0.0],
  'size': <double>[4.0, 4.0, 1.0],
  'material': 'wall',
  ...extra,
};

void main() {
  group('reading the word', () {
    test('a document that says nothing casts, as it always did', () {
      final brush = Brush.fromJson(_document(const <String, Object?>{}));

      expect(brush.shadowCasting, ShadowCasting.on);
      expect(brush.castsShadow, isTrue);
    });

    test('the boolean still says off, and now says it as a mode', () {
      // Mutation: drop the `flagOr('castsShadow')` fallback from
      // `Brush.fromJson` and every fence in every level starts casting again.
      final brush = Brush.fromJson(
        _document(const <String, Object?>{'castsShadow': false}),
      );

      expect(brush.shadowCasting, ShadowCasting.off);
      expect(brush.castsShadow, isFalse);
    });

    test('and the word wins where a document gives both', () {
      // Mutation: read the boolean after the word rather than as its fallback
      // — a wall that asked for both faces gets one of them.
      final brush = Brush.fromJson(
        _document(const <String, Object?>{
          'castsShadow': true,
          'shadowCasting': 'shadowsOnly',
        }),
      );

      expect(brush.shadowCasting, ShadowCasting.shadowsOnly);
    });

    test('a wall may ask for both its faces', () {
      final brush = Brush.fromJson(
        _document(const <String, Object?>{'shadowCasting': 'doubleSided'}),
      );

      expect(brush.shadowCasting, ShadowCasting.doubleSided);
      expect(
        brush.castsShadow,
        isTrue,
        reason: 'the boolean asks whether it casts at all, and it does',
      );
    });

    test('a proxy casts without being drawn, and reads as casting', () {
      final brush = Brush.fromJson(
        _document(const <String, Object?>{'shadowCasting': 'shadowsOnly'}),
      );

      expect(brush.shadowCasting, ShadowCasting.shadowsOnly);
      expect(brush.castsShadow, isTrue);
    });

    test('and a word nobody knows is refused with the four in it', () {
      // Mutation: read the mode with `textOrNull` and map the unknown to
      // `on`. A misspelt `doubleSided` then loads as an ordinary wall and the
      // seam it was written for leaks light with nothing said.
      expect(
        () => Brush.fromJson(
          _document(const <String, Object?>{'shadowCasting': 'both'}),
        ),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException it) => it.toString(),
            'the refusal',
            allOf(
              contains('both'),
              contains('doubleSided'),
              contains('shadowsOnly'),
            ),
          ),
        ),
      );
    });
  });

  group('writing it back', () {
    test('a brush that casts says nothing about it', () {
      // Mutation: `whenAbsent: true` on the `shadowCasting` field. Every
      // document in the repository grows a line per brush saying the default.
      final written = Brush.fromJson(
        _document(const <String, Object?>{}),
      ).toJson();

      expect(written.containsKey('shadowCasting'), isFalse);
      expect(written.containsKey('castsShadow'), isFalse);
    });

    test('a fence goes on writing the boolean it was written with', () {
      final written = Brush.fromJson(
        _document(const <String, Object?>{'castsShadow': false}),
      ).toJson();

      expect(written['castsShadow'], false);
      expect(
        written.containsKey('shadowCasting'),
        isFalse,
        reason: 'the boolean says this one exactly; a word would be noise',
      );
    });

    test('a wall built in code with a mode spells it out', () {
      // Mutation: `whenAbsent: false` on the `shadowCasting` field. The
      // editor saves a level and the mode is gone from the document.
      final written = Brush(
        centre: Vector3.zero(),
        size: Vector3.all(1.0),
        shadowCasting: ShadowCasting.doubleSided,
      ).toJson();

      expect(written['shadowCasting'], 'doubleSided');
      expect(
        written.containsKey('castsShadow'),
        isFalse,
        reason: 'it casts, so the boolean has nothing to add',
      );
    });

    test('and a document that spelled off out is given back as it came', () {
      // Mutation: `whenAbsent: !castsShadow` on the boolean, ignoring what the
      // source said. Reading and writing back a level then adds a redundant
      // `castsShadow: false` beside every word that already said it.
      final written = Brush.fromJson(
        _document(const <String, Object?>{'shadowCasting': 'off'}),
      ).toJson();

      expect(written['shadowCasting'], 'off');
      expect(written.containsKey('castsShadow'), isFalse);
    });
  });

  group('batching', () {
    Level walls(ShadowCasting other) => Level(
      brushes: <Brush>[
        Brush(
          centre: Vector3(0.0, 2.0, 0.0),
          size: Vector3(4.0, 4.0, 1.0),
          material: 'wall',
        ),
        Brush(
          centre: Vector3(20.0, 2.0, 0.0),
          size: Vector3(4.0, 4.0, 1.0),
          material: 'wall',
          shadowCasting: other,
        ),
      ],
    );

    test('two walls of one stone that agree are one batch', () {
      expect(
        const BrushGeometry().build(walls(ShadowCasting.on)),
        hasLength(1),
      );
    });

    test('and two that disagree are two, whatever the boolean says', () {
      // The finding the boolean could not carry: `on` and `doubleSided` both
      // read as "it casts", so a key built from `castsShadow` puts them in one
      // batch and the batch can only answer once.
      //
      // Mutation: key `builderFor` by `brush.castsShadow ? 1 : 0` again — this
      // drops to one surface and the wall stops casting from both faces.
      final surfaces = const BrushGeometry().build(
        walls(ShadowCasting.doubleSided),
      );

      expect(surfaces, hasLength(2));
      expect(
        surfaces.map((BrushSurface it) => it.shadowCasting).toSet(),
        <ShadowCasting>{ShadowCasting.on, ShadowCasting.doubleSided},
      );
      expect(
        surfaces.every((BrushSurface it) => it.castsShadow),
        isTrue,
        reason: 'both of them cast; that is what the boolean could see',
      );
    });
  });
}
