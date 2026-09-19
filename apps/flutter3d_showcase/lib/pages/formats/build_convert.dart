/// `flutter3d_build`'s converter, described rather than run: it is a
/// command line tool with no Flutter SDK on its own dependency list, and
/// this app cannot depend on it without pulling the tool into every build.
/// This page instead runs the same decode-then-write path by hand, on a
/// document built in memory, to show what the real command does.
///
/// Quoted by `build_convert.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class BuildConvertDemo extends ShowcaseDemo {
  late final int _sourceBytes;
  late final int _convertedBytes;
  late final ModelDocument _decoded;

  // #region source
  // `dart run flutter3d_build:convert model.obj` reads a model by its file
  // extension. This page hands the same source text straight to the same
  // decoder the real tool would pick.
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
    // #region convert
    // The converter's own two steps, run here by hand: decode the source
    // with the format's ordinary reader, then write it to `.f3d` with
    // `F3dWriter`. `dart run flutter3d_build:convert` does exactly this,
    // for every model under a directory at once, and writes the result
    // beside the source rather than holding it in memory.
    final sourceBytes = utf8.encode(_sourceObj);
    _sourceBytes = sourceBytes.length;
    _decoded = await ObjLoader().load(sourceBytes);
    final converted = F3dWriter(_decoded).write();
    _convertedBytes = converted.length;
    // #endregion convert
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _decoded.surfaces.single.mesh),
        Material(baseColor: Vector4(0.7, 0.65, 0.5, 1.0)),
        name: 'tetra',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  // #region report
  String _report() =>
      'source (.obj) bytes: $_sourceBytes\n'
      'converted (.f3d) bytes: $_convertedBytes\n\n'
      'The real command line tool:\n'
      'dart run flutter3d_build:convert model.obj -o model.f3d\n\n'
      'and, once per project, the build hook that runs it automatically:\n'
      'dart run flutter3d_build:init';
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
    if (_decoded.surfaces.isEmpty) {
      throw StateError('the source did not decode to a surface');
    }
    if (_convertedBytes == 0) {
      throw StateError('the converter wrote nothing');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the tetrahedron was not drawn');
    }
    // #endregion check
  }
}
