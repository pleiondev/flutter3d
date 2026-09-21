/// One sweep from a goal, read by every agent in the level as the direction
/// to walk from wherever it stands.
///
/// Quoted by `flow_field.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class FlowFieldDemo extends ShowcaseDemo {
  late final String _report;

  int goal = 0;
  bool cycling = true;

  late final NavGrid _grid;
  late final FlowField _field;
  late final MeshNode _beacon;
  final List<MeshNode> _agents = <MeshNode>[];
  final List<Vector3> _starts = <Vector3>[];
  double _clock = 0.0;
  int _shown = -1;

  static const List<(double, double)> _goals = <(double, double)>[
    (18.0, 17.0),
    (18.0, 3.0),
    (3.0, 17.0),
    (3.0, 3.0),
  ];

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 26.0
      ..pitch = 1.0
      ..yaw = 0.0;
    context.orbit.target.setValues(10.0, 0.0, 10.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();

    // #region live
    // A floor with two walls across it, each leaving a gap at one end: an
    // agent has to snake round them, and the field knows how.
    _grid = NavGrid.bake(<Brush>[
      Brush(centre: Vector3(10, 0, 10), size: Vector3(20, 1, 20)),
      Brush(centre: Vector3(7, 2, 6), size: Vector3(1, 4, 12)),
      Brush(centre: Vector3(13, 2, 14), size: Vector3(1, 4, 12)),
    ], cellSize: 0.5);
    _field = FlowField(_grid);
    // #endregion live

    final math.Random random = math.Random(4);
    for (var i = 0; i < 16; i++) {
      final Vector3 start = Vector3(
        1.0 + 4.0 * random.nextDouble(),
        0.5,
        1.0 + 18.0 * random.nextDouble(),
      );
      _starts.add(start);
      _agents.add(
        ballNode(
          context,
          'agent $i',
          0.25,
          Vector4(0.9, 0.6, 0.3, 1.0),
          at: start + Vector3(0.0, 0.25, 0.0),
        ),
      );
    }
    _beacon = blockNode(
      context,
      'goal',
      Vector3(0.5, 2.0, 0.5),
      Vector4(0.95, 0.85, 0.3, 1.0),
    );
    return sceneOf(<SceneNode>[
      blockNode(
        context,
        'floor',
        Vector3(20.0, 0.5, 20.0),
        Vector4(0.34, 0.38, 0.36, 1.0),
        at: Vector3(10.0, 0.25, 10.0),
      ),
      blockNode(
        context,
        'wall 1',
        Vector3(1.0, 1.5, 12.0),
        Vector4(0.55, 0.5, 0.5, 1.0),
        at: Vector3(7.0, 1.25, 6.0),
      ),
      blockNode(
        context,
        'wall 2',
        Vector3(1.0, 1.5, 12.0),
        Vector4(0.55, 0.5, 0.5, 1.0),
        at: Vector3(13.0, 1.25, 14.0),
      ),
      _beacon,
      ..._agents,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (cycling) goal = (_clock ~/ 12.0) % _goals.length;
    final (double gx, double gz) = _goals[goal];
    if (goal != _shown) {
      _shown = goal;
      // #region aim
      // A new goal is one rebuild; every agent then follows the same table.
      _field.rebuild(Vector3(gx, 0.5, gz));
      // #endregion aim
      _beacon.setPosition(gx, 1.5, gz);
    }
    final Vector3 direction = Vector3.zero();
    for (var i = 0; i < _agents.length; i++) {
      final Vector3 at = _agents[i].readPosition()..y = 0.5;
      // #region follow
      // One step down the table from wherever the agent stands.
      if (_field.descend(at, direction)) {
        at.addScaled(direction, 3.0 * dt);
      }
      // #endregion follow
      if ((at.x - gx).abs() + (at.z - gz).abs() < 1.0) {
        at.setFrom(_starts[i]);
      }
      _agents[i].setPosition(at.x, 0.75, at.z);
    }
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Goal',
      options: const <String>['far corner', 'near corner', 'far side', 'start'],
      index: () => goal,
      onChanged: (int i) {
        cycling = false;
        goal = i;
      },
    ),
    ToggleControl(
      'Move the goal',
      value: () => cycling,
      onChanged: (bool v) => cycling = v,
    ),
  ];

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
