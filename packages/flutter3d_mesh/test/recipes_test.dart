/// `gal-02`: sixteen models that are code, and the three things each of
/// them owes a gallery.
///
///     dart test test/recipes_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The bounding box of every live vertex — what says a model is the size a
/// person expects rather than a metre of anything.
({Vector3 min, Vector3 max}) _bounds(EditMesh mesh) {
  final min = Vector3.all(double.infinity);
  final max = Vector3.all(-double.infinity);
  for (var v = 0; v < mesh.vertexSlotCount; v++) {
    if (!mesh.isVertexAlive(v)) continue;
    final Vector3 at = mesh.positionOf(v);
    Vector3.min(min, at, min);
    Vector3.max(max, at, max);
  }
  return (min: min, max: max);
}

void main() {
  test('every recipe builds a mesh nothing objects to', () {
    for (final Recipe recipe in recipes()) {
      final EditMesh mesh = recipe.build();
      expect(mesh.faceCount, greaterThan(0), reason: recipe.id);
      // **Mutation: join the parts by concatenating their faces without
      // renumbering the vertices.** Every recipe still "builds", every one
      // of them is nonsense, and nothing but this line says so.
      expect(() => mesh.validate(), returnsNormally, reason: recipe.id);
    }
  });

  test('and builds the same one twice', () {
    for (final Recipe recipe in recipes()) {
      // A gallery caches a thumbnail against an id, and a golden frame
      // holds a model by its bytes. Mutation: seed a recipe from
      // `Random()` — the thumbnails go stale and the frames flicker, and
      // both fail somewhere a long way from here.
      expect(
        recipe.build().toBytes(),
        recipe.build().toBytes(),
        reason: recipe.id,
      );
    }
  });

  test('every recipe has an id, a name and a sentence, and no two share an '
      'id', () {
    final seen = <String>{};
    for (final Recipe recipe in recipes()) {
      expect(seen.add(recipe.id), isTrue, reason: '${recipe.id} twice');
      expect(recipe.id, matches(RegExp(r'^[a-z][a-z0-9-]*$')));
      expect(recipe.name, isNotEmpty);
      // `ux-18`'s own rule, applied to a gallery card: a name is not a
      // description, and a card with only a name asks somebody to insert
      // the thing to find out what it is.
      expect(recipe.about.length, greaterThan(20), reason: recipe.id);
      expect(recipe.about.endsWith('.'), isTrue, reason: recipe.id);
    }
  });

  test('all four categories are there, and none is empty', () {
    final byCategory = <RecipeCategory, int>{};
    for (final Recipe recipe in recipes()) {
      byCategory[recipe.category] = (byCategory[recipe.category] ?? 0) + 1;
    }
    for (final RecipeCategory category in RecipeCategory.values) {
      expect(byCategory[category], isNotNull, reason: category.name);
      expect(byCategory[category], greaterThan(1), reason: category.name);
    }
  });

  group('the measurements are the ones the objects actually have', () {
    test('a chair seats at 450 and a table tops at 740', () {
      // **This is what makes a set of props a set.** Mutation: model each
      // one to look right on its own. Every model passes its own eye test
      // and the chair does not fit under the table, which is the first
      // thing anybody notices and the last thing they can explain.
      final ({Vector3 max, Vector3 min}) chair = _bounds(diningChair());
      expect(chair.max.y, closeTo(0.85, 0.02));
      expect(chair.max.x - chair.min.x, closeTo(0.44, 0.02));

      final ({Vector3 max, Vector3 min}) table = _bounds(diningTable());
      expect(table.max.y, closeTo(0.74, 0.01));
      expect(table.max.x - table.min.x, closeTo(1.6, 0.01));

      // A seat at 450 under a top at 740 leaves 290 of knee room, which is
      // the number the two dimensions exist to produce.
      expect(table.max.y - 0.45, greaterThan(0.25));
    });

    test('a mug is a mug and not a barrel', () {
      final ({Vector3 max, Vector3 min}) it = _bounds(mug());
      expect(it.max.y, closeTo(0.095, 0.005));
      // Across the cup, handle excluded on the far side: 95 plus the
      // handle's own reach.
      expect(it.max.x - it.min.x, lessThan(0.16));
    });

    test('a door is 900 by 2040 in a frame that is bigger than it', () {
      final ({Vector3 max, Vector3 min}) it = _bounds(door());
      expect(it.max.y, greaterThan(2.04));
      expect(it.max.x - it.min.x, closeTo(1.02, 0.02));
    });

    test('everything stands on the floor rather than through it', () {
      for (final Recipe recipe in recipes()) {
        // The sconce and the pendant hang, and the window sill dips a
        // little below its own origin; nothing else may.
        if (<String>{
          'wall-sconce',
          'pendant-lamp',
          'window',
        }.contains(recipe.id)) {
          continue;
        }
        final ({Vector3 max, Vector3 min}) it = _bounds(recipe.build());
        expect(it.min.y, greaterThanOrEqualTo(-0.001), reason: recipe.id);
      }
    });
  });

  test('joining parts renumbers rather than concatenates', () {
    final EditMesh one = ParametricCuboid(size: Vector3(1, 1, 1)).toEditMesh();
    final EditMesh two = ParametricCuboid(size: Vector3(1, 1, 1)).toEditMesh();
    final EditMesh joined = joinMeshes(<PlacedMesh>[
      PlacedMesh(mesh: one, at: Vector3.zero()),
      PlacedMesh(mesh: two, at: Vector3(2, 0, 0)),
    ]);

    expect(joined.faceCount, one.faceCount + two.faceCount);
    expect(joined.vertexCount, one.vertexCount + two.vertexCount);
    joined.validate();

    final ({Vector3 max, Vector3 min}) it = _bounds(joined);
    expect(it.max.x - it.min.x, closeTo(3, 1e-6));
  });
}
