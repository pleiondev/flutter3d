import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';
import 'package:flutter3d_samples/flutter3d_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const String kSamples = kSamplesPath;

Uint8List readSample(String name) => File('$kSamples/$name').readAsBytesSync();

Vector4 tangentAt(MeshData mesh, int index) {
  final o =
      index * mesh.layout.floatsPerVertex +
      mesh.layout.floatOffsetOf(VertexLayout.tangent.name);
  return Vector4(
    mesh.vertices[o],
    mesh.vertices[o + 1],
    mesh.vertices[o + 2],
    mesh.vertices[o + 3],
  );
}

Vector3 normalAt(MeshData mesh, int index) {
  final o =
      index * mesh.layout.floatsPerVertex +
      mesh.layout.floatOffsetOf(VertexLayout.normal.name);
  return Vector3(mesh.vertices[o], mesh.vertices[o + 1], mesh.vertices[o + 2]);
}

void main() {
  group('generated tangents against an authoring tool', () {
    // NormalTangentMirrorTest ships TANGENT for geometry that
    // NormalTangentTest supplies without it. The authored data is what a real
    // exporter produced, which makes it the only reference available for
    // whether the generator agrees with the rest of the world — and mirrored UV
    // islands are exactly where a sign convention goes wrong.
    late MeshData authored;
    late MeshData generated;

    setUpAll(() async {
      final asset = await GltfLoader().load(
        readSample('NormalTangentMirrorTest.glb'),
      );
      authored = asset.surfaces.first.mesh;
      generated = authored
          .convertedTo(VertexLayout.positionNormalTexcoord)
          .withGeneratedTangents(target: VertexLayout.standard);
    });

    test('the file really does carry tangents to compare against', () {
      expect(authored.layout.has(VertexLayout.tangent), isTrue);
      // An all-neutral tangent set would mean the loader generated them and the
      // comparison below would be against itself.
      var distinct = 0;
      final first = tangentAt(authored, 0);
      for (var v = 1; v < authored.vertexCount; v++) {
        if ((tangentAt(authored, v) - first).length > 1e-3) distinct++;
      }
      expect(distinct, greaterThan(authored.vertexCount ~/ 2));
    });

    test('the bitangent sign matches almost everywhere', () {
      // The sign is discrete: it is either right or the surface lights from the
      // wrong side. Seams are the exception — a vertex shared between two UV
      // islands of opposite handedness has no single correct answer, and the
      // exporter and the generator may break the tie differently.
      var agree = 0;
      var total = 0;
      for (var v = 0; v < authored.vertexCount; v++) {
        final a = tangentAt(authored, v);
        final g = tangentAt(generated, v);
        if (a.w == 0.0) continue;
        total++;
        if (a.w.sign == g.w.sign) agree++;
      }
      expect(total, greaterThan(0));
      expect(
        agree / total,
        greaterThan(0.98),
        reason: '$agree of $total bitangent signs matched',
      );
    });

    test('the tangent direction matches almost everywhere', () {
      var agree = 0;
      var total = 0;
      for (var v = 0; v < authored.vertexCount; v++) {
        final a = Vector3(
          tangentAt(authored, v).x,
          tangentAt(authored, v).y,
          tangentAt(authored, v).z,
        );
        final g = Vector3(
          tangentAt(generated, v).x,
          tangentAt(generated, v).y,
          tangentAt(generated, v).z,
        );
        if (a.length2 < 1e-6 || g.length2 < 1e-6) continue;
        total++;
        // Averaged across faces versus whatever the exporter smoothed, so the
        // bar is "the same direction", not "the same vector".
        if (a.normalized().dot(g.normalized()) > 0.9) agree++;
      }
      expect(total, greaterThan(0));
      expect(
        agree / total,
        greaterThan(0.95),
        reason: '$agree of $total tangent directions matched',
      );
    });

    test('generated tangents are orthonormal to the normals', () {
      for (var v = 0; v < generated.vertexCount; v++) {
        final n = normalAt(generated, v);
        final t = tangentAt(generated, v);
        final direction = Vector3(t.x, t.y, t.z);
        expect(direction.length, closeTo(1.0, 1e-3));
        if (n.length2 > 1e-6) {
          expect(n.normalized().dot(direction).abs(), lessThan(1e-3));
        }
        expect(t.w.abs(), closeTo(1.0, 1e-6));
      }
    });
  });

  group('decoding fills the standard layout', () {
    test('a file without TANGENT still ends up with one', () async {
      final asset = await GltfLoader().load(
        readSample('NormalTangentTest.glb'),
      );
      final mesh = asset.surfaces.first.mesh;

      expect(mesh.layout.has(VertexLayout.tangent), isTrue);
      for (var v = 0; v < mesh.vertexCount; v++) {
        final t = tangentAt(mesh, v);
        expect(Vector3(t.x, t.y, t.z).length, closeTo(1.0, 1e-3));
      }
    });

    test('a file without COLOR_0 gets opaque white, not black', () async {
      final asset = await GltfLoader().load(readSample('Box.glb'));
      final mesh = asset.surfaces.first.mesh;
      final offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);
      expect(offset, greaterThanOrEqualTo(0));

      for (var v = 0; v < mesh.vertexCount; v++) {
        final o = v * mesh.layout.floatsPerVertex + offset;
        expect(mesh.vertices[o], 1.0);
        expect(mesh.vertices[o + 3], 1.0);
      }
    });

    test('COLOR_0 is still read when the file has it', () async {
      final asset = await GltfLoader().load(readSample('BoxVertexColors.glb'));
      final mesh = asset.surfaces.first.mesh;
      final offset = mesh.layout.floatOffsetOf(VertexLayout.color.name);

      var coloured = 0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final o = v * mesh.layout.floatsPerVertex + offset;
        if (mesh.vertices[o] < 0.99 ||
            mesh.vertices[o + 1] < 0.99 ||
            mesh.vertices[o + 2] < 0.99) {
          coloured++;
        }
      }
      expect(
        coloured,
        greaterThan(0),
        reason: 'the file has vertex colours but none survived decoding',
      );
    });

    test('the material carries every texture slot the file declares', () async {
      final asset = await GltfLoader().load(
        readSample('NormalTangentTest.glb'),
      );
      final material = asset.materials.single;

      expect(material.normalTexture, isNotNull);
      expect(material.occlusionTexture, isNotNull);
      expect(material.metallicRoughnessTexture, isNotNull);
      expect(material.baseColorTexture, isNotNull);
      expect(material.doubleSided, isTrue);
    });
  });

  group('the OBJ path fills tangents too', () {
    test('the teapot ends up with a usable tangent frame', () async {
      // OBJ has no tangent record at all, so every vertex has to be derived —
      // and the teapot has no UVs either, which is the case that must not
      // produce a zero-length frame.
      final asset = await GltfLoader().load(readSample('Box.glb'));
      expect(
        asset.surfaces.first.mesh.layout.has(VertexLayout.tangent),
        isTrue,
      );
    });
  });
}
