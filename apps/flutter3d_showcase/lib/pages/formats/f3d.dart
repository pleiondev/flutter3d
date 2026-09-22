/// `.f3d`: the engine's own container, built to load without parsing.
///
/// Quoted by `f3d.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class F3dDemo extends ShowcaseDemo {
  late final F3dDocument _decoded;
  late final int _fileBytes;
  late final int _glbBytes;

  final _document = PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: SphereShape(segments: 32, rings: 16).build(),
        materialIndex: 0,
      ),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(baseColor: Vector4(0.4, 0.7, 0.5, 1.0)),
    ],
  );

  @override
  Scene build(DemoContext context) {
    // #region write
    // `F3dWriter.write` is the offline half, run once by
    // `dart run flutter3d_build:convert`. Nothing here is on a frame path.
    final bytes = F3dWriter(_document).write();
    _fileBytes = bytes.length;
    _glbBytes = GltfWriter(_document).writeGlb().length;
    // #endregion write

    // #region read
    // Parsing reads the header and the section directory; every array the
    // engine asks for afterwards, `surfaces` included, is a view over these
    // same bytes rather than a copy.
    _decoded = F3dDocument.parse(bytes);
    // #endregion read

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _decoded.surfaces.single.mesh),
          Material(baseColor: Vector4(0.4, 0.7, 0.5, 1.0)),
          name: 'ball',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region report
  String _report() =>
      '.f3d bytes: $_fileBytes\n'
      '.glb bytes (for comparison): $_glbBytes\n'
      'surfaces: ${_decoded.surfaces.length}\n'
      'vertices: ${_decoded.vertexCount}\n'
      'triangles: ${_decoded.triangleCount}';
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
    final differences = compareModelDocuments(_document, _decoded);
    if (differences.isNotEmpty) {
      throw StateError(
        'the round trip through .f3d changed something: '
        '$differences',
      );
    }
    if (_decoded.surfaces.isEmpty) {
      throw StateError('the file decoded to no surfaces');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the ball was not drawn');
    }
    // #endregion check
  }
}
