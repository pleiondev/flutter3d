/// Vertex colour: linear, painted onto a whole mesh by [MeshData.withColor],
/// and reached from a colour picked on screen by [LinearColor.fromSrgb].
library;

import 'package:flutter3d_core/formats.dart' show srgbToLinear;
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// The colour stored at [index], as float32 holds it.
LinearColor _colorAt(MeshData mesh, int index) {
  final base =
      index * mesh.layout.floatsPerVertex +
      mesh.layout.floatOffsetOf(VertexLayout.color.name);
  return LinearColor(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
    mesh.vertices[base + 3],
  );
}

/// [color] as a float32 vertex stores it.
LinearColor _stored(LinearColor color) {
  final v = Vector4(color.r, color.g, color.b, color.a);
  return LinearColor(v.x, v.y, v.z, v.w);
}

void main() {
  test('withColor paints every vertex and leaves the shape alone', () {
    final cube = CuboidShape(size: Vector3.all(2.0)).build();
    const red = LinearColor(0.8, 0.1, 0.05);
    final painted = cube.withColor(red);

    expect(painted.vertexCount, cube.vertexCount);
    expect(painted.indices, same(cube.indices));
    for (var i = 0; i < painted.vertexCount; i++) {
      expect(_colorAt(painted, i), _stored(red));
    }
    // A copy: the mesh it was made from keeps its own neutral white.
    expect(_colorAt(cube, 0), LinearColor.white);
    expect(painted.computeBounds().max, cube.computeBounds().max);
  });

  test('parts painted apart keep their colours through a merge', () {
    const green = LinearColor(0.1, 0.5, 0.1);
    const brown = LinearColor(0.3, 0.2, 0.1);
    final trunk = const CylinderShape(height: 0.6).build().withColor(brown);
    final crown = const SphereShape(radius: 0.7).build().withColor(green);
    final tree = MeshData.merge(<MeshData>[trunk, crown]);

    expect(_colorAt(tree, 0), _stored(brown));
    expect(_colorAt(tree, trunk.vertexCount), _stored(green));
  });

  test('a layout with no colour gets an unchanged copy', () {
    final plain = const PlaneShape().build(layout: VertexLayout.positionNormal);
    final painted = plain.withColor(const LinearColor(1.0, 0.0, 0.0));
    expect(painted.vertices, plain.vertices);
  });

  test('a colour picked on screen comes out darker in linear, alpha kept', () {
    final grass = LinearColor.fromSrgb(0.33, 0.55, 0.24, 0.5);
    expect(grass.r, closeTo(srgbToLinear(0.33), 1e-6));
    expect(grass.g, closeTo(srgbToLinear(0.55), 1e-6));
    expect(grass.b, closeTo(srgbToLinear(0.24), 1e-6));
    expect(grass.a, 0.5);
    // Mid-grey on screen is about a fifth of the light in linear.
    expect(LinearColor.fromSrgb(0.5, 0.5, 0.5).r, closeTo(0.214, 0.001));
    expect(LinearColor.fromSrgb(0.0, 1.0, 0.0).g, 1.0);
  });
}
