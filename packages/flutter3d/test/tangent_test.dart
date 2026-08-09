import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter3d/src/engine/geometry/geometry.dart';

/// Reads attribute [name] of vertex [index] as a Vector4, zero-padded.
Vector4 attributeAt(MeshData mesh, String name, int index) {
  final offset = mesh.layout.floatOffsetOf(name);
  final attribute =
      mesh.layout.attributes.firstWhere((a) => a.name == name);
  final base = index * mesh.layout.floatsPerVertex + offset;
  return Vector4(
    mesh.vertices[base],
    attribute.componentCount > 1 ? mesh.vertices[base + 1] : 0.0,
    attribute.componentCount > 2 ? mesh.vertices[base + 2] : 0.0,
    attribute.componentCount > 3 ? mesh.vertices[base + 3] : 0.0,
  );
}

Vector3 xyz(Vector4 v) => Vector3(v.x, v.y, v.z);

void main() {
  group('neutral attribute defaults', () {
    test('an unwritten colour is opaque white, not black', () {
      final builder = MeshBuilder(VertexLayout.standard);
      builder.addVertex(position: Vector3.zero(), normal: Vector3(0, 1, 0));
      final mesh = builder.build();

      expect(attributeAt(mesh, 'color', 0), Vector4(1.0, 1.0, 1.0, 1.0));
    });

    test('an unwritten tangent is unit length, not zero', () {
      final builder = MeshBuilder(VertexLayout.standard);
      builder.addVertex(position: Vector3.zero());
      final mesh = builder.build();

      final tangent = attributeAt(mesh, 'tangent', 0);
      expect(xyz(tangent).length, closeTo(1.0, 1e-6));
      expect(tangent.w.abs(), 1.0);
    });
  });

  group('layout conversion', () {
    test('shared attributes are copied and new ones get neutral values', () {
      final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
      builder.addVertex(
        position: Vector3(1.0, 2.0, 3.0),
        normal: Vector3(0.0, 1.0, 0.0),
        texcoord: Vector2(0.25, 0.75),
      );
      final converted = builder.build().convertedTo(VertexLayout.standard);

      expect(xyz(attributeAt(converted, 'position', 0)), Vector3(1.0, 2.0, 3.0));
      expect(attributeAt(converted, 'texcoord', 0).x, closeTo(0.25, 1e-6));
      expect(attributeAt(converted, 'color', 0), Vector4(1.0, 1.0, 1.0, 1.0));
      expect(xyz(attributeAt(converted, 'tangent', 0)).length,
          closeTo(1.0, 1e-6));
    });

    test('converting to the same layout returns the same object', () {
      final mesh = CuboidShape().build(layout: VertexLayout.standard);
      expect(identical(mesh.convertedTo(VertexLayout.standard), mesh), isTrue);
    });

    test('dropping an attribute keeps the rest intact', () {
      final full = CuboidShape().build(layout: VertexLayout.standard);
      final reduced = full.convertedTo(VertexLayout.positionNormal);

      expect(reduced.vertexCount, full.vertexCount);
      expect(reduced.layout.floatsPerVertex, 6);
      for (var v = 0; v < reduced.vertexCount; v++) {
        expect(
          xyz(attributeAt(reduced, 'position', v)),
          xyz(attributeAt(full, 'position', v)),
        );
      }
    });
  });

  group('analytic tangents', () {
    test('a cuboid tangent is orthogonal to its normal and unit length', () {
      final mesh = CuboidShape(size: Vector3(2.0, 1.0, 3.0))
          .build(layout: VertexLayout.standard);

      for (var v = 0; v < mesh.vertexCount; v++) {
        final normal = xyz(attributeAt(mesh, 'normal', v));
        final tangent = attributeAt(mesh, 'tangent', v);
        expect(xyz(tangent).length, closeTo(1.0, 1e-5));
        expect(normal.dot(xyz(tangent)).abs(), lessThan(1e-5));
        expect(tangent.w.abs(), closeTo(1.0, 1e-6));
      }
    });

    test('a lathe tangent runs around the axis', () {
      final mesh =
          const SphereShape(radius: 1.0).build(layout: VertexLayout.standard);

      for (var v = 0; v < mesh.vertexCount; v++) {
        final position = xyz(attributeAt(mesh, 'position', v));
        final tangent = xyz(attributeAt(mesh, 'tangent', v));

        // A surface of revolution's U tangent is horizontal and perpendicular
        // to the radius, whatever the profile is doing.
        expect(tangent.y.abs(), lessThan(1e-5));
        final radial = Vector3(position.x, 0.0, position.z);
        if (radial.length > 1e-3) {
          radial.normalize();
          expect(radial.dot(tangent).abs(), lessThan(1e-5));
        }
      }
    });

    test('the bitangent points against the way V grows', () {
      // glTF's bitangent is minus dP/dv: texture V grows downwards while a
      // normal map's green channel points up. On a sphere V climbs from the
      // bottom pole to the top, so at the equator the bitangent points DOWN.
      // Getting w backwards flips exactly this, and it is what makes every
      // mirrored UV island light from the wrong side.
      final mesh =
          const SphereShape(radius: 1.0).build(layout: VertexLayout.standard);

      var checked = 0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final normal = xyz(attributeAt(mesh, 'normal', v));
        final tangent = attributeAt(mesh, 'tangent', v);
        final bitangent = normal.cross(xyz(tangent))..scale(tangent.w);

        // On the equator the surface climbs straight up as V increases.
        final position = xyz(attributeAt(mesh, 'position', v));
        if (position.y.abs() > 0.05) continue;
        expect(bitangent.y, lessThan(-0.5));
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });

  group('generated tangents', () {
    test('agree with the analytic ones on a cuboid', () {
      // The strongest available check: the same surface, two independent
      // derivations. A sign convention error shows up as an exact negation.
      final analytic = CuboidShape().build(layout: VertexLayout.standard);
      final generated = CuboidShape()
          .build(layout: VertexLayout.positionNormalTexcoord)
          .withGeneratedTangents(target: VertexLayout.standard);

      expect(generated.vertexCount, analytic.vertexCount);
      for (var v = 0; v < analytic.vertexCount; v++) {
        final a = attributeAt(analytic, 'tangent', v);
        final g = attributeAt(generated, 'tangent', v);
        expect(xyz(g).dot(xyz(a)), closeTo(1.0, 1e-4),
            reason: 'tangent direction differs at vertex $v');
        expect(g.w, a.w, reason: 'bitangent sign differs at vertex $v');
      }
    });

    test('agree with the analytic ones on a surface of revolution', () {
      // A torus rather than a cylinder or a sphere: neither of those can settle
      // the question at their axis vertices, where the surface has no width in
      // U and the generated tangent is genuinely undefined. A torus never
      // touches the axis, so every vertex is a fair comparison.
      const shape = TorusShape();
      final analytic = shape.build(layout: VertexLayout.standard);
      final generated = shape
          .build(layout: VertexLayout.positionNormalTexcoord)
          .withGeneratedTangents(target: VertexLayout.standard);

      expect(generated.vertexCount, analytic.vertexCount);
      for (var v = 0; v < analytic.vertexCount; v++) {
        final a = attributeAt(analytic, 'tangent', v);
        final g = attributeAt(generated, 'tangent', v);
        // Not exact, and it should not be: the analytic tangent is the true
        // derivative at the vertex while the generated one averages the chords
        // of the faces meeting there. On a faceted torus that is about half a
        // segment of disagreement — a couple of degrees. The sign, on the other
        // hand, is discrete and has to match exactly.
        expect(xyz(g).dot(xyz(a)), greaterThan(0.995),
            reason: 'tangent direction differs at vertex $v');
        expect(g.w, a.w, reason: 'bitangent sign differs at vertex $v');
      }
    });

    test('an axis vertex still gets a usable frame', () {
      // Where the profile meets the axis a whole column of vertices shares one
      // position, so U has no width and no tangent can be derived. The result
      // has to stay unit length and perpendicular to the normal regardless.
      final generated = const CylinderShape()
          .build(layout: VertexLayout.positionNormalTexcoord)
          .withGeneratedTangents(target: VertexLayout.standard);

      for (var v = 0; v < generated.vertexCount; v++) {
        final normal = xyz(attributeAt(generated, 'normal', v));
        final tangent = xyz(attributeAt(generated, 'tangent', v));
        expect(tangent.length, closeTo(1.0, 1e-4));
        expect(normal.dot(tangent).abs(), lessThan(1e-4));
      }
    });

    test('are orthogonal to the normal and unit length everywhere', () {
      final mesh = const TorusShape()
          .build(layout: VertexLayout.positionNormalTexcoord)
          .withGeneratedTangents();

      for (var v = 0; v < mesh.vertexCount; v++) {
        final normal = xyz(attributeAt(mesh, 'normal', v));
        final tangent = xyz(attributeAt(mesh, 'tangent', v));
        expect(tangent.length, closeTo(1.0, 1e-4));
        expect(normal.dot(tangent).abs(), lessThan(1e-4));
      }
    });

    test('a mirrored UV island gets the opposite sign', () {
      // Two triangles with the same geometry but opposite UV winding. The
      // handedness is the only thing that differs, and it is the whole reason
      // the w component exists.
      MeshData quad({required bool mirrored}) {
        final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
        final normal = Vector3(0.0, 0.0, 1.0);
        // The same triangle in space; only the UV assignment is swapped, which
        // reverses the handedness of the tangent frame without moving a vertex.
        final a = builder.addVertex(
          position: Vector3(0.0, 0.0, 0.0),
          normal: normal,
          texcoord: Vector2(0.0, 0.0),
        );
        final b = builder.addVertex(
          position: Vector3(1.0, 0.0, 0.0),
          normal: normal,
          texcoord: mirrored ? Vector2(0.0, 1.0) : Vector2(1.0, 0.0),
        );
        final c = builder.addVertex(
          position: Vector3(0.0, 1.0, 0.0),
          normal: normal,
          texcoord: mirrored ? Vector2(1.0, 0.0) : Vector2(0.0, 1.0),
        );
        builder.addTriangle(a, b, c);
        return builder.build();
      }

      final normalWinding = quad(mirrored: false).withGeneratedTangents();
      final mirroredWinding = quad(mirrored: true).withGeneratedTangents();

      expect(attributeAt(normalWinding, 'tangent', 0).w, -1.0);
      expect(attributeAt(mirroredWinding, 'tangent', 0).w, 1.0);
    });

    test('a degenerate UV triangle yields a finite frame, not NaN', () {
      final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
      final normal = Vector3(0.0, 0.0, 1.0);
      // All three UVs identical: the UV triangle has zero area.
      final a = builder.addVertex(
        position: Vector3(0.0, 0.0, 0.0),
        normal: normal,
        texcoord: Vector2(0.5, 0.5),
      );
      final b = builder.addVertex(
        position: Vector3(1.0, 0.0, 0.0),
        normal: normal,
        texcoord: Vector2(0.5, 0.5),
      );
      final c = builder.addVertex(
        position: Vector3(0.0, 1.0, 0.0),
        normal: normal,
        texcoord: Vector2(0.5, 0.5),
      );
      builder.addTriangle(a, b, c);

      final mesh = builder.build().withGeneratedTangents();
      for (var v = 0; v < mesh.vertexCount; v++) {
        final tangent = attributeAt(mesh, 'tangent', v);
        expect(tangent.x.isFinite, isTrue);
        expect(xyz(tangent).length, closeTo(1.0, 1e-5));
        expect(xyz(tangent).dot(normal).abs(), lessThan(1e-5));
      }
    });

    test('a mesh with no UVs falls back to the neutral tangent', () {
      final builder = MeshBuilder(VertexLayout.positionNormal);
      final a = builder.addVertex(
        position: Vector3.zero(),
        normal: Vector3(0.0, 1.0, 0.0),
      );
      final b = builder.addVertex(
        position: Vector3(1.0, 0.0, 0.0),
        normal: Vector3(0.0, 1.0, 0.0),
      );
      final c = builder.addVertex(
        position: Vector3(0.0, 0.0, 1.0),
        normal: Vector3(0.0, 1.0, 0.0),
      );
      builder.addTriangle(a, b, c);

      final mesh = builder.build().withGeneratedTangents();
      expect(mesh.layout.has(VertexLayout.tangent), isTrue);
      for (var v = 0; v < mesh.vertexCount; v++) {
        expect(xyz(attributeAt(mesh, 'tangent', v)).length, closeTo(1.0, 1e-6));
      }
    });

    test('the source mesh is left untouched', () {
      final source = CuboidShape().build(layout: VertexLayout.standard);
      final before = attributeAt(source, 'tangent', 3);
      source.withGeneratedTangents();
      expect(attributeAt(source, 'tangent', 3), before);
    });

    test('a target layout without a tangent is refused', () {
      final mesh = CuboidShape().build();
      expect(
        () => mesh.withGeneratedTangents(
          target: VertexLayout.positionNormalTexcoord,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the sphere still behaves after the layout change', () {
    test('normals point outwards', () {
      final mesh =
          const SphereShape(radius: 2.0).build(layout: VertexLayout.standard);
      for (var v = 0; v < mesh.vertexCount; v++) {
        final position = xyz(attributeAt(mesh, 'position', v));
        final normal = xyz(attributeAt(mesh, 'normal', v));
        if (position.length < 1e-3) continue;
        expect(position.normalized().dot(normal), closeTo(1.0, 1e-3));
      }
    });

    test('the winding is still outward', () {
      final mesh =
          const SphereShape(radius: 1.0).build(layout: VertexLayout.standard);
      // 4/3 pi r^3 is about 4.19; a faceted sphere comes in slightly under.
      expect(mesh.signedVolume(), closeTo(4.0, 0.3));
      expect(mesh.signedVolume(), greaterThan(0.0));
    });
  });
}
