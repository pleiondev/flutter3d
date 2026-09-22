/// Reading and writing Wavefront OBJ, with `ObjNormals` filling in what a
/// file left out.
///
/// Quoted by `obj.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ObjDemo extends ShowcaseDemo {
  late final ModelDocument _decoded;
  late final Uint8List _written;

  // #region source
  // A tetrahedron with no `vn` records at all — real files omit normals
  // often enough that `ObjLoader` has to have an answer for it.
  static const String _sourceObj = '''
v 0 1 0
v 1 -1 1
v -1 -1 1
v 0 -1 -1.4
f 1 2 3
f 1 3 4
f 1 4 2
f 2 4 3
''';
  // #endregion source

  @override
  Future<void> prepare(DemoContext context) async {
    // #region load
    // `ObjNormals.smooth`, the loader's default, averages the face normals
    // meeting at each vertex rather than leaving them at zero.
    final bytes = Uint8List.fromList(utf8.encode(_sourceObj));
    _decoded = await ObjLoader(normals: ObjNormals.smooth).load(bytes);
    // #endregion load

    // #region write
    final writer = ObjWriter(_decoded, name: 'tetra');
    _written = writer.write();
    // #endregion write
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _decoded.surfaces.single.mesh),
        Material(baseColor: Vector4(0.8, 0.6, 0.3, 1.0), roughness: 0.6),
        name: 'tetra',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  // #region report
  String _report() {
    final mesh = _decoded.surfaces.single.mesh;
    return 'source bytes: ${_sourceObj.length}\n'
        'written bytes: ${_written.length}\n'
        'vertices: ${mesh.vertexCount}\n'
        'triangles: ${mesh.triangleCount}\n'
        'a generated normal: ${mesh.vertices[3].toStringAsFixed(3)}, '
        '${mesh.vertices[4].toStringAsFixed(3)}, '
        '${mesh.vertices[5].toStringAsFixed(3)}';
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
    final mesh = _decoded.surfaces.single.mesh;
    if (mesh.triangleCount != 4) {
      throw StateError('the tetrahedron did not decode to four triangles');
    }
    // A generated normal is never the zero vector `ObjNormals.none` would
    // have left behind.
    final nx = mesh.vertices[3];
    final ny = mesh.vertices[4];
    final nz = mesh.vertices[5];
    if (nx == 0.0 && ny == 0.0 && nz == 0.0) {
      throw StateError('no normal was generated for a file that had none');
    }
    if (_written.isEmpty) {
      throw StateError('the writer produced nothing');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the tetrahedron was not drawn');
    }
    // #endregion check
  }
}
