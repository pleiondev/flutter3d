/// Decoding a real Draco bitstream with `decodeDraco`.
///
/// Quoted by `draco.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class DracoDemo extends ShowcaseDemo {
  late final DracoMesh _mesh;
  late final MeshData _upload;

  // #region bitstream
  // A small edgebreaker-encoded mesh, the same fixture
  // `flutter3d_core`'s own decoder test checks against an independently
  // computed set of triangles. Edgebreaker connectivity carries no index
  // buffer and no vertex order of its own: both come out however the
  // encoder's traversal happened to walk the mesh.
  static const String _fixtureBase64 =
      'RFJBQ08CAgEBAAAAQDwBPAEBHx8BF2/btm3bfdu2bdv2ruu6ruu6ruu6rusC/wEz/wI1RA'
      'L/AAAAAAABAAkDAAACAQEJAwABAwEBAQAPIwEHAQgBEAEBAQkBFxTABEaQRtBEhyBH5Yv'
      'P2CnbLPkrs79pACDdXi8AUMmBEQBA+gYCgBrctAHA6m9DAYAfsbEGAFY/rh8AqMHMbwD'
      'go5GqAQAAwPwGAEAarh8AsMEaawDA9WtDAQAfsWkDANd/AwGADW4nBIDtV60BAMzAvQE'
      'ADuOWBAB3O94DAMLH6BYAyDZfeQAgfLS1AYC7jckFALodqhUAAACYXAAA3LG1AQC77ZU'
      'HAMjH6BYA0DbjPQCAfNySAMBu/zMAEQKoACR0HgLAYSQDgAgnDQAJjQFAhEMFABpbAug'
      'dMwB4+DeAl5UAgFkjBKAMCQFA0hECYAYaAUDU3gBgehgAMHsJwLdZAYCJMgCQUNIAiJA'
      'ZAEhIVACcESYA4DADwId9A3CJCQBUW0IAyIgQACYtIQBjnBEAQwUOoCUAAAAA/z8AAAA'
      'grr4AUBi/ACCuvgAwcz8OAAMBAQP/B4E2/5+AAQGrAQP//////58BAf//////o4EBqw'
      'EBAQH/m4ATIJkSAFI2CrI77Ywk2kkIW/rugP8DAAD/AQAACg==';
  // #endregion bitstream

  @override
  Scene build(DemoContext context) {
    // #region decode
    final bytes = base64Decode(_fixtureBase64.replaceAll('\n', ''));
    _mesh = decodeDraco(bytes);
    // #endregion decode

    // #region rebuild
    // A decoded `DracoMesh` is not yet a `MeshData`: its attributes are
    // keyed by Draco's own attribute id, not by name, so a caller picks
    // out the ones it wants. This page draws positions only, with a flat
    // normal recomputed per triangle.
    final position = _mesh.attributes.values.firstWhere(
      (attribute) => attribute.type == DracoAttributeType.position,
    );
    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: _mesh.indices.length,
      reserveIndices: _mesh.indices.length,
    );
    Vector3 pointAt(int index) => Vector3(
      position.values[index * 3],
      position.values[index * 3 + 1],
      position.values[index * 3 + 2],
    );
    for (var t = 0; t + 2 < _mesh.indices.length; t += 3) {
      final a = pointAt(_mesh.indices[t]);
      final b = pointAt(_mesh.indices[t + 1]);
      final c = pointAt(_mesh.indices[t + 2]);
      final cross = (b - a).cross(c - a);
      final normal = cross.length2 > 0.0
          ? cross.normalized()
          : Vector3(0, 0, 1);
      final texcoord = Vector2.zero();
      final i0 = builder.addVertex(
        position: a,
        normal: normal,
        texcoord: texcoord,
      );
      final i1 = builder.addVertex(
        position: b,
        normal: normal,
        texcoord: texcoord,
      );
      final i2 = builder.addVertex(
        position: c,
        normal: normal,
        texcoord: texcoord,
      );
      builder.addTriangle(i0, i1, i2);
    }
    _upload = builder.build();
    // #endregion rebuild

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _upload),
          Material(baseColor: Vector4(0.75, 0.6, 0.5, 1.0), roughness: 0.6),
          name: 'draco mesh',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_mesh.indices.length != 180) {
      throw StateError(
        'this fixture always decodes to 60 triangles (180 corners); got '
        '${_mesh.indices.length}',
      );
    }
    if (_mesh.pointCount == 0) {
      throw StateError('the decoded mesh has no points');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the decoded mesh was not drawn');
    }
    // #endregion check
  }
}
