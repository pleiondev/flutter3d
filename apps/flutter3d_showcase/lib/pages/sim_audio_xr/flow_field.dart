/// One sweep from a goal, read by every agent in the level as the direction
/// to walk from wherever it stands.
///
/// Quoted by `flow_field.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class FlowFieldDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'agent',
      baseColor: Vector4(0.9, 0.6, 0.3, 1.0),
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
    // #region grid
    final grid = NavGrid.bake(<Brush>[
      Brush(centre: Vector3(5, 0, 5), size: Vector3(10, 1, 10)),
    ], cellSize: 0.5);
    // #endregion grid

    // #region field
    final field = FlowField(grid);
    field.rebuild(Vector3(9.0, 0.0, 9.0));
    // #endregion field

    // #region descend
    final from = Vector3(1.0, 0.0, 1.0);
    final direction = Vector3.zero();
    final found = field.descend(from, direction);
    final distance = field.walkingDistanceTo(from);
    // #endregion descend

    return 'a step from (1, 1) points towards '
        '(${direction.x.toStringAsFixed(2)}, ${direction.z.toStringAsFixed(2)}), '
        'found: $found\n'
        'walking distance to the goal: ${distance?.toStringAsFixed(2)} m';
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
      throw StateError('the agent marker was not drawn');
    }
    if (!_report.contains('found: true')) {
      throw StateError(
        'an open floor should always have a direction to the goal',
      );
    }
    // The direction from (1, 1) towards (9, 9) points diagonally: both
    // components positive.
    if (_report.contains('(-') || _report.contains(', -')) {
      throw StateError(
        'the direction towards a goal up and to the right '
        'should point up and to the right',
      );
    }
  }
}
