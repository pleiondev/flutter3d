/// Determinism in a step: transcendental functions computed the same way on
/// every platform, and a random generator whose state can be written down and
/// restored to continue the same sequence.
///
/// Quoted by `portable_math.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class PortableMathDemo extends ShowcaseDemo {
  late final String _report;

  @override
  Scene build(DemoContext context) {
    _report = _run();
    final material = Material(
      name: 'die',
      baseColor: Vector4(0.9, 0.4, 0.5, 1.0),
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
    // #region trig
    // `Portable.sinCos` places a point on a circle without ever calling
    // `dart:math`, whose trig is a platform's own library and disagrees
    // between the Dart VM and a browser in the last few bits.
    final direction = Portable.sinCos(0.7853981633974483); // pi / 4
    // #endregion trig

    // #region roll
    final dice = GameRandom(1234);
    final firstRoll = dice.nextInt(6) + 1;
    final secondRoll = dice.nextInt(6) + 1;
    final savedState = dice.state;
    // #endregion roll

    // #region resume
    // A fresh generator given the saved state continues the exact same
    // sequence, which is what lets a snapshot carry a simulation's dice
    // forward across a save and a load.
    final resumed = GameRandom(1)..state = savedState;
    final thirdRoll = dice.nextInt(6) + 1;
    final resumedRoll = resumed.nextInt(6) + 1;
    // #endregion resume

    return 'sin/cos of pi/4: ${direction.sin.toStringAsFixed(4)}, '
        '${direction.cos.toStringAsFixed(4)}\n'
        'rolls: $firstRoll, $secondRoll, then $thirdRoll\n'
        'a generator resumed from the saved state rolls $resumedRoll next, '
        'matching the original\'s $thirdRoll';
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
      throw StateError('the die was not drawn');
    }
    final dice = GameRandom(1234);
    final expectedThird = () {
      dice.nextInt(6);
      dice.nextInt(6);
      return dice.nextInt(6) + 1;
    }();
    if (!_report.contains('then $expectedThird')) {
      throw StateError(
        'a GameRandom seeded the same way should roll the '
        'same sequence',
      );
    }
  }
}
