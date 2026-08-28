import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Reads a vertex normal for the standard position/normal/texcoord layout.
Vector3 normalAt(MeshData mesh, int index) {
  final offset = mesh.layout.floatOffsetOf(VertexLayout.normal.name);
  final base = index * mesh.layout.floatsPerVertex + offset;
  return Vector3(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
  );
}

void main() {
  group('winding is consistent and outward', () {
    // Signed volume is positive only when every triangle winds
    // counter-clockwise as seen from outside. This is what makes backface
    // culling safe, and it is checked without a GPU.
    final closedShapes = <String, MeshData>{
      'box': CuboidShape().build(),
      'sphere': const SphereShape().build(),
      'cylinder': const CylinderShape().build(),
      'cone': const ConeShape().build(),
      'torus': const TorusShape().build(),
      'capsule': const CapsuleShape().build(),
    };

    closedShapes.forEach((name, mesh) {
      test('$name has positive signed volume', () {
        expect(mesh.signedVolume(), greaterThan(0.0), reason: name);
      });
    });

    test('reversing a profile flips the orientation', () {
      final profile = <Vector2>[
        Vector2(0.0, -0.5),
        Vector2(0.5, -0.5),
        Vector2(0.5, -0.5),
        Vector2(0.5, 0.5),
        Vector2(0.5, 0.5),
        Vector2(0.0, 0.5),
      ];
      final outward = LatheShape(profile: profile, segments: 24).build();
      final inward = LatheShape(
        profile: profile.reversed.toList(),
        segments: 24,
      ).build();

      expect(outward.signedVolume(), greaterThan(0.0));
      expect(inward.signedVolume(), lessThan(0.0));
      // Same surface, opposite orientation: magnitudes must match.
      expect(
        inward.signedVolume().abs(),
        closeTo(outward.signedVolume().abs(), 1e-5),
      );
    });
  });

  group('generated volumes match the analytic ones', () {
    // Faceted meshes always under-fill a curved shape, so tolerances are
    // one-sided in spirit but kept symmetric and loose enough for the default
    // segment counts.
    test('sphere', () {
      final mesh = SphereShape(radius: 0.5, segments: 64, rings: 32).build();
      final expected = 4.0 / 3.0 * math.pi * math.pow(0.5, 3);
      expect(mesh.signedVolume(), closeTo(expected, expected * 0.01));
    });

    test('cylinder', () {
      final mesh = CylinderShape(
        radiusTop: 0.4,
        radiusBottom: 0.4,
        height: 1.2,
        segments: 128,
      ).build();
      final expected = math.pi * 0.4 * 0.4 * 1.2;
      expect(mesh.signedVolume(), closeTo(expected, expected * 0.01));
    });

    test('cone', () {
      final mesh = ConeShape(radius: 0.5, height: 1.0, segments: 128).build();
      final expected = math.pi * 0.5 * 0.5 * 1.0 / 3.0;
      expect(mesh.signedVolume(), closeTo(expected, expected * 0.01));
    });

    test('torus', () {
      final mesh = TorusShape(
        radius: 0.35,
        tubeRadius: 0.15,
        segments: 128,
        tubeSegments: 64,
      ).build();
      final expected = 2.0 * math.pi * math.pi * 0.35 * 0.15 * 0.15;
      expect(mesh.signedVolume(), closeTo(expected, expected * 0.01));
    });

    test('box', () {
      final mesh = CuboidShape(size: Vector3(1.0, 2.0, 3.0)).build();
      expect(mesh.signedVolume(), closeTo(6.0, 1e-5));
    });
  });

  group('normals', () {
    test('are unit length on every primitive', () {
      final meshes = <String, MeshData>{
        'sphere': const SphereShape().build(),
        'cylinder': const CylinderShape().build(),
        'torus': const TorusShape().build(),
        'capsule': const CapsuleShape().build(),
        'disc': const DiscShape().build(),
      };

      meshes.forEach((name, mesh) {
        for (var i = 0; i < mesh.vertexCount; i++) {
          expect(
            normalAt(mesh, i).length,
            closeTo(1.0, 1e-4),
            reason: '$name vertex $i',
          );
        }
      });
    });

    test('sphere normals are radial', () {
      final mesh = SphereShape(radius: 0.5).build();
      final position = Vector3.zero();
      for (var i = 0; i < mesh.vertexCount; i++) {
        mesh.positionAt(i, position);
        // Poles sit on the axis with a radius of 0, but their normal is still
        // the axis direction, so the dot product stays 1.
        expect(
          normalAt(mesh, i).dot(position.normalized()),
          closeTo(1.0, 1e-4),
          reason: 'vertex $i',
        );
      }
    });

    test('repeated profile points keep the cylinder rim hard', () {
      final mesh = CylinderShape(
        radiusTop: 0.5,
        radiusBottom: 0.5,
        height: 1.0,
        segments: 16,
      ).build();
      final position = Vector3.zero();

      var capNormals = 0;
      var wallNormals = 0;
      for (var i = 0; i < mesh.vertexCount; i++) {
        mesh.positionAt(i, position);
        if ((position.y + 0.5).abs() > 1e-6) continue;
        final normal = normalAt(mesh, i);
        if ((normal.y + 1.0).abs() < 1e-4) capNormals++;
        if (normal.y.abs() < 1e-4) wallNormals++;
      }

      // Both families exist at the same height: the cap points straight down
      // while the wall points sideways. A smoothed rim would have neither.
      expect(capNormals, greaterThan(0));
      expect(wallNormals, greaterThan(0));
    });

    test('disc faces +Y', () {
      final mesh = DiscShape(radius: 0.5).build();
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(normalAt(mesh, i).y, closeTo(1.0, 1e-4));
      }
    });
  });

  group('revolve details', () {
    test('drops the degenerate triangles at the poles', () {
      final mesh = SphereShape(segments: 8, rings: 4).build();
      final a = Vector3.zero();
      final b = Vector3.zero();
      final c = Vector3.zero();

      for (var i = 0; i < mesh.indexCount; i += 3) {
        mesh.positionAt(mesh.indices[i], a);
        mesh.positionAt(mesh.indices[i + 1], b);
        mesh.positionAt(mesh.indices[i + 2], c);
        final area = (b - a).cross(c - a).length * 0.5;
        expect(area, greaterThan(1e-9), reason: 'triangle ${i ~/ 3}');
      }
    });

    test('UVs span the full range', () {
      final mesh = SphereShape(segments: 16, rings: 8).build();
      final uvOffset = mesh.layout.floatOffsetOf(VertexLayout.texcoord.name);
      final stride = mesh.layout.floatsPerVertex;

      var minU = double.infinity, maxU = -double.infinity;
      var minV = double.infinity, maxV = -double.infinity;
      for (var o = uvOffset; o < mesh.vertices.length; o += stride) {
        minU = math.min(minU, mesh.vertices[o]);
        maxU = math.max(maxU, mesh.vertices[o]);
        minV = math.min(minV, mesh.vertices[o + 1]);
        maxV = math.max(maxV, mesh.vertices[o + 1]);
      }

      expect(minU, closeTo(0.0, 1e-6));
      expect(maxU, closeTo(1.0, 1e-6));
      expect(minV, closeTo(0.0, 1e-6));
      expect(maxV, closeTo(1.0, 1e-6));
    });

    test('rejects a negative radius', () {
      expect(
        () => LatheShape(
          profile: <Vector2>[Vector2(-1.0, 0.0), Vector2(1.0, 1.0)],
        ).build(),
        throwsArgumentError,
      );
    });

    test('rejects too few segments', () {
      expect(
        () => LatheShape(
          profile: <Vector2>[Vector2(1.0, 0.0), Vector2(1.0, 1.0)],
          segments: 2,
        ).build(),
        throwsArgumentError,
      );
    });

    test('a partial sweep produces an open surface', () {
      final half = LatheShape(
        profile: <Vector2>[Vector2(0.5, -0.5), Vector2(0.5, 0.5)],
        segments: 32,
        sweepAngle: math.pi,
      ).build();
      expect(half.triangleCount, 32 * 2);
    });
  });

  group('mesh data', () {
    test('layout offsets follow declaration order', () {
      const layout = VertexLayout.positionNormalTexcoord;
      expect(layout.floatsPerVertex, 8);
      expect(layout.strideInBytes, 32);
      expect(layout.floatOffsetOf('position'), 0);
      expect(layout.floatOffsetOf('normal'), 3);
      expect(layout.floatOffsetOf('texcoord'), 6);
      expect(layout.floatOffsetOf('tangent'), -1);
    });

    test('merge rebases indices and preserves volume', () {
      final left = CuboidShape().build().transformed(
        Matrix4.translationValues(-1.0, 0.0, 0.0),
      );
      final right = CuboidShape().build().transformed(
        Matrix4.translationValues(1.0, 0.0, 0.0),
      );
      final merged = MeshData.merge([left, right]);

      expect(merged.vertexCount, left.vertexCount + right.vertexCount);
      expect(merged.indices.reduce(math.max), merged.vertexCount - 1);
      expect(merged.signedVolume(), closeTo(2.0, 1e-4));
    });

    test('transformed keeps normals unit under non-uniform scale', () {
      final mesh = SphereShape(
        radius: 0.5,
      ).build().transformed(Matrix4.diagonal3(Vector3(2.0, 0.5, 1.0)));
      for (var i = 0; i < mesh.vertexCount; i++) {
        expect(normalAt(mesh, i).length, closeTo(1.0, 1e-4));
      }
    });

    test('bounds cover the box exactly', () {
      final bounds = CuboidShape(
        size: Vector3(2.0, 4.0, 6.0),
      ).build().computeBounds();
      expect(bounds.min.x, closeTo(-1.0, 1e-6));
      expect(bounds.max.y, closeTo(2.0, 1e-6));
      expect(bounds.max.z, closeTo(3.0, 1e-6));
    });

    test('indices narrow to 16 bit for small meshes', () {
      final packed = CuboidShape().build().packIndices();
      expect(packed.is16Bit, isTrue);
      expect(packed.count, 36);
      expect(packed.bytes.lengthInBytes, 72);
    });

    test('a large mesh keeps 32-bit indices', () {
      final mesh = SphereShape(segments: 400, rings: 200).build();
      expect(mesh.vertexCount, greaterThan(0x10000));
      expect(mesh.packIndices().is16Bit, isFalse);
    });

    test('rejects vertices that do not match the layout', () {
      expect(
        () => MeshData(
          // 7 floats is not a whole vertex for an 8-float layout.
          layout: VertexLayout.positionNormalTexcoord,
          vertices: Float32List(7),
          indices: Uint32List(0),
        ),
        throwsArgumentError,
      );
    });

    test('rejects an index count that is not a multiple of 3', () {
      expect(
        () => MeshData(
          layout: VertexLayout.positionNormalTexcoord,
          vertices: Float32List(8),
          indices: Uint32List(4),
        ),
        throwsArgumentError,
      );
    });
  });
}
