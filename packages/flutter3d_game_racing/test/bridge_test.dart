import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/bridge.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

TrackSpline ring({
  double radius = 60.0,
  int points = 20,
  double width = 14.0,
  double bank = 0.0,
  List<BarrierBand> barriers = const <BarrierBand>[],
}) {
  final positions = <Vector3>[
    for (var i = 0; i < points; i++)
      Vector3(
        radius * math.cos(2 * math.pi * i / points),
        0.0,
        radius * math.sin(2 * math.pi * i / points),
      ),
  ];
  return TrackSpline(
    centre: CatmullRom(positions),
    widths: List<double>.filled(points, width),
    banks: List<double>.filled(points, bank),
    barriers: barriers,
  );
}

/// Every vertex position in a mesh, read back out of the buffer.
List<Vector3> positionsOf(MeshData mesh) {
  final floats = mesh.layout.floatsPerVertex;
  final offset = mesh.layout.floatOffsetOf(VertexLayout.position.name);
  return <Vector3>[
    for (var i = 0; i + floats <= mesh.vertices.length; i += floats)
      Vector3(
        mesh.vertices[i + offset],
        mesh.vertices[i + offset + 1],
        mesh.vertices[i + offset + 2],
      ),
  ];
}

/// The direction each triangle actually faces, worked out from the order its
/// corners are listed in — which is what back-face culling reads, and is not
/// the same thing as the normal stored on the vertices.
List<Vector3> faceNormalsOf(MeshData mesh) {
  final points = positionsOf(mesh);
  final normals = <Vector3>[];
  for (var i = 0; i + 2 < mesh.indices.length; i += 3) {
    final a = points[mesh.indices[i]];
    final b = points[mesh.indices[i + 1]];
    final c = points[mesh.indices[i + 2]];
    final normal = (b - a).cross(c - a);
    if (normal.length2 > 1e-12) normals.add(normal.normalized());
  }
  return normals;
}

List<Vector2> texcoordsOf(MeshData mesh) {
  final floats = mesh.layout.floatsPerVertex;
  final offset = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
  return <Vector2>[
    for (var i = 0; i + floats <= mesh.vertices.length; i += floats)
      Vector2(mesh.vertices[i + offset], mesh.vertices[i + offset + 1]),
  ];
}

