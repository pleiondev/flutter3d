/// A level made from a seed and a few rules: rooms laid out by wave function
/// collapse, joined by corridors, the player in one room and the exit in the
/// farthest, and refused unless the exit can be walked to.
///
/// Quoted by `procedural_levels.md` and shown whole in the Source tab.
library;

import 'dart:convert';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/scene_kit.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

final class ProceduralLevelsDemo extends ShowcaseDemo {
  double seed = 7;
  double density = 0.7;

  bool _dirty = true;
  late final DeviceMesh _cube;
  late final MeshNode _player;
  late final MeshNode _exit;
  final SceneNode _rooms = SceneNode(name: 'rooms');
  late Generated _generated;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 78.0
      ..pitch = 1.1
      ..yaw = 0.0;
    context.orbit.target.setValues(32.0, 0.0, 24.0);
  }

  @override
  Scene build(DemoContext context) {
    _cube = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    _player = ballNode(context, 'player', 1.2, Vector4(0.35, 0.9, 0.45, 1.0));
    _exit = ballNode(context, 'exit', 1.2, Vector4(0.95, 0.35, 0.3, 1.0));
    _regenerate();
    return sceneOf(<SceneNode>[_rooms, _player, _exit]);
  }

  // #region rules
  /// Four cells across and three down, sixteen metres each, a room of ten
  /// in each cell the seed makes a room, and corridors three metres wide.
  LevelRules get _rules => LevelRules(density: density);
  // #endregion rules

  // #region generate
  /// The level [seed] makes. When a seed makes nothing playable, the next is
  /// tried, and [Generated.seed] says which one it was.
  Generated _make(int seed) => generateLevel(_rules, seed: seed);
  // #endregion generate

  void _regenerate() {
    _generated = _make(seed.round());
    for (final SceneNode old in _rooms.children) {
      _rooms.remove(old);
    }
    final Level? level = _generated.level;
    if (level == null) return;
    // #region draw
    // The rooms and corridors are recipes; `expandRecipes` turns them into
    // the brushes everything that uses a level reads. The ceilings are left
    // out so the camera sees in.
    for (final Brush brush in expandRecipes(level).brushes) {
      if (brush.material == 'ceiling') continue;
      final bool floor = brush.material == 'floor';
      _rooms.add(
        MeshNode(
            _cube,
            RenderMaterial(
              name: brush.material,
              baseColor: floor
                  ? LinearColor.fromSrgb(0.42, 0.44, 0.47, 1.0)
                  : LinearColor.fromSrgb(0.72, 0.66, 0.56, 1.0),
              roughness: 0.85,
            ),
            name: brush.material,
          )
          ..setPositionFrom(brush.center)
          ..setScale(brush.size.x, brush.size.y, brush.size.z),
      );
    }
    _player.setPositionFrom(
      level.ofType('player_spawn').first.position + Vector3(0, 1.2, 0),
    );
    _exit.setPositionFrom(
      level.ofType('exit').first.position + Vector3(0, 1.2, 0),
    );
    // #endregion draw
  }

  @override
  void update(DemoContext context, double dt) {
    if (!_dirty) return;
    _dirty = false;
    _regenerate();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Seed',
      min: 1,
      max: 64,
      divisions: 63,
      value: () => seed,
      onChanged: (double v) {
        seed = v;
        _dirty = true;
      },
      format: (double v) => '${v.round()}',
    ),
    SliderControl(
      'Room density',
      min: 0.3,
      max: 0.95,
      value: () => density,
      onChanged: (double v) {
        density = v;
        _dirty = true;
      },
      format: (double v) => v.toStringAsFixed(2),
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1 || _rooms.children.isEmpty) {
      throw StateError('no room of the level reached the frame');
    }
    // #region check
    final Generated first = _make(seed.round());
    final Generated again = _make(seed.round());
    final Level level = first.level!;
    if (jsonEncode(level.toJson()) != jsonEncode(again.level!.toJson())) {
      throw StateError('the same seed should make the same level');
    }
    // The generator held the level to this rule already; asking again is
    // what any game that loads a level can do.
    final List<LevelIssue> issues = <LevelIssue>[];
    const ExitReachable().check(level, issues);
    if (issues.any((LevelIssue i) => i.isError)) {
      throw StateError('the exit cannot be walked to: $issues');
    }
    // #endregion check
  }
}
