/// A path measured in metres along it, and a road laid on it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forty metres straight ahead (along -Z), then a right-angle turn right.
OpenPath _bend() => OpenPath(<Vector3>[
  Vector3(0.0, 0.0, 0.0),
  Vector3(0.0, 0.0, -40.0),
  Vector3(30.0, 0.0, -40.0),
]);

void main() {
  test('a point is found by the metres to it', () {
    final path = _bend();
    expect(path.length, 70.0);
    final at = path.pointAt(55.0);
    expect(at.x, closeTo(15.0, 1e-9));
    expect(at.z, closeTo(-40.0, 1e-9));
    expect(
      path.pointAt(-5.0).z,
      closeTo(5.0, 1e-9),
      reason: 'straight on past the start',
    );
  });

  test('the heading turns through a corner rather than snapping', () {
    final path = _bend();
    expect(path.tangentAt(10.0).z, closeTo(-1.0, 1e-9));
    final corner = path.tangentAt(40.0);
    expect(corner.x, closeTo(corner.z.abs(), 1e-9), reason: 'half way round');
    expect(path.tangentAt(60.0).x, closeTo(1.0, 1e-9));
    // Right of a road heading into the screen is +x.
    expect(path.rightAt(10.0).x, closeTo(1.0, 1e-9));
  });

  test('a ribbon lies along the road, faces up, and tiles in metres', () {
    // Mutation: wind the ribbon's triangles the other way.
    final path = _bend();
    final road = ribbon(path, from: 0.0, to: 20.0, width: 6.0, step: 5.0);
    final stride = VertexLayout.standard.floatsPerVertex;
    expect(road.vertices.length ~/ stride, 10, reason: 'five cuts, two sides');
    expect(road.indices.length, 4 * 6);

    Vector3 vertex(int i) => Vector3(
      road.vertices[i * stride],
      road.vertices[i * stride + 1],
      road.vertices[i * stride + 2],
    );
    final a = vertex(road.indices[0]);
    final b = vertex(road.indices[1]);
    final c = vertex(road.indices[2]);
    final facing = (b - a).cross(c - a);
    expect(facing.y, greaterThan(0.0), reason: 'seen from above');

    // The left edge of the first cut is three metres left of the start.
    expect(vertex(0).x, closeTo(-3.0, 1e-9));
    final uv = VertexLayout.standard.floatOffsetOf('texcoord');
    expect(road.vertices[8 * stride + uv + 1], closeTo(20.0, 1e-9));
  });
}
