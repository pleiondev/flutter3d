/// Doors, lifts and buttons: one machine that travels between two places, and
/// a switch that relays an activation to it by name.
///
/// Quoted by `level_mechanisms.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LevelMechanismsDemo extends ShowcaseDemo {
  late final String _report;

  bool automatic = true;
  bool _pressAsked = false;

  late final MechanismWorld _mechanisms;
  late final Door _door;
  late final Collider _doorCollider;
  late final MeshNode _doorNode;
  late final MeshNode _buttonNode;
  late final BarGauge _progress;
  double _clock = 0.0;
  double _lit = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.3
      ..yaw = 0.4;
    context.orbit.target.setValues(2.5, 1.2, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _report = _run();

    // #region live
    // The same door and button, running: the door's collider is what the
    // mechanism moves, and the picture follows it.
    final CollisionWorld world = CollisionWorld();
    _mechanisms = MechanismWorld(world);
    _doorCollider = world.addBox(Vector3(5, 1, 0), Vector3(1, 2, 0.2));
    _door = _mechanisms.add(
      Door(
        name: 'north-door',
        collider: _doorCollider,
        travel: Vector3(0, 2, 0),
      ),
    );
    _mechanisms.add(
      Button(
        name: 'door-button',
        target: 'north-door',
        collider: world.addBox(Vector3(0, 1, 0), Vector3(0.3, 0.3, 0.3)),
      ),
    );
    // #endregion live

    _doorNode = blockNode(
      context,
      'door',
      Vector3(1.0, 2.0, 0.2),
      Vector4(0.65, 0.42, 0.3, 1.0),
      at: Vector3(5.0, 1.0, 0.0),
    );
    _buttonNode = blockNode(
      context,
      'button',
      Vector3(0.3, 0.3, 0.3),
      Vector4(0.8, 0.2, 0.2, 1.0),
      at: Vector3(0.0, 1.0, 0.0),
    );
    _progress = BarGauge(
      context,
      'progress',
      Vector4(0.9, 0.75, 0.3, 1.0),
      Vector3(7.0, 0.0, 0.0),
      height: 2.0,
      vertical: true,
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 12.0, depth: 6.0),
      // The frame the door slides up out of, and the wall beside it.
      blockNode(
        context,
        'wall left',
        Vector3(4.5, 3.0, 0.4),
        Vector4(0.5, 0.5, 0.52, 1.0),
        at: Vector3(2.75, 1.5, 0.0),
      ),
      blockNode(
        context,
        'wall right',
        Vector3(1.5, 3.0, 0.4),
        Vector4(0.5, 0.5, 0.52, 1.0),
        at: Vector3(5.75 + 0.25, 1.5, 0.0),
      ),
      _doorNode,
      _buttonNode,
      ..._progress.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    if (automatic && _clock > 2.0 && (_clock - 2.0) % 8.0 < dt) {
      _pressAsked = true;
    }
    if (_pressAsked) {
      _pressAsked = false;
      // #region press-live
      _mechanisms.activate('door-button', const Activation());
      // #endregion press-live
      _lit = 1.0;
    }
    _mechanisms.step(dt);
    _lit = (_lit - dt * 1.5).clamp(0.0, 1.0);
    _doorNode.setPositionFrom(_doorCollider.position);
    _progress.set(_door.progress);
    _buttonNode.material.baseColor.setValues(
      0.8 - 0.6 * _lit,
      0.2 + 0.65 * _lit,
      0.2,
      1.0,
    );
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Press the button',
      value: () => false,
      onChanged: (bool v) {
        if (v) _pressAsked = true;
      },
    ),
    ToggleControl(
      'Press it for me',
      value: () => automatic,
      onChanged: (bool v) => automatic = v,
    ),
  ];

  static String _run() {
    // #region world
    final world = CollisionWorld();
    final mechanisms = MechanismWorld(world);
    // #endregion world

    // #region wire
    final doorCollider = world.addBox(Vector3(5, 1, 0), Vector3(1, 2, 0.2));
    final door = mechanisms.add(
      Door(
        name: 'north-door',
        collider: doorCollider,
        travel: Vector3(0, 2, 0),
      ),
    );
    final buttonCollider = world.addBox(
      Vector3(0, 1, 0),
      Vector3(0.3, 0.3, 0.3),
    );
    mechanisms.add(
      Button(
        name: 'door-button',
        target: 'north-door',
        collider: buttonCollider,
      ),
    );
    // #endregion wire

    final beforeProgress = door.progress;

    // #region press
    mechanisms.activate('door-button', const Activation());
    for (var i = 0; i < 180; i++) {
      mechanisms.step(1 / 60);
    }
    // #endregion press

    return 'the door started at progress ${beforeProgress.toStringAsFixed(2)}\n'
        'after pressing the button and stepping three seconds, it is at '
        '${door.progress.toStringAsFixed(2)}, state ${door.state.name}';
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the door marker was not drawn');
    }
    if (!_report.contains('started at progress 0.00')) {
      throw StateError('a door should start closed');
    }
    if (!_report.contains('is at 1.00, state open')) {
      throw StateError(
        'pressing the button should open the door within '
        'three seconds',
      );
    }
  }
}
