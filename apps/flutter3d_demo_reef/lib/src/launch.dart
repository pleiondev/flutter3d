/// The dive boat as it is drawn: a five-metre launch with a white hull
/// over red antifouling, a console under a canvas top, twin outboards on
/// the transom with the dive ladder between them, and a rack of tanks.
///
/// Built here rather than downloaded: the free launches there are are either
/// toys or ships' boats of a hundred thousand triangles, and a hull is a
/// handful of curves. Its frame is the boat's body's — length along x, bow
/// forward, the middle of the box the sea floats at the origin — so it
/// rides where the box rides; it is a little longer than the box at the bow.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:vector_math/vector_math.dart';

/// Where the sea comes to on her, in her frame: the box floats a little
/// under a third of its depth, light as she is.
const double _waterline = -0.06;

/// Linear colours of her paint and her fittings.
final Vector4 _white = Vector4(0.86, 0.86, 0.83, 1.0);
final Vector4 _antifouling = Vector4(0.36, 0.05, 0.04, 1.0);
final Vector4 _stripe = Vector4(0.03, 0.10, 0.30, 1.0);
final Vector4 _deck = Vector4(0.62, 0.60, 0.55, 1.0);
final Vector4 _steel = Vector4(0.60, 0.62, 0.64, 1.0);
final Vector4 _engine = Vector4(0.08, 0.08, 0.09, 1.0);
final Vector4 _glass = Vector4(0.02, 0.04, 0.05, 1.0);
final Vector4 _canvas = Vector4(0.05, 0.16, 0.30, 1.0);
final Vector4 _tank = Vector4(0.85, 0.62, 0.08, 1.0);
final Vector4 _flag = Vector4(0.75, 0.04, 0.03, 1.0);

