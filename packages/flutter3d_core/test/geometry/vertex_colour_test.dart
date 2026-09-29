/// Vertex colour: linear, painted onto a whole mesh by [MeshData.withColor],
/// and reached from a colour picked on screen by [linearFromSrgb].
library;

import 'package:flutter3d_core/formats.dart' show linearFromSrgb, srgbToLinear;
import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Vector4 _colourAt(MeshData mesh, int index) {
  final base =
      index * mesh.layout.floatsPerVertex +
      mesh.layout.floatOffsetOf(VertexLayout.color.name);
  return Vector4(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
    mesh.vertices[base + 3],
  );
}

void main() {
  test('withColor paints every vertex and leaves the shape alone', () {
    final cube = CuboidShape(size: Vector3.all(2.0)).build();
    final red = Vector4(0.8, 0.1, 0.05, 1.0);
    final painted = cube.withColor(red);

    expect(painted.vertexCount, cube.vertexCount);
    expect(painted.indices, same(cube.indices));
    for (var i = 0; i < painted.vertexCount; i++) {
      expect(_colourAt(painted, i), red);
    }
    // A copy: the mesh it was made from keeps its own neutral white.
    expect(_colourAt(cube, 0), Vector4.all(1.0));
    expect(painted.computeBounds().max, cube.computeBounds().max);
  });

  test('parts painted apart keep their colours through a merge', () {
    final green = Vector4(0.1, 0.5, 0.1, 1.0);
    final brown = Vector4(0.3, 0.2, 0.1, 1.0);
    final trunk = const CylinderShape(height: 0.6).build().withColor(brown);
    final crown = const SphereShape(radius: 0.7).build().withColor(green);
    final tree = MeshData.merge(<MeshData>[trunk, crown]);

    expect(_colourAt(tree, 0), brown);
    expect(_colourAt(tree, trunk.vertexCount), green);
  });

  test('a layout with no colour gets an unchanged copy', () {
    final plain = const PlaneShape().build(layout: VertexLayout.positionNormal);
    final painted = plain.withColor(Vector4(1.0, 0.0, 0.0, 1.0));
    expect(painted.vertices, plain.vertices);
  });

  test('a colour picked on screen comes out darker in linear, alpha kept', () {
    final grass = linearFromSrgb(0.33, 0.55, 0.24, 0.5);
    expect(grass.x, closeTo(srgbToLinear(0.33), 1e-6));
    expect(grass.y, closeTo(srgbToLinear(0.55), 1e-6));
    expect(grass.z, closeTo(srgbToLinear(0.24), 1e-6));
    expect(grass.w, 0.5);
    // Mid-grey on screen is about a fifth of the light in linear.
    expect(linearFromSrgb(0.5, 0.5, 0.5).x, closeTo(0.214, 0.001));
    expect(linearFromSrgb(0.0, 1.0, 0.0).y, 1.0);
  });
}
