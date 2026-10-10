/// A field of blocks that never move, kept in a cascade atlas of their own,
/// so a walking camera and a rolling ball redraw only what changed.
///
/// Quoted by `static_cascades.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

final class StaticCascadesDemo extends ShowcaseDemo {
  bool blocksAreStatic = true;
  bool walk = true;
  bool roll = true;
  bool showAtlas = false;

  static const int _cascades = 3;

  late final DemoContext _context;
  late final List<MeshNode> _blocks;
  late final MeshNode _ball;
  bool _blocksWere = true;
  double _walked = 0.0;
  double _rolled = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 9.0
      ..pitch = 0.65
      ..yaw = 0.35;
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final Scene scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            const PlaneShape(width: 18, depth: 12).build(),
          ),
          RenderMaterial(
            name: 'ground',
            baseColor: LinearColor.fromSrgb(0.55, 0.55, 0.53, 1.0),
            roughness: 0.9,
            doubleSided: true,
          ),
          name: 'ground',
        )..shadowCasting = ShadowCastingMode.off,
      );

    // #region field
    final DeviceMesh block = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.4, 0.8, 0.4)).build(),
    );
    final RenderMaterial stone = RenderMaterial(
      name: 'stone',
      baseColor: LinearColor.fromSrgb(0.5, 0.48, 0.45, 1.0),
      roughness: 0.85,
    );
    _blocks = <MeshNode>[
      for (var i = 0; i < 12; i++)
        for (var j = 0; j < 5; j++)
          MeshNode(block, stone, name: 'block $i $j')
            ..setPosition(-6.0 + i * 1.1, 0.4, -3.0 + j * 1.2)
            ..shadowIsStatic = true,
    ];
    _blocks.forEach(scene.add);
    // #endregion field

    // #region ball
    _ball = MeshNode(
      DeviceMesh.upload(
        context.device,
        const SphereShape(radius: 0.25, segments: 24, rings: 12).build(),
      ),
      RenderMaterial(
        name: 'clay',
        baseColor: LinearColor.fromSrgb(0.6, 0.32, 0.22, 1.0),
        roughness: 0.7,
      ),
      name: 'ball',
    )..setPosition(0.05, 0.3, -0.6);
    scene.add(_ball);
    // #endregion ball

    // #region sun
    scene.add(
      LightNode(name: 'sun', intensity: 1.8 * Photometric.legacyUnit)
        ..setLocalForward(Vector3(-4.0, -5.0, -0.01).normalized()),
    );
    // #endregion sun
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region walk
    if (walk) {
      _walked += dt;
      context.orbit.target.x = 3.0 * math.sin(0.35 * _walked);
      context.orbit.apply();
    }
    // #endregion walk

    // #region roll
    if (roll) {
      _rolled += dt;
      _ball.setPosition(0.05, 0.3, -0.6 + 2.2 * math.sin(0.8 * _rolled));
    }
    // #endregion roll

    // #region flag
    if (blocksAreStatic != _blocksWere) {
      for (final MeshNode block in _blocks) {
        block.shadowIsStatic = blocksAreStatic;
      }
      _blocksWere = blocksAreStatic;
    }
    // #endregion flag
  }

  @override
  RenderSettings settings(DemoContext context) => RenderSettings(
    // #region settings
    shadows: const ShadowSettings(cascades: _cascades),
    showShadowMap: showAtlas,
    // #endregion settings
  );

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Blocks are static',
      value: () => blocksAreStatic,
      onChanged: (bool v) => blocksAreStatic = v,
    ),
    ToggleControl(
      'Camera walks',
      value: () => walk,
      onChanged: (bool v) => walk = v,
    ),
    ToggleControl(
      'Ball rolls',
      value: () => roll,
      onChanged: (bool v) => roll = v,
    ),
    ToggleControl(
      'Show the sun\'s atlas',
      value: () => showAtlas,
      onChanged: (bool v) => showAtlas = v,
    ),
  ];

  // #region count
  /// What the frame says the sun's atlas cost: every draw into it, casters,
  /// copies and resets alike.
  static int _shadowDraws(FrameResult frame) => frame.passes
      .where((FramePass p) => p.name == 'directional shadows')
      .fold(0, (int sum, FramePass p) => sum + p.drawCalls);
  // #endregion count

  @override
  void verify(Scene scene, FrameResult frame) {
    final int first = _shadowDraws(frame);
    if (first < _blocks.length) {
      throw StateError(
        'the first frame drew $first things into the sun\'s atlas, '
        'fewer than the ${_blocks.length} blocks',
      );
    }
    // #region check
    // The camera stays where it is and only the ball moves.
    _ball.translate(0.0, 0.0, 0.2);
    final int next = _shadowDraws(
      _context.renderer.render(
        width: 320,
        height: 180,
        scene: scene,
        views: views(_context),
        settings: settings(_context),
      ),
    );
    // A copy of the kept tile and the ball, in each cascade at most.
    if (blocksAreStatic && next > 2 * _cascades) {
      throw StateError(
        'moving the ball drew $next things into the sun\'s atlas, '
        'more than a copy and the ball in each of $_cascades cascades',
      );
    }
    // #endregion check
  }
}
