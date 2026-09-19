/// Four axes a genre applies where it decides: what the player is hurt by,
/// what their own attacks are worth, how quickly the opposition reacts, and
/// how much help is switched on.
///
/// Quoted by `difficulty.md` and shown whole in the Source tab.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class DifficultyDemo extends ShowcaseDemo {
  @override
  Scene build(DemoContext context) {
    final material = Material(
      name: 'target',
      baseColor: Vector4(0.7, 0.5, 0.9, 1.0),
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

  // #region apply
  /// A hit a genre would deal at `normal`, scaled by one difficulty.
  static double _incomingDamage(Difficulty at, double baseAmount) =>
      baseAmount * at.damageTaken;
  // #endregion apply

  static String _lineFor(Difficulty level) {
    final hit = _incomingDamage(level, 10.0);
    return '${level.name}: a ten-point hit costs $hit, opponents react at '
        'x${level.opponentReaction} speed, assistance ${level.assistance}';
  }

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) {
    // #region list
    final lines = <String>[
      for (final Difficulty level in Difficulty.offered) _lineFor(level),
    ];
    // #endregion list
    return Container(
      color: const Color(0xFF14161A),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8E8EC), fontSize: 16),
        child: Text(lines.join('\n')),
      ),
    );
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the target marker was not drawn');
    }
    // #region compare
    final onGentle = _incomingDamage(Difficulty.gentle, 10.0);
    final onPunishing = _incomingDamage(Difficulty.punishing, 10.0);
    // #endregion compare
    if (!(onGentle < 10.0 && onPunishing > 10.0)) {
      throw StateError(
        'gentle should soften a hit and punishing should '
        'sharpen it, against the same ten points',
      );
    }
  }
}