/// The launch's look, one mesh in one material, its colours in its
/// vertices.
SceneNode launchLook(GraphicsDevice device) {
  final parts = <MeshData>[_hull(), _deckPlate()];
  MeshData box(Vector3 size, Vector3 at, Vector4 color, {Quaternion? turn}) =>
      CuboidShape(size: size)
          .build()
          .transformed(
            Matrix4.compose(
              at,
              turn ?? Quaternion.identity(),
              Vector3(1, 1, 1),
            ),
          )
          .withColor(color.toLinearColor());
  MeshData rod(Vector3 from, Vector3 to, double r, Vector4 color) {
    final along = to - from;
    return CylinderShape(
          radiusTop: r,
          radiusBottom: r,
          height: along.length,
          segments: 8,
        )
        .build()
        .transformed(
          Matrix4.compose(
            from + along * 0.5,
            Quaternion.fromTwoVectors(Vector3(0, 1, 0), along.normalized()),
            Vector3(1, 1, 1),
          ),
        )
        .withColor(color.toLinearColor());
  }

  const deck = 0.30;
  parts
    // The console amidships, its screen raked aft.
    ..add(box(Vector3(0.6, 0.85, 0.75), Vector3(0.45, deck + 0.42, 0), _white))
    ..add(
      box(
        Vector3(0.05, 0.42, 0.72),
        Vector3(0.75, deck + 1.02, 0),
        _glass,
        turn: Quaternion.axisAngle(Vector3(0, 0, 1), 0.35),
      ),
    )
    // The canvas top on four steel legs.
    ..add(box(Vector3(1.9, 0.05, 1.5), Vector3(0.2, deck + 1.75, 0), _canvas));
  for (final x in <double>[-0.7, 1.1]) {
    for (final z in <double>[-0.68, 0.68]) {
      parts.add(
        rod(Vector3(x, deck, z), Vector3(x, deck + 1.75, z), 0.025, _steel),
      );
    }
  }
  // A dive flag on a staff off the top: red, with its white bar.
  parts
    ..add(
      rod(
        Vector3(1.1, deck + 1.75, 0.68),
        Vector3(1.1, deck + 2.45, 0.68),
        0.015,
        _steel,
      ),
    )
    ..add(
      box(Vector3(0.36, 0.26, 0.01), Vector3(1.29, deck + 2.3, 0.68), _flag),
    )
    ..add(
      box(
        Vector3(0.40, 0.05, 0.012),
        Vector3(1.29, deck + 2.3, 0.68),
        _white,
        turn: Quaternion.axisAngle(Vector3(0, 0, 1), -0.6),
      ),
    );
  // Benches along both sides aft, and the tanks racked upright over them.
  for (final side in <double>[-1.0, 1.0]) {
    parts.add(
      box(
        Vector3(1.6, 0.35, 0.35),
        Vector3(-1.1, deck + 0.17, side * 0.62),
        _white,
      ),
    );
    for (var k = 0; k < 4; k++) {
      final at = Vector3(-1.75 + k * 0.42, deck + 0.35, side * 0.80);
      parts
        ..add(
          const CapsuleShape(radius: 0.09, height: 0.62)
              .build()
              .transformed(Matrix4.translation(at + Vector3(0, 0.36, 0)))
              .withColor(_tank.toLinearColor()),
        )
        ..add(
          rod(at + Vector3(0, 0.72, 0), at + Vector3(0, 0.8, 0), 0.03, _steel),
        );
    }
  }
  // A grab rail along each gunwale, on stanchions.
  for (final side in <double>[-1.0, 1.0]) {
    Vector3 rail(double x) =>
        Vector3(x, _sheer(x) + 0.3, side * (_beam(x) - 0.06));
    for (var k = 0; k < 7; k++) {
      final x0 = -1.9 + k * 0.6, x1 = x0 + 0.6;
      parts.add(rod(rail(x0), rail(x1), 0.015, _steel));
      parts.add(rod(rail(x0) - Vector3(0, 0.3, 0), rail(x0), 0.015, _steel));
    }
  }
  // Twin outboards on the transom, and the ladder down into the sea
  // between them.
  for (final side in <double>[-0.5, 0.5]) {
    parts
      ..add(box(Vector3(0.38, 0.55, 0.34), Vector3(-2.72, 0.55, side), _engine))
      ..add(
        box(Vector3(0.16, 0.75, 0.10), Vector3(-2.66, -0.05, side), _engine),
      )
      ..add(
        const CylinderShape(
              radiusTop: 0.06,
              radiusBottom: 0.06,
              height: 0.3,
              segments: 10,
            )
            .build()
            .transformed(
              Matrix4.compose(
                Vector3(-2.62, -0.42, side),
                Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2),
                Vector3(1, 1, 1),
              ),
            )
            .withColor(_engine.toLinearColor()),
      );
  }
  for (final z in <double>[-0.18, 0.18]) {
    parts.add(
      rod(Vector3(-2.6, 0.5, z), Vector3(-2.75, -0.9, z), 0.02, _steel),
    );
  }
  for (var k = 0; k < 4; k++) {
    final x = -2.62 - k * 0.035, y = 0.25 - k * 0.33;
    parts.add(rod(Vector3(x, y, -0.18), Vector3(x, y, 0.18), 0.02, _steel));
  }
  return SceneNode(name: 'boat')..add(
    MeshNode(
      DeviceMesh.upload(device, MeshData.merge(parts)),
      // Both sides: the hull is a skin with no inside, and from the deck
      // its inside is what shows.
      RenderMaterial(name: 'boat', roughness: 0.45, doubleSided: true),
      name: 'launch',
    ),
  );
}

/// Her half beam at the gunwale at [x], m: full from the transom to
/// amidships, then fining to the stem.
double _beam(double x) {
  if (x < -0.4) return 1.02 - 0.03 * ((-0.4 - x) / 2.2);
  final t = ((x + 0.4) / 3.0).clamp(0.0, 1.0);
  return 1.02 * math.sqrt(1.0 - t * t);
}

/// The gunwale's height, rising forward.
double _sheer(double x) =>
    0.38 + 0.22 * math.pow(((x + 2.5) / 5.1).clamp(0.0, 1.0), 2);

/// The keel's depth, rising in a curve to the stem.
double _keel(double x) {
  final t = ((x - 0.6) / 2.0).clamp(0.0, 1.0);
  return -0.42 + (_sheer(x) + 0.42 - 0.05) * t * t;
}

/// A cross-section's points, port gunwale round under the keel to the
/// starboard gunwale: a vee bottom with a chine, and flared topsides.
List<Vector3> _section(double x) {
  final b = _beam(x), g = _sheer(x), k = _keel(x);
  final chineY = k + (g - k) * 0.28;
  return <Vector3>[
    Vector3(x, g, -b),
    Vector3(x, chineY + (g - chineY) * 0.5, -b * 0.97),
    Vector3(x, chineY, -b * 0.86),
    Vector3(x, k + (chineY - k) * 0.35, -b * 0.40),
    Vector3(x, k, 0),
    Vector3(x, k + (chineY - k) * 0.35, b * 0.40),
    Vector3(x, chineY, b * 0.86),
    Vector3(x, chineY + (g - chineY) * 0.5, b * 0.97),
    Vector3(x, g, b),
  ];
}

