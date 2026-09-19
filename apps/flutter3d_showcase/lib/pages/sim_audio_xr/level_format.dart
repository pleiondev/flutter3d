/// The document a level is: brushes, entities and lights, and the validator
/// that reports what is wrong with one before it is ever played.
///
/// Quoted by `level_format.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LevelFormatDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'level',
      baseColor: Vector4(0.7, 0.7, 0.5, 1.0),
    );
    final node = MeshNode(
      DeviceMesh.upload(context.device, SphereShape(segments: 16).build()),
      material,
    );
    return Scene()
      ..add(node)
      ..add(
        LightNode(name: 'sun', intensity: 3.0)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.3)),
      );
  }

  static String _run() {
    // #region level
    // Two brushes that overlap by a metre, which nothing in this format
    // forbids outright but which the validator flags as worth a look.
    final level = Level(
      name: 'sample',
      brushes: <Brush>[
        Brush(centre: Vector3(0, 0, 0), size: Vector3(4, 2, 4)),
        Brush(centre: Vector3(3, 0, 0), size: Vector3(4, 2, 4)),
      ],
      entities: <EntityDef>[EntityDef(type: 'spawn', name: 'start')],
    );
    // #endregion level

    // #region write
    final json = level.toJson();
    final reread = Level.fromJson(json);
    // #endregion write

    // #region validate
    final validator = LevelValidator(
      registry: EntityRegistry(const <EntityKind>[]),
    );
    final issues = validator.validate(reread);
    // #endregion validate

    return '${reread.brushes.length} brushes round-tripped through JSON\n'
        '${issues.length} issue(s): ${issues.map((LevelIssue i) => i.message).join(' | ')}';
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) =>
      Container(
        color: const Color(0xFF14161A),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.topLeft,
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
          child: Text(_report),
        ),
      );

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the level marker was not drawn');
    }
    if (!_report.contains('2 brushes round-tripped')) {
      throw StateError('every brush should survive a trip through JSON');
    }
    if (_report.contains('0 issue(s)')) {
      throw StateError(
        'two overlapping brushes should be reported by the validator',
      );
    }
  }
}
