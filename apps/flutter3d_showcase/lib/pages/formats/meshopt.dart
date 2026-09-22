/// `EXT_meshopt_compression`, written by `GltfWriter(compressGeometry:
/// true)` and decoded again by `GltfLoader`.
///
/// Quoted by `meshopt.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class MeshoptDemo extends ShowcaseDemo {
  late final bool _usedMeshopt;
  late final List<DocumentDifference> _differences;
  late final int _plainBytes;
  late final int _compressedBytes;
  late final ModelDocument _readBack;

  final _document = PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(mesh: SphereShape(segments: 32, rings: 16).build()),
    ],
    // `GltfWriter` reads placement from the node graph alone, so a document
    // headed for glTF needs a node naming its surface.
    nodes: <ModelNode>[
      ModelNode(surfaces: <int>[0]),
    ],
  );

  @override
  Future<void> prepare(DemoContext context) async {
    // #region write
    // The vertex and index bitstreams themselves live in
    // `meshopt_vertex_codec.dart` and `meshopt_index_codec.dart`; this is
    // the writer that reaches for them.
    final plain = GltfWriter(_document).writeGlb();
    final compressed = GltfWriter(_document, compressGeometry: true).writeGlb();
    _plainBytes = plain.length;
    _compressedBytes = compressed.length;
    // #endregion write

    // #region used
    // A GLB's JSON chunk is plain UTF-8 text at the front of the file, so
    // whether the extension was actually reached for is a byte search away.
    _usedMeshopt = latin1
        .decode(compressed, allowInvalid: true)
        .contains('EXT_meshopt_compression');
    // #endregion used

    // #region decode
    // Reordering moves which byte offset a vertex or an index lands at
    // without changing what the mesh draws, so the comparison asks whether
    // the same triangles came back, not whether they are in the same
    // order.
    _readBack = await GltfLoader().load(compressed);
    _differences = compareModelDocuments(
      _document,
      _readBack,
      tolerance: 1e-2,
      allowVertexReorder: true,
    );
    // #endregion decode
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _readBack.surfaces.single.mesh),
        Material(baseColor: Vector4(0.6, 0.7, 0.85, 1.0), roughness: 0.5),
        name: 'ball',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (!_usedMeshopt) {
      throw StateError('compressGeometry did not reach for meshopt at all');
    }
    if (_differences.isNotEmpty) {
      throw StateError('the compressed mesh drew different triangles back');
    }
    if (_compressedBytes >= _plainBytes) {
      throw StateError('the compressed file was not smaller');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
