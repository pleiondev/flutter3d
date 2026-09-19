/// Doors, lifts and buttons: one machine that travels between two places, and
/// a switch that relays an activation to it by name.
///
/// Quoted by `level_mechanisms.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as f3d show Material;
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class LevelMechanismsDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = f3d.Material(
      name: 'door',
      baseColor: Vector4(0.6, 0.4, 0.3, 1.0),
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
