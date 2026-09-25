/// Generated tangents against MikkTSpace itself.
///
/// The expected frames below are what the reference implementation returns
/// for the same triangles (the `mikktspace` npm package, a WebAssembly build
/// of the Rust port of `mikktspace.c`, fed the unwelded triangle list), with
/// its w negated into glTF's convention. They are literals rather than
/// something recomputed here, because the point is to agree with a program
/// this repository did not write.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Two quads meeting at x = 0, the left one's UVs the mirror of the right's
/// (u = 1 - |x|), sharing the two vertices on the seam — the layout a
/// symmetric model's UV island has when it is mirrored in place.
MeshData _mirroredSeam() {
  final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
  final ids = <int>[
    for (final y in <double>[0.0, 1.0])
      for (final x in <double>[-1.0, 0.0, 1.0])
        builder.addVertex(
          position: Vector3(x, y, 0.2 * x * x),
          normal: Vector3(-0.4 * x, 0.0, 1.0)..normalize(),
          texcoord: Vector2(1.0 - x.abs(), y),
        ),
  ];
  builder
    ..addTriangle(ids[0], ids[1], ids[4])
    ..addTriangle(ids[0], ids[4], ids[3])
    ..addTriangle(ids[1], ids[2], ids[5])
    ..addTriangle(ids[1], ids[5], ids[4]);
  return builder.build();
}

/// A low, uneven cap of seven triangles round a centre: faces of different
/// sizes and UV densities meeting at every vertex, which is where weighting
/// by angle and weighting by UV area part company.
MeshData _unevenFan() {
  final builder = MeshBuilder(VertexLayout.positionNormalTexcoord);
  const ring = <List<double>>[
    <double>[1.2, 0.1, 0.05],
    <double>[0.5, 0.9, 0.15],
    <double>[-0.6, 1.1, 0.0],
    <double>[-1.4, 0.2, 0.1],
    <double>[-0.7, -0.9, 0.12],
    <double>[0.3, -1.3, 0.02],
    <double>[1.1, -0.6, 0.18],
  ];
  const uvs = <List<double>>[
    <double>[0.95, 0.55],
    <double>[0.7, 0.85],
    <double>[0.3, 0.95],
    <double>[0.05, 0.5],
    <double>[0.35, 0.1],
    <double>[0.55, 0.2],
    <double>[0.9, 0.3],
  ];
  final centre = builder.addVertex(
    position: Vector3(0.0, 0.0, 0.3),
    normal: Vector3(0.0, 0.0, 1.0),
    texcoord: Vector2(0.5, 0.5),
  );
  final around = <int>[
    for (var i = 0; i < ring.length; i++)
      builder.addVertex(
        position: Vector3(ring[i][0], ring[i][1], ring[i][2]),
        normal: Vector3(0.3 * ring[i][0], 0.3 * ring[i][1], 1.0)..normalize(),
        texcoord: Vector2(uvs[i][0], uvs[i][1]),
      ),
  ];
  for (var i = 0; i < around.length; i++) {
    builder.addTriangle(centre, around[i], around[(i + 1) % around.length]);
  }
  return builder.build();
}

Vector4 _tangentOf(MeshData mesh, int vertex) {
  final base =
      vertex * mesh.layout.floatsPerVertex +
      mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
  return Vector4(
    mesh.vertices[base],
    mesh.vertices[base + 1],
    mesh.vertices[base + 2],
    mesh.vertices[base + 3],
  );
}

/// Every corner of [mesh]'s triangles carries [expected]'s frame for it.
void _expectCorners(MeshData mesh, List<List<double>> expected) {
  expect(mesh.indices.length, expected.length);
  for (var c = 0; c < expected.length; c++) {
    final tangent = _tangentOf(mesh, mesh.indices[c]);
    for (var k = 0; k < 3; k++) {
      expect(
        tangent[k],
        closeTo(expected[c][k], 1e-5),
        reason: 'component $k of the tangent at corner $c',
      );
    }
    expect(tangent.w, expected[c][3], reason: 'the sign at corner $c');
  }
}

