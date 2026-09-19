/// Writing a GLB with `GltfWriter`, plain and with `compressGeometry`.
///
/// Quoted by `gltf_write.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class GltfWriteDemo extends ShowcaseDemo {
  late final int _plainBytes;
  late final int _compressedBytes;
  late final bool _usedQuantization;
  late final bool _usedReordering;
  late final List<int> _magic;

  @override
  Scene build(DemoContext context) {
    // #region document
    // A sphere with enough vertices that quantizing its attributes and
    // reordering its triangles actually has something to save on.
    final document = PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: SphereShape(segments: 48, rings: 24).build(),
          materialIndex: 0,
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(
          name: 'shell',
          baseColor: Vector4(0.8, 0.5, 0.2, 1.0),
          roughness: 0.5,
        ),
      ],
    );
    // #endregion document

    // #region write
    final plain = GltfWriter(document).writeGlb();
    final compressor = GltfWriter(document, compressGeometry: true);
    final compressed = compressor.writeGlb();
    // #endregion write

    _plainBytes = plain.length;
    _compressedBytes = compressed.length;
    _usedQuantization = compressor.usedGeometryQuantization;
    _usedReordering = compressor.usedVertexCacheReordering;
    _magic = plain.take(4).toList();

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, document.surfaces.single.mesh),
          Material(baseColor: Vector4(0.8, 0.5, 0.2, 1.0), roughness: 0.5),
          name: 'shell',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region report
  String _report() {
    final magicText = String.fromCharCodes(_magic);
    final ratio = _plainBytes / _compressedBytes;
    return 'GLB magic: "$magicText"\n'
        'plain:      $_plainBytes bytes\n'
        'compressed: $_compressedBytes bytes '
        '(${ratio.toStringAsFixed(2)}x smaller)\n'
        'used quantization: $_usedQuantization\n'
        'used vertex-cache reordering: $_usedReordering';
  }
  // #endregion report

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFE8E8EC),
            fontSize: 16,
            fontFamily: 'monospace',
          ),
          child: Text(_report()),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    if (_magic.first != 0x67) {
      throw StateError('the file does not start with the GLB magic');
    }
    if (_compressedBytes >= _plainBytes) {
      throw StateError('compressGeometry did not shrink the file');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the sphere was not drawn');
    }
    // #endregion check
  }
}
