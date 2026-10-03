/// A brush's place in the draw order, as a level document says it — `P7`.
///
///     dart test test/brush_draw_order_test.dart
///
/// The engine has had `MeshNode.drawOrder` since the order between nodes was
/// written, and the level format had no word for it: a stripe painted on a
/// floor of the same stone fought the floor pixel by pixel, and the only fix
/// was to patch the node after loading. What is pinned here: the word is read
/// and written back, a document without it keeps its bytes, a number the
/// renderer cannot order by is refused, a batch is split by it, and an edit
/// of it alone is a look-only edit, patched into a running game without a
/// timeline branch.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Map<String, Object?> _floor() => <String, Object?>{
  'at': <double>[0, -0.5, 0],
  'size': <double>[20, 1, 20],
  'material': 'stone',
};

Map<String, Object?> _stripe([Map<String, Object?> extra = const {}]) =>
    <String, Object?>{
      'at': <double>[0, 0.01, 0],
      'size': <double>[1, 0.02, 20],
      'material': 'stone',
      'solid': false,
      ...extra,
    };

Map<String, Object?> _document(Map<String, Object?> stripe) =>
    <String, Object?>{
      'version': 1,
      'name': 'yard',
      'materials': <String, Object?>{
        'stone': <String, Object?>{
          'color': <double>[0.5, 0.5, 0.5, 1.0],
        },
      },
      'brushes': <Object?>[_floor(), stripe],
      'lights': <Object?>[
        <String, Object?>{
          'type': 'point',
          'at': <double>[0, 3, 0],
          'color': <double>[1, 1, 1],
        },
      ],
    };

void main() {
  group('the document', () {
    test('a brush with an order keeps it through a round trip', () {
      // Mutation: leave `drawOrder` out of `Brush.toJson` — the stripe comes
      // back at nought and is drawn under the floor half the time.
      final brush = Brush.fromJson(_stripe(const {'drawOrder': 3}));
      expect(brush.drawOrder, 3);

      final again = Brush.fromJson(brush.toJson());
      expect(again.drawOrder, 3);
      expect(brush.toJson()['drawOrder'], 3);
    });

    test('a brush built in code with an order writes it', () {
      final brush = Brush(
        centre: Vector3.zero(),
        size: Vector3.all(1.0),
        drawOrder: -4,
      );
      expect(brush.toJson()['drawOrder'], -4);
    });

    test('a document without it keeps its bytes and its digest', () {
      // Mutation: write `drawOrder` whether or not it is nought — every level
      // ever saved grows a key per brush and digests to something new, so
      // every recorded run of it stops replaying.
      final level = Level.fromJson(_document(_stripe()));
      final brushes = level.toJson()['brushes']! as List<Object?>;
      for (final brush in brushes) {
        expect(
          (brush! as Map<String, Object?>).containsKey('drawOrder'),
          isFalse,
        );
      }
      expect(
        Level.fromJson(level.toJson()).digestHex,
        Level.fromJson(_document(_stripe())).digestHex,
      );
      expect(
        Level.fromJson(_document(_stripe(const {'drawOrder': 0}))).digestHex,
        isNot(
          Level.fromJson(_document(_stripe(const {'drawOrder': 1}))).digestHex,
        ),
      );
    });
  });

  group('the validator', () {
    List<LevelIssue> orderIssues(int order) =>
        LevelValidator(registry: EntityRegistry(const <EntityKind>[]))
            .validate(Level.fromJson(_document(_stripe({'drawOrder': order}))))
            .where((LevelIssue issue) => issue.message.contains('drawOrder'))
            .toList();

    test('refuses an order the renderer cannot hold', () {
      // Mutation: drop the range check — 200 loads, the engine clamps it to
      // 127, and two brushes the author put in an order draw as a tie.
      expect(orderIssues(200), hasLength(1));
      expect(orderIssues(200).single.severity, LevelIssueSeverity.error);
      expect(orderIssues(-129), hasLength(1));
    });

    test('takes both ends of the range', () {
      expect(orderIssues(Brush.maxDrawOrder), isEmpty);
      expect(orderIssues(Brush.minDrawOrder), isEmpty);
    });
  });

  test('a batch is split by the order, and carries it', () {
    // Mutation: drop the order from `BrushGeometry`'s batch key. Floor and
    // stripe share a material and become one surface, one node, one place
    // in the order.
    final level = Level.fromJson(_document(_stripe(const {'drawOrder': 2})));
    final surfaces = const BrushGeometry(cullHiddenFaces: false).build(level);

    expect(
      <int>[for (final surface in surfaces) surface.drawOrder]..sort(),
      <int>[0, 2],
    );
  });

  group('an edit of the order alone', () {
    final before = Level.fromJson(_document(_stripe()));
    final after = Level.fromJson(_document(_stripe(const {'drawOrder': 2})));

    test('is look-only to the diff', () {
      // Mutation: compare brushes whole in `diffLevel` — the edit lands in
      // `simulation`, and the running game branches its timeline to redraw
      // a stripe.
      final diff = diffLevel(before, after);
      expect(diff.simulation, isEmpty);
      expect(diff.presentationOnly, isTrue);
      expect(diff.brushOrder, <int>[1]);
      expect(diff.isEmpty, isFalse);
    });

    test('and to a patch', () {
      // Mutation: count any brush row in `LevelPatch._diff` as simulation.
      final patch = LevelPatch.between(before, after);
      final result = patch.applyTo(before);
      expect(result, isA<LevelPatched>());
      final diff = (result as LevelPatched).diff;
      expect(diff.simulation, isEmpty);
      expect(diff.brushOrder, <int>[1]);
    });

    test('but not with anything else changed on the same brush', () {
      final moved = Level.fromJson(
        _document(
          _stripe(const {
            'drawOrder': 2,
            'at': <double>[3, 0.01, 0],
          }),
        ),
      );
      final diff = diffLevel(before, moved);
      expect(diff.simulation, <String>['brushes']);
      expect(diff.brushOrder, isEmpty);

      final patched =
          LevelPatch.between(before, moved).applyTo(before) as LevelPatched;
      expect(patched.diff.simulation, <String>['brushes']);
      expect(patched.diff.brushOrder, isEmpty);
    });
  });
}
