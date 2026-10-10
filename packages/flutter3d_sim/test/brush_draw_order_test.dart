/// A brush's place in the draw order, said in the level document — `P7`.
///
///     dart test test/brush_draw_order_test.dart
///
/// The engine has had `MeshNode.drawOrder` since the render order was added,
/// and a level could not ask for it: a water surface that has to come after
/// the floor under it, a decal brush laid over a wall, were reachable from
/// Dart and unauthorable. Pinned here: the number is read, a brush that does
/// not ask says nothing about it, and two brushes of one stone that draw at
/// different places are two batches, because a batch draws as one.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Brush _wall(double x, {int drawOrder = 0}) => Brush(
  center: Vector3(x, 2.0, 0.0),
  size: Vector3(4.0, 4.0, 1.0),
  material: 'wall',
  drawOrder: drawOrder,
);

void main() {
  test('a document that says nothing draws at nought', () {
    final brush = Brush.fromJson(const <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[1.0, 1.0, 1.0],
    });
    expect(brush.drawOrder, 0);
    expect(brush.toJson().containsKey('drawOrder'), isFalse);
  });

  test('a number is read and written back', () {
    // Mutation: drop `drawOrder` from `Brush.toJson` — a level saved from
    // the editor forgets its water's order.
    final brush = Brush.fromJson(const <String, Object?>{
      'at': <double>[0.0, 0.0, 0.0],
      'size': <double>[1.0, 1.0, 1.0],
      'drawOrder': 2,
    });
    expect(brush.drawOrder, 2);
    // Built in code, so there is no document for the write to pass through
    // and the number has to come from the field.
    expect(_wall(0.0, drawOrder: 2).toJson()['drawOrder'], 2);
  });

  test('two walls of one stone at different places in the order are two '
      'batches, each saying its place', () {
    // Mutation: leave the order out of `builderFor`'s key — one surface,
    // which can say only one order.
    final surfaces = const BrushGeometry().build(
      Level(brushes: <Brush>[_wall(0.0), _wall(20.0, drawOrder: 1)]),
    );
    expect(surfaces, hasLength(2));
    expect(surfaces.map((BrushSurface it) => it.drawOrder).toSet(), <int>{
      0,
      1,
    });
  });

  test('a breach keeps the order of the brush it cut', () {
    // Mutation: drop `drawOrder` from the pieces `subtractBox` builds — the
    // wall round a breach falls back to nought.
    final cut = subtractBox(
      _wall(0.0, drawOrder: 3),
      Aabb3.minMax(Vector3(-0.5, 1.5, -1.0), Vector3(0.5, 2.5, 1.0)),
    );
    expect(cut, isNotEmpty);
    expect(cut.every((Brush it) => it.drawOrder == 3), isTrue);
  });
}
