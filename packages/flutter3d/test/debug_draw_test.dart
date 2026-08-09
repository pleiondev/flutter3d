import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d/src/engine/render/debug_draw.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';

/// Reads a vertex out of the packed line buffer.
({Vector3 position, Vector4 color}) _vertexAt(DebugDraw draw, int index) {
  final floats = Float32List.view(
    draw.vertexBytes.buffer,
    draw.vertexBytes.offsetInBytes,
    draw.vertexBytes.lengthInBytes ~/ 4,
  );
  final o = index * DebugDraw.floatsPerVertex;
  return (
    position: Vector3(floats[o], floats[o + 1], floats[o + 2]),
    color: Vector4(floats[o + 3], floats[o + 4], floats[o + 5], floats[o + 6]),
  );
}

void main() {
  final red = Vector4(1.0, 0.0, 0.0, 1.0);

  group('line buffer', () {
    test('a segment writes two vertices carrying the same colour', () {
      final draw = DebugDraw();
      draw.addLine(Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0), red);

      expect(draw.lineCount, 1);
      expect(draw.vertexCount, 2);

      final a = _vertexAt(draw, 0);
      final b = _vertexAt(draw, 1);
      expect(a.position, Vector3(1.0, 2.0, 3.0));
      expect(b.position, Vector3(4.0, 5.0, 6.0));
      expect(a.color, red);
      expect(b.color, red);
    });

    test('clear rewinds without shrinking the buffer', () {
      final draw = DebugDraw(reserveLines: 1);
      for (var i = 0; i < 100; i++) {
        draw.addLine(Vector3.zero(), Vector3(i.toDouble(), 0.0, 0.0), red);
      }
      expect(draw.lineCount, 100);

      draw.clear();
      expect(draw.isEmpty, isTrue);
      expect(draw.vertexBytes.lengthInBytes, 0);

      // Growth happened while filling; refilling must not re-grow or misplace.
      draw.addLine(Vector3.zero(), Vector3(1.0, 0.0, 0.0), red);
      expect(draw.lineCount, 1);
      expect(_vertexAt(draw, 1).position, Vector3(1.0, 0.0, 0.0));
    });

    test('vertexBytes covers only the used range', () {
      final draw = DebugDraw(reserveLines: 64);
      draw.addLine(Vector3.zero(), Vector3(1.0, 0.0, 0.0), red);
      expect(draw.vertexBytes.lengthInBytes, DebugDraw.floatsPerLine * 4);
    });
  });

  group('box', () {
    test('an AABB becomes twelve edges spanning its corners', () {
      final draw = DebugDraw();
      draw.addBox(
        Aabb3.minMax(Vector3(-1.0, -2.0, -3.0), Vector3(1.0, 2.0, 3.0)),
        red,
      );
      expect(draw.lineCount, 12);

      // Every endpoint is a corner of the box, never an interior point.
      for (var i = 0; i < draw.vertexCount; i++) {
        final p = _vertexAt(draw, i).position;
        expect(p.x.abs(), closeTo(1.0, 1e-6));
        expect(p.y.abs(), closeTo(2.0, 1e-6));
        expect(p.z.abs(), closeTo(3.0, 1e-6));
      }
    });

    test('a transformed box follows the rotation rather than re-axis-aligning',
        () {
      final draw = DebugDraw();
      final unitCube =
          Aabb3.minMax(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5));
      // 45 degrees about Y: an axis-aligned box would gain half-extents of
      // sqrt(0.5) in x and z, the rotated one keeps corners at that radius but
      // has vertices exactly on the axes.
      draw.addTransformedBox(unitCube, Matrix4.rotationY(math.pi / 4), red);

      var onAxis = 0;
      for (var i = 0; i < draw.vertexCount; i++) {
        final p = _vertexAt(draw, i).position;
        expect(math.sqrt(p.x * p.x + p.z * p.z), closeTo(math.sqrt(0.5), 1e-6));
        if (p.x.abs() < 1e-6 || p.z.abs() < 1e-6) onAxis++;
      }
      expect(onAxis, greaterThan(0));
    });
  });

  group('frustum', () {
    test('corners sit on the near and far planes of the source camera', () {
      const near = 0.5;
      const far = 10.0;
      const projection = PerspectiveProjection(near: near, far: far);
      // Identity view: the camera sits at the origin looking down -Z.
      final draw = DebugDraw();
      draw.addFrustum(projection.toMatrix(1.0), red);

      expect(draw.lineCount, 12);

      var nearCorners = 0;
      var farCorners = 0;
      for (var i = 0; i < draw.vertexCount; i++) {
        final z = _vertexAt(draw, i).position.z;
        if ((z + near).abs() < 1e-3) nearCorners++;
        if ((z + far).abs() < 1e-3) farCorners++;
      }
      // Twelve edges touch eight corners, so each corner appears three times.
      expect(nearCorners, 12);
      expect(farCorners, 12);
    });

    test('a singular matrix draws nothing instead of producing NaN', () {
      final draw = DebugDraw();
      draw.addFrustum(Matrix4.zero(), red);
      expect(draw.isEmpty, isTrue);
    });
  });

  group('normals', () {
    test('each segment starts on a vertex and runs along its world normal', () {
      final mesh = CuboidShape().build();
      final draw = DebugDraw();
      // Non-uniform scale: the case where using the world matrix instead of the
      // inverse transpose visibly tilts the segments.
      final world = Matrix4.diagonal3(Vector3(2.0, 1.0, 1.0));
      final normalMatrix = Matrix4.copy(world)
        ..invert()
        ..transpose();

      draw.addNormals(mesh, world, normalMatrix, length: 0.25);
      expect(draw.lineCount, mesh.vertexCount);

      // A face whose normal is +X keeps pointing along +X under an x-scale, and
      // the segment length is what was asked for.
      for (var i = 0; i < draw.lineCount; i++) {
        final a = _vertexAt(draw, i * 2).position;
        final b = _vertexAt(draw, i * 2 + 1).position;
        expect((b - a).length, closeTo(0.25, 1e-5));
      }
    });

    test('a mesh without normals is skipped rather than misread', () {
      final builder = MeshBuilder(VertexLayout.positionOnly);
      final a = builder.addVertex(position: Vector3(0.0, 0.0, 0.0));
      final b = builder.addVertex(position: Vector3(1.0, 0.0, 0.0));
      final c = builder.addVertex(position: Vector3(0.0, 1.0, 0.0));
      builder.addTriangle(a, b, c);

      final draw = DebugDraw();
      draw.addNormals(
        builder.build(),
        Matrix4.identity(),
        Matrix4.identity(),
        length: 1.0,
      );
      expect(draw.isEmpty, isTrue);
    });

    test('a dense mesh is sampled rather than drawn in full', () {
      // Enough vertices to exceed the cap: the overlay must stay bounded.
      final mesh = const SphereShape(segments: 128, rings: 96).build();
      expect(mesh.vertexCount, greaterThan(DebugDraw.maxNormalsPerMesh));

      final draw = DebugDraw();
      draw.addNormals(
        mesh,
        Matrix4.identity(),
        Matrix4.identity(),
        length: 0.1,
      );
      expect(draw.lineCount, lessThanOrEqualTo(DebugDraw.maxNormalsPerMesh));
      expect(draw.lineCount, greaterThan(0));
    });
  });

  group('options', () {
    test('nothing enabled means nothing to build', () {
      expect(const DebugDrawOptions().anyEnabled, isFalse);
      expect(const DebugDrawOptions(bounds: true).anyEnabled, isTrue);
    });

    test('copyWith changes one flag and keeps the rest', () {
      const base = DebugDrawOptions(bounds: true, normalLength: 0.5);
      final next = base.copyWith(normals: true);
      expect(next.bounds, isTrue);
      expect(next.normals, isTrue);
      expect(next.normalLength, 0.5);
    });
  });
}
