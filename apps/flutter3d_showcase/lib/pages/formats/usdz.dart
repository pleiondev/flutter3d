/// Writing geometry as `.usdz`, and reading the text layer back out of its
/// own ZIP container.
///
/// Quoted by `usdz.md` and shown whole in the Source tab.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class UsdzDemo extends ShowcaseDemo {
  late final Uint8List _archive;
  late final String _usda;

  final _document = PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(mesh: CuboidShape(size: Vector3.all(1.0)).build()),
    ],
  );

  @override
  Scene build(DemoContext context) {
    // #region write
    // Geometry only: no materials, no hierarchy past one `Mesh` prim a
    // surface. A `.usdz` is a ZIP with its entries stored uncompressed and
    // aligned, so what Quick Look opens is the same bytes this writes.
    _archive = UsdzWriter(_document, name: 'cube').write();
    // #endregion write

    // #region unzip
    // Nothing in this package reads `.usdz` back, but the archive is a
    // plain ZIP with one uncompressed entry, so its text layer can be read
    // straight off the local file header this writer wrote first.
    final view = ByteData.sublistView(_archive);
    final nameLength = view.getUint16(26, Endian.little);
    final extraLength = view.getUint16(28, Endian.little);
    final dataLength = view.getUint32(22, Endian.little);
    final dataStart = 30 + nameLength + extraLength;
    _usda = utf8.decode(_archive.sublist(dataStart, dataStart + dataLength));
    // #endregion unzip

    return Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(context.device, _document.surfaces.single.mesh),
          Material(baseColor: Vector4(0.85, 0.82, 0.7, 1.0)),
          name: 'cube',
        ),
      )
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  // #region report
  String _report() =>
      'archive bytes: ${_archive.length}\n'
      'first four bytes: '
      '${String.fromCharCodes(_archive.take(2))}'
      '${_archive[2]}${_archive[3]}\n'
      '.usda bytes: ${_usda.length}\n'
      'first line: ${_usda.split('\n').first}';
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
    if (_archive[0] != 0x50 || _archive[1] != 0x4b) {
      throw StateError('the archive does not start with the ZIP signature');
    }
    if (!_usda.startsWith('#usda 1.0')) {
      throw StateError('the text layer is not a USD ASCII file');
    }
    if (!_usda.contains('def Mesh')) {
      throw StateError('the text layer has no mesh prim');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the cube was not drawn');
    }
    // #endregion check
  }
}
