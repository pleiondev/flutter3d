/// One 3D model in a plain Flame game, between a 2D backdrop and a 2D
/// shape passing in front of it.
///
///     flutter run -t lib/model3d_main.dart
///
/// No [Flutter3dFlameWidget] and no [HasFlutter3d]: a [Model3dComponent]
/// opens what it needs and draws into Flame's canvas, so an ordinary
/// [GameWidget] shows it. Put any `.glb` under `assets/models/` and name it
/// in [_model]; this one is the RobotExpressive sample, whose first clip is
/// the dance it loops here.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame_flutter3d/flame_flutter3d.dart';
import 'package:flutter/material.dart';

const String _model = 'assets/models/RobotExpressive.glb';

void main() => runApp(GameWidget(game: _Stage()));

class _Stage extends FlameGame {
  @override
  Color backgroundColor() => const Color(0xFF1B2433);

  @override
  Future<void> onLoad() async {
    final middle = size / 2;
    await world.addAll(<Component>[
      // Behind the model: priority 0.
      for (var i = 0; i < 6; i++)
        CircleComponent(
          radius: 40.0 + i * 30.0,
          position: Vector2(math.cos(i * 1.1), math.sin(i * 1.1)) * 140.0,
          anchor: Anchor.center,
          paint: Paint()
            ..color = const Color(0xFF2E4A6B).withValues(alpha: 0.5),
        ),
      Model3dComponent(
        model: _model,
        size: Vector2.all(320),
        anchor: Anchor.center,
        priority: 1,
      ),
      // In front of it: priority 2.
      _Passing(span: middle.x)..priority = 2,
    ]);
  }
}

/// A square that crosses the stage in front of the model and back.
class _Passing extends RectangleComponent {
  _Passing({required this.span})
    : super(
        size: Vector2.all(70),
        anchor: Anchor.center,
        paint: Paint()..color = const Color(0xFFF2A541),
      );

  final double span;
  double _time = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    position.setValues(math.sin(_time * 0.8) * span * 0.8, 90);
    angle = _time;
  }
}