void main() {
  group('the road surface', () {
    test('it is built where the car drives, not somewhere near it', () {
      // The reason this file exists at all: the mesh and the driving surface
      // come from the same curve, the same width and the same camber. A road
      // drawn from a second description is a road whose edges are in the wrong
      // place, and the car would ride the invisible one.
      final track = ring(bank: 0.12);
      final mesh = buildRoadMesh(track);
      final field = TrackField(track: track);
      final sample = GroundSample();

      // Asked at the vertex itself rather than above it. Sideways distance is
      // measured along the road's own right, which on a cambered corner is
      // tilted — so a probe lifted straight up reads as one lifted partly
      // sideways, and comes back with a height for a place a few centimetres
      // further out. That is a property of asking about a point in mid-air, not
      // a disagreement between the mesh and the road.
      //
      // The hint is carried from vertex to vertex, because the rings come out
      // in order along the lap and that is what the hint is for: asking about a
      // point two hundred metres up the road with a hint of nought is asking
      // outside the search window.
      var worst = 0.0;
      var hint = 0.0;
      for (final vertex in positionsOf(mesh)) {
        expect(field.sample(vertex, hint, sample), isTrue);
        worst = math.max(worst, (sample.height - vertex.y).abs());
        hint = sample.s;
      }

      expect(worst, lessThan(1e-6));
    });

    test('a corner is cut more finely than a straight', () {
      // Mutation: a fixed step. Either the hairpins are polygons or the
      // straights carry ten times the triangles they need.
      final tight = buildRoadMesh(ring(radius: 30.0));
      final open = buildRoadMesh(ring(radius: 300.0));

      final tightPerMetre =
          positionsOf(tight).length / ring(radius: 30.0).length;
      final openPerMetre =
          positionsOf(open).length / ring(radius: 300.0).length;

      expect(tightPerMetre, greaterThan(openPerMetre * 1.5));
    });

    test('the edges are half a road apart, all the way round', () {
      final track = ring(width: 14.0);
      final mesh = buildRoadMesh(track);
      final vertices = positionsOf(mesh);

      // Rings of two: an inner edge and an outer one.
      for (var i = 0; i + 1 < vertices.length; i += 2) {
        expect(vertices[i].distanceTo(vertices[i + 1]), closeTo(14.0, 0.01));
      }
    });

    test('the texture runs along the road and across it', () {
      // Mutation: put the distance in `u`. The markings would then run across
      // the track rather than down it — a road painted like a zebra crossing.
      final track = ring();
      final uv = texcoordsOf(buildRoadMesh(track));

      // Across: nought at one edge, one at the other, every ring.
      for (var i = 0; i + 1 < uv.length; i += 2) {
        expect(uv[i].x, 0.0);
        expect(uv[i + 1].x, 1.0);
      }
      // Along: rising all the way round, and repeating many times over a lap.
      expect(uv.first.y, 0.0);
      expect(uv.last.y, greaterThan(track.length / 20.0));
      for (var i = 2; i < uv.length; i += 2) {
        expect(uv[i].y, greaterThan(uv[i - 2].y));
      }
    });

    test('the seam at the finish line is closed', () {
      // Mutation: stop the last ring short of the lap length. A closed circuit
      // would have a gap across it at the one place every car crosses.
      final track = ring();
      final vertices = positionsOf(buildRoadMesh(track));

      expect(vertices.last.distanceTo(vertices[1]), lessThan(0.01));
      expect(
        vertices[vertices.length - 2].distanceTo(vertices.first),
        lessThan(0.01),
      );
    });

    test('the road faces upwards, and so does every strip beside it', () {
      // Mutation: list a quad's corners the other way round. Nothing about the
      // positions changes — every other test here still passes — and the whole
      // road vanishes from the screen, because back-face culling reads the
      // order of the corners and not the normal written on them. That is
      // exactly what shipped: a circuit with grass down one side and a hole
      // where the tarmac should be, on a mesh whose vertices were all correct.
      final track = ring(bank: 0.15);

      for (final entry in <String, MeshData>{
        'road': buildRoadMesh(track),
        'left verge': buildVergeMesh(track, side: -1),
        'right verge': buildVergeMesh(track, side: 1),
      }.entries) {
        for (final normal in faceNormalsOf(entry.value)) {
          expect(
            normal.y,
            greaterThan(0.5),
            reason: '${entry.key} has a triangle facing away from the sky',
          );
        }
      }
    });

    test('a banked road is tilted in the mesh too', () {
      final flat = positionsOf(buildRoadMesh(ring()));
      final tilted = positionsOf(buildRoadMesh(ring(bank: 0.2)));

      double spread(List<Vector3> vertices) {
        var low = 1e9;
        var high = -1e9;
        for (final v in vertices) {
          low = math.min(low, v.y);
          high = math.max(high, v.y);
        }
        return high - low;
      }

      expect(spread(flat), lessThan(0.01));
      expect(spread(tilted), greaterThan(1.0));
    });
  });

  group('the verge', () {
    test('it starts where the road stops', () {
      final track = ring(width: 14.0);
      final verge = positionsOf(buildVergeMesh(track, side: 1));
      final road = positionsOf(buildRoadMesh(track));

      // The verge's inner edge is the road's outer one.
      expect(verge.first.distanceTo(road[1]), lessThan(0.01));
    });

    test('it is as wide as the shoulder says', () {
      final track = ring(width: 14.0);
      final verge = positionsOf(buildVergeMesh(track, side: -1));

      for (var i = 0; i + 1 < verge.length; i += 2) {
        expect(
          verge[i].distanceTo(verge[i + 1]),
          closeTo(track.shoulder, 0.01),
        );
      }
    });

    test('the two sides are on opposite sides', () {
      final track = ring();
      final left = positionsOf(buildVergeMesh(track, side: -1));
      final right = positionsOf(buildVergeMesh(track, side: 1));

      // On a ring about the origin, one verge is nearer the middle than the
      // other all the way round.
      expect(left.first.length, isNot(closeTo(right.first.length, 1.0)));
    });
  });

  group('barriers', () {
    test('a wall is built only where the track says there is one', () {
      final track = ring(
        barriers: <BarrierBand>[
          const BarrierBand(fromS: 40.0, toS: 120.0, right: true),
        ],
      );

      final right = buildBarrierMeshes(track, side: 1);
      final left = buildBarrierMeshes(track, side: -1);

      expect(right, hasLength(1));
      expect(left, isEmpty);
    });

    test('two stretches of wall are two meshes, not one long one', () {
      // Mutation: one builder for the lap. The two runs would be joined by a
      // wall straight across the road between them, which is a barrier where
      // the track says there is none.
      final track = ring(
        barriers: <BarrierBand>[
          const BarrierBand(fromS: 20.0, toS: 60.0, right: true),
          const BarrierBand(fromS: 180.0, toS: 240.0, right: true),
        ],
      );

      expect(buildBarrierMeshes(track, side: 1), hasLength(2));
    });

    test('a wall stands up from the road edge', () {
      final track = ring(
        barriers: <BarrierBand>[
          const BarrierBand(fromS: 40.0, toS: 120.0, right: true),
        ],
      );
      const settings = RoadMeshSettings();
      final wall = positionsOf(buildBarrierMeshes(track, side: 1).single);

      var low = 1e9;
      var high = -1e9;
      for (final v in wall) {
        low = math.min(low, v.y);
        high = math.max(high, v.y);
      }
      expect(high - low, closeTo(settings.barrierHeight, 0.01));
    });

    test('a track with no walls builds none', () {
      expect(buildBarrierMeshes(ring(), side: 1), isEmpty);
      expect(buildBarrierMeshes(ring(), side: -1), isEmpty);
    });
  });

  group('the map in the corner', () {
    test('the outline goes round the lap once', () {
      final track = ring(radius: 60.0);
      final outline = trackOutline(track, step: 10.0);

      expect(outline.length, closeTo(track.length / 10.0, 2));
      for (final point in outline) {
        expect(point.length, closeTo(60.0, 1.0));
      }
    });
  });
}
