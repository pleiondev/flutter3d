/// Four axes a genre applies where it decides: what the player is hurt by,
/// what their own attacks are worth, how quickly the opposition reacts, and
/// how much help is switched on.
///
/// Quoted by `difficulty.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

final class DifficultyDemo extends ShowcaseDemo {
  int level = 0;

  late final MeshNode _player;
  late final MeshNode _enemy;
  late final BarGauge _health;
  double _hp = 100.0;
  double _swing = 0.0;
  bool _struck = false;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.45
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _player = blockNode(
      context,
      'player',
      Vector3(0.9, 1.6, 0.9),
      Vector4(0.45, 0.65, 0.95, 1.0),
      at: Vector3(-2.5, 0.8, 0.0),
    );
    _enemy = ballNode(
      context,
      'opponent',
      0.6,
      Vector4(0.85, 0.35, 0.3, 1.0),
      at: Vector3(2.5, 0.6, 0.0),
    );
    _health = BarGauge(
      context,
      'health',
      Vector4(0.4, 0.85, 0.4, 1.0),
      Vector3(-3.5, 2.6, 0.0),
      height: 2.0,
    );
    return sceneOf(<SceneNode>[
      floorNode(context, width: 12.0, depth: 6.0),
      _player,
      _enemy,
      ..._health.nodes,
    ]);
  }

  @override
  void update(DemoContext context, double dt) {
    final Difficulty difficulty = Difficulty.offered[level];
    // The opponent lunges once a swing; a quicker opponent swings sooner.
    _swing += dt * difficulty.opponentReaction * 0.6;
    if (_swing >= 1.0) {
      _swing -= 1.0;
      _struck = false;
    }
    // Out to the player and back, hitting at the far end.
    final double reach = math.sin(math.pi * _swing.clamp(0.0, 1.0));
    _enemy.setPosition(2.5 - 4.2 * reach, 0.6, 0.0);
    if (!_struck && reach > 0.97) {
      _struck = true;
      // #region hit
      // The same ten-point hit as ever, scaled by the level.
      _hp -= _incomingDamage(difficulty, 10.0);
      // #endregion hit
      if (_hp <= 0.0) _hp = 100.0;
    }
    _health.set(_hp / 100.0);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Difficulty',
      options: <String>[for (final Difficulty d in Difficulty.offered) d.name],
      index: () => level,
      onChanged: (int i) {
        level = i;
        _hp = 100.0;
      },
    ),
  ];

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

  /// One line for each level on offer, as the settings screen would list them.
  static List<String> lines() {
    // #region list
    final lines = <String>[
      for (final Difficulty level in Difficulty.offered) _lineFor(level),
    ];
    // #endregion list
    return lines;
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
