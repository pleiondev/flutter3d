/// Reading ASCII STL and writing it back as the binary form.
///
/// Quoted by `stl.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class StlDemo extends ShowcaseDemo {
  late final ModelDocument _decoded;
  late final Uint8List _binary;

  // #region source
  // STL has no shared vertices: each of its four facets repeats its own
  // three corners in full, with the facet's own normal ahead of them.
  static const String _sourceStl = '''
solid tetra
  facet normal 0 0 0
    outer loop
      vertex 0 1 0
      vertex 1 -1 1
      vertex -1 -1 1
    endloop
  endfacet
  facet normal 0 0 0
    outer loop
      vertex 0 1 0
      vertex -1 -1 1
      vertex 0 -1 -1.4
    endloop
  endfacet
  facet normal 0 0 0
    outer loop
      vertex 0 1 0
      vertex 0 -1 -1.4
      vertex 1 -1 1
    endloop
  endfacet
  facet normal 0 0 0
    outer loop
      vertex 1 -1 1
      vertex 0 -1 -1.4
      vertex -1 -1 1
    endloop
  endfacet
endsolid tetra
''';
  // #endregion source

  @override
  Future<void> prepare(DemoContext context) async {
    // #region load
    // Every facet's own normal is the zero vector here, on purpose: a
    // surprising number of real exporters write exactly that, and
    // `StlNormals.fromFile`, the default, falls back to the triangle's own
    // cross product rather than trusting a degenerate normal.
    final bytes = Uint8List.fromList(utf8.encode(_sourceStl));
    _decoded = await StlLoader().load(bytes);
    // #endregion load

    // #region write
    _binary = StlWriter(_decoded, name: 'tetra').write();
    // #endregion write
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _decoded.surfaces.single.mesh),
        Material(baseColor: Vector4(0.75, 0.75, 0.8, 1.0), roughness: 0.5),
        name: 'tetra',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  // #region report
  String _report() {
    final headerBytes = _binary.sublist(0, 20);
    final header = String.fromCharCodes(headerBytes.where((byte) => byte != 0));
    final facetCount = ByteData.sublistView(
      _binary,
      80,
      84,
    ).getUint32(0, Endian.little);
    return 'source (ASCII) bytes: ${_sourceStl.length}\n'
        'written (binary) bytes: ${_binary.length}\n'
        'binary header starts: "$header"\n'
        'facet count in binary header: $facetCount';
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
      throw StateError('the tetrahedron did not decode to four facets');
    }
    // A facet whose file normal was degenerate must have been recomputed,
    // never left at zero.
    final nx = mesh.vertices[3];
    final ny = mesh.vertices[4];
    final nz = mesh.vertices[5];
    if (nx == 0.0 && ny == 0.0 && nz == 0.0) {
      throw StateError('a degenerate normal was not recomputed');
    }
    if (_binary.length != 84 + 50 * 4) {
      throw StateError('the binary file is not the size four facets makes it');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the tetrahedron was not drawn');
    }
    // #endregion check
  }
}