void main() {
  group('mikktspace-generated-tangents', () {
    test('an uneven fan gets the reference frames, weighted by angle', () {
      // Mutation: `method: TangentMethod.lengyel` as the default (the old
      // generator) misses these by a hundredth at the centre; weighting every
      // face alike in `_evaluate` instead of by its angle misses by 3e-4.
      const centre = <double>[0.995514, -0.094616, 0.000000, -1.0];
      const ring = <List<double>>[
        <double>[0.940659, -0.034397, -0.337605, -1.0],
        <double>[0.989365, -0.013109, -0.144865, -1.0],
        <double>[0.981135, -0.038764, 0.189397, -1.0],
        <double>[0.911322, -0.130189, 0.390567, -1.0],
        <double>[0.905403, -0.417433, 0.077428, -1.0],
        <double>[0.983649, -0.119190, -0.135012, -1.0],
        <double>[0.943994, 0.174355, -0.280134, -1.0],
      ];
      final mesh = _unevenFan().withGeneratedTangents();
      _expectCorners(mesh, <List<double>>[
        for (var i = 0; i < ring.length; i++) ...<List<double>>[
          centre,
          ring[i],
          ring[(i + 1) % ring.length],
        ],
      ]);
      expect(mesh.vertexCount, 8, reason: 'nothing here to split');
    });

    test('a vertex on a mirrored seam is split into two frames', () {
      const left = <double>[0.928477, 0.0, -0.371391, -1.0];
      const leftSeam = <double>[1.0, 0.0, 0.0, -1.0];
      const right = <double>[-0.928477, 0.0, -0.371391, 1.0];
      const rightSeam = <double>[-1.0, 0.0, 0.0, 1.0];
      final generated = _mirroredSeam().generateTangents();

      // Mutation: comparing frames by index instead of splitting (the
      // `disagreeing` corners left pointing at the original) gives the right
      // half the left half's seam frame, and the sign on the seam is wrong.
      _expectCorners(generated.mesh, <List<double>>[
        ...<List<double>>[left, leftSeam, leftSeam],
        ...<List<double>>[left, leftSeam, left],
        ...<List<double>>[rightSeam, right, right],
        ...<List<double>>[rightSeam, right, rightSeam],
      ]);
      // The two seam vertices, copied once each onto the end, and the
      // vertices that were there keep their places.
      expect(generated.mesh.vertexCount, 8);
      expect(generated.copiedFrom, Uint32List.fromList(<int>[1, 4]));
    });

    test('without splitting, the vertex count is kept', () {
      final source = _mirroredSeam();
      final kept = source.withGeneratedTangents(splitSeams: false);

      expect(kept.vertexCount, source.vertexCount);
      expect(kept.indices, source.indices);
      // Each seam vertex takes the side more of its corners are on: the
      // bottom one is in one left triangle and two right ones, the top one
      // the other way about.
      expect(_tangentOf(kept, 1), Vector4(-1.0, 0.0, 0.0, 1.0));
      expect(_tangentOf(kept, 4), Vector4(1.0, 0.0, 0.0, -1.0));
    });

    test('Lengyel stays available and never adds a vertex', () {
      final source = _mirroredSeam();
      final fast = source.generateTangents(method: TangentMethod.lengyel);

      expect(fast.mesh.vertexCount, source.vertexCount);
      expect(fast.copiedFrom, isEmpty);
      // And so each seam vertex has one sign for both halves, which is the
      // crease the default no longer draws.
      final seam = _tangentOf(fast.mesh, 1).w;
      expect(<double>[-1.0, 1.0], contains(seam));
    });

    test('identical vertices share a frame whatever the index list says', () {
      // The fan with its centre duplicated for every triangle: the reference
      // welds by value, so the frame at the centre is the same whether the
      // file shared the vertex or not.
      final shared = _unevenFan();
      final stride = shared.layout.floatsPerVertex;
      final vertices = Float32List(shared.indices.length * stride);
      for (var c = 0; c < shared.indices.length; c++) {
        vertices.setRange(
          c * stride,
          (c + 1) * stride,
          shared.vertices,
          shared.indices[c] * stride,
        );
      }
      final unwelded = MeshData(
        layout: shared.layout,
        vertices: vertices,
        indices: Uint32List.fromList(<int>[
          for (var c = 0; c < shared.indices.length; c++) c,
        ]),
      );
      final a = shared.withGeneratedTangents();
      final b = unwelded.withGeneratedTangents();
      for (var c = 0; c < shared.indices.length; c++) {
        final ta = _tangentOf(a, a.indices[c]);
        final tb = _tangentOf(b, b.indices[c]);
        expect((ta - tb).length, lessThan(1e-6), reason: 'corner $c');
      }
    });
  });
}
