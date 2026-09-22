/// Write, read back, and compare: `ExportReport` and `validateGltfExport`.
///
/// Quoted by `export_validate.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class ExportValidateDemo extends ShowcaseDemo {
  late final ExportReport _glb;
  late final ExportReport _obj;
  late final ExportReport _stl;
  late final List<String> _boundsProblems;

  final _document = PlainModelDocument(
    surfaces: <ModelSurface>[
      ModelSurface(
        mesh: CuboidShape(size: Vector3.all(1.0)).build(),
        materialIndex: 0,
      ),
    ],
    materials: <SurfaceMaterial>[
      SurfaceMaterial(baseColor: Vector4(0.5, 0.7, 0.9, 1.0)),
    ],
    // `GltfWriter` places a surface through the node graph alone, never
    // through its own transform, so a document meant to be written as glTF
    // needs at least one node naming it.
    nodes: <ModelNode>[
      ModelNode(surfaces: <int>[0]),
    ],
  );

  @override
  Future<void> prepare(DemoContext context) async {
    // #region checked
    // `exportChecked` writes, reads the result back through the same writer
    // and compares. A binary format like GLB is held to a tolerance of
    // `0.0`; OBJ, a decimal text format, rounds on the way out by design and
    // is checked against `ObjWriter.decimals` own precision instead.
    _glb = await exportToGlb(_document);
    _obj = await exportToObj(_document);
    _stl = await exportToStl(_document);
    // #endregion checked

    // #region validate
    // `compareModelDocuments` proves the geometry round-tripped; it says
    // nothing about whether the file's own declared bounds match the data,
    // which is a writer's own bookkeeping and not part of a document at
    // all. `validateGltfExport` checks that separately, straight off the
    // bytes.
    _boundsProblems = await validateGltfExport(_glb.files.values.first);
    // #endregion validate
  }

  @override
  Scene build(DemoContext context) => Scene()
    ..add(
      MeshNode(
        DeviceMesh.upload(context.device, _document.surfaces.single.mesh),
        Material(baseColor: Vector4(0.5, 0.7, 0.9, 1.0)),
        name: 'cube',
      ),
    )
    ..add(
      LightNode(name: 'sun', intensity: 3.0)
        ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
    );

  // #region report
  String _line(String name, ExportReport report) =>
      '$name: ${report.isClean ? 'clean' : 'not clean'}, '
      '${report.writerWarnings.length} warning(s), '
      '${report.differences.length} difference(s)';

  String _report() =>
      '${_line('glb', _glb)}\n'
      '${_line('obj', _obj)}\n'
      '${_line('stl', _stl)}\n'
      'accessor bounds: ${_boundsProblems.isEmpty ? 'match the data' : _boundsProblems.join('\n')}';
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
    if (!_glb.isClean) {
      throw StateError('the GLB round trip was not clean: $_glb');
    }
    if (_boundsProblems.isNotEmpty) {
      throw StateError('the GLB declared the wrong bounds: $_boundsProblems');
    }
    if (frame.drawCalls < 1) {
      throw StateError('the cube was not drawn');
    }
    // #endregion check
  }
}