/// The paint at a height on the hull.
Vector4 _paint(double y, double sheer) => y < _waterline
    ? _antifouling
    : y < _waterline + 0.08 || (y > sheer - 0.13 && y < sheer - 0.07)
    ? _stripe
    : _white;

/// The hull, lofted from sections stem to transom, with the transom closed.
MeshData _hull() {
  const stations = 30;
  final rows = <List<Vector3>>[
    for (var s = 0; s <= stations; s++) _section(-2.5 + 5.1 * s / stations),
  ];
  final width = rows.first.length;
  final positions = <Vector3>[for (final row in rows) ...row];
  final indices = <int>[];
  for (var s = 0; s < stations; s++) {
    for (var p = 0; p < width - 1; p++) {
      final a = s * width + p, b = (s + 1) * width + p;
      // Wound so the faces look outboard.
      indices.addAll(<int>[a, b, a + 1, b, b + 1, a + 1]);
    }
  }
  final hull = _smooth(positions, indices, (p) => _paint(p.y, _sheer(p.x)));
  // The transom: a fan over the stern section, painted as the hull is.
  final stern = rows.first;
  final center = Vector3(-2.5, (stern.first.y + stern[width ~/ 2].y) / 2, 0);
  final fan = <Vector3>[center, ...stern];
  final fanIndices = <int>[
    for (var p = 1; p < fan.length - 1; p++) ...<int>[0, p + 1, p],
  ];
  final transom = _flat(
    fan,
    fanIndices,
    Vector3(-1, 0, 0),
    (p) => _paint(p.y, _sheer(p.x)),
  );
  return MeshData.merge(<MeshData>[hull, transom]);
}

/// The deck, inside the gunwales a little below them.
MeshData _deckPlate() {
  const stations = 24;
  const deck = 0.30;
  final positions = <Vector3>[];
  final indices = <int>[];
  for (var s = 0; s <= stations; s++) {
    final x = -2.48 + 4.6 * s / stations;
    final b = math.max(_beam(x) - 0.06, 0.02);
    positions
      ..add(Vector3(x, deck, -b))
      ..add(Vector3(x, deck, b));
    if (s < stations) {
      final a = s * 2;
      indices.addAll(<int>[a, a + 1, a + 2, a + 2, a + 1, a + 3]);
    }
  }
  return _flat(positions, indices, Vector3(0, 1, 0), (_) => _deck);
}

/// Triangles with normals averaged at their shared vertices.
MeshData _smooth(
  List<Vector3> positions,
  List<int> indices,
  Vector4 Function(Vector3) color,
) {
  final normals = <Vector3>[for (final _ in positions) Vector3.zero()];
  for (var t = 0; t < indices.length; t += 3) {
    final a = positions[indices[t]], b = positions[indices[t + 1]];
    final c = positions[indices[t + 2]];
    final n = (b - a).cross(c - a);
    for (var k = 0; k < 3; k++) {
      normals[indices[t + k]].add(n);
    }
  }
  return _mesh(
    positions,
    <Vector3>[for (final n in normals) n.normalized()],
    indices,
    color,
  );
}

/// Triangles all facing [normal].
MeshData _flat(
  List<Vector3> positions,
  List<int> indices,
  Vector3 normal,
  Vector4 Function(Vector3) color,
) => _mesh(
  positions,
  <Vector3>[for (final _ in positions) normal],
  indices,
  color,
);

MeshData _mesh(
  List<Vector3> positions,
  List<Vector3> normals,
  List<int> indices,
  Vector4 Function(Vector3) color,
) {
  const stride = 16;
  final v = Float32List(positions.length * stride);
  for (var i = 0; i < positions.length; i++) {
    final p = positions[i], n = normals[i], c = color(p);
    final o = i * stride;
    v
      ..[o] = p.x
      ..[o + 1] = p.y
      ..[o + 2] = p.z
      ..[o + 3] = n.x
      ..[o + 4] = n.y
      ..[o + 5] = n.z
      ..[o + 6] = p.x
      ..[o + 7] = p.y
      ..[o + 8] = 1
      ..[o + 11] = 1
      ..[o + 12] = c.x
      ..[o + 13] = c.y
      ..[o + 14] = c.z
      ..[o + 15] = 1;
  }
  return MeshData(
    layout: VertexLayout.standard,
    vertices: v,
    indices: Uint32List.fromList(indices),
  );
}
