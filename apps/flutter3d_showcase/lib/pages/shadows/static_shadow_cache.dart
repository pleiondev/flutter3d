/// Walls that never move are drawn into a lamp's shadow atlas once and kept;
/// only the things that move are redrawn.
///
/// Quoted by `static_shadow_cache.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class StaticShadowCacheDemo extends ShowcaseDemo {
  bool wallsAreStatic = true;
  bool moverOrbits = true;
  bool showStatic = false;
  bool showMoving = false;

  late final Scene _scene;
  late final List<MeshNode> _walls;
  late final MeshNode _mover;
  bool _wallsWere = true;
  double _angle = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.7
      ..yaw = 0.8;
  }

  @override
  Scene build(DemoContext context) {
    final Material stone = Material(
      name: 'stone',
      baseColor: Vector4(0.78, 0.76, 0.72, 1.0),
      roughness: 0.9,
    );
    final Material floorStone = stone.copy()..doubleSided = true;
    final Material clay = Material(
      name: 'clay',
      baseColor: Vector4(0.85, 0.45, 0.3, 1.0),
      roughness: 0.7,
    );
    _scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 12, depth: 12).build(),
          ),
          floorStone,
          name: 'floor',
        ),
      );

    // #region walls
    _walls = <MeshNode>[
      MeshNode(
        DeviceMesh.upload(
          context.device,
          CuboidShape(size: Vector3(0.3, 3.0, 4.0)).build(),
        ),
        stone,
        name: 'west wall',
      )..setPosition(-2.5, 1.5, 0.0),
      MeshNode(
        DeviceMesh.upload(
          context.device,
          CuboidShape(size: Vector3(4.0, 3.0, 0.3)).build(),
        ),
        stone,
        name: 'north wall',
      )..setPosition(0.0, 1.5, -2.5),
    ];
    for (final MeshNode wall in _walls) {
      wall.shadowIsStatic = true;
      _scene.add(wall);
    }
    // #endregion walls

    // #region mover
    _mover = MeshNode(
      DeviceMesh.upload(
        context.device,
        SphereShape(radius: 0.4, segments: 24, rings: 12).build(),
      ),
      clay,
      name: 'mover',
    );
    _scene.add(_mover);
    // #endregion mover

    _scene.add(
      LightNode(
        name: 'lamp',
        type: LightType.point,
        intensity: 50.0,
        range: 14.0,
        castsShadow: true,
      )..setPosition(0.0, 3.6, 0.0),
    );
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region orbit
    if (moverOrbits) _angle += dt;
    _mover.setPosition(1.4 * math.cos(_angle), 0.6, 1.4 * math.sin(_angle));
    // #endregion orbit

    // #region invalidate
    if (wallsAreStatic != _wallsWere) {
      for (final MeshNode wall in _walls) {
        wall.shadowIsStatic = wallsAreStatic;
      }
      _scene.invalidateStaticShadows();
      _wallsWere = wallsAreStatic;
    }
    // #endregion invalidate
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region atlas
    shadows: const ShadowSettings(cubeResolution: 256),
    showStaticShadowMap: showStatic,
    showShadowMap: showMoving,
    // #endregion atlas
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Walls are static',
      value: () => wallsAreStatic,
      onChanged: (bool v) => wallsAreStatic = v,
    ),
    ToggleControl(
      'Mover circles',
      value: () => moverOrbits,
      onChanged: (bool v) => moverOrbits = v,
    ),
    ToggleControl(
      'Show static atlas',
      value: () => showStatic,
      onChanged: (bool v) {
        showStatic = v;
        if (v) showMoving = false;
      },
    ),
    ToggleControl(
      'Show moving atlas',
      value: () => showMoving,
      onChanged: (bool v) {
        showMoving = v;
        if (v) showStatic = false;
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    final FramePass? bake = frame.passes
        .where((FramePass p) => p.name == 'point shadows (static)')
        .firstOrNull;
    if (bake == null) {
      throw StateError('the static shadow atlas was never baked');
    }
    if (bake.drawCalls < 1) {
      throw StateError('the first frame did not draw the walls into the atlas');
    }
  }
}
