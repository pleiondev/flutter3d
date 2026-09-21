/// Flame's own layer and flutter3d's own layer, drawn side by side and not
/// yet talking to each other — the state every other page in this category
/// starts connecting.
///
/// Quoted by `flame_overview.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_flame/flutter3d_flame.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/flame_layer.dart';

final class FlameOverviewDemo extends ShowcaseDemo {
  late final double _flameX;
  late final double _cubeX;

  late final Scene _scene;
  late final MeshNode _cube;
  late final TransparentFlameGame _game;
  late final Widget _body = flameOrbit(
    _context,
    Flutter3dFlameWidget(
      game: _game,
      camera: _context.camera,
      existing: (device: _context.device, renderer: _context.renderer),
      buildScene: (GraphicsDevice device) => _scene,
    ),
  );
  late final DemoContext _context;
  double _clock = 0.0;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 3.2
      ..pitch = 0.3
      ..yaw = 0.6;
    context.orbit.target.setValues(0.0, 0.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    _context = context;
    final (double flameX, double cubeX) = _run();
    _flameX = flameX;
    _cubeX = cubeX;

    _cube = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(0.8, 0.8, 0.8)).build(),
      ),
      Material(name: 'cube', baseColor: Vector4(0.5, 0.6, 0.8, 1.0)),
      name: 'cube',
    );
    _scene = Scene()
      ..add(_cube)
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region live
    // Built once, kept: the widget below is rebuilt every frame, and a game
    // made afresh each time would restart before it drew anything.
    _game = TransparentFlameGame();
    final _Slider slider = _Slider();
    _game
      ..add(flameCaption('Flame: a component its own game moves'))
      ..add(slider)
      ..add(
        flameCaption(
          'flutter3d: a cube its own scene turns',
          at: Vector2(16.0, 88.0),
        ),
      );
    // #endregion live
    return _scene;
  }

  @override
  void update(DemoContext context, double dt) {
    _clock += dt;
    context.orbit.syncProjectionDepth(context.camera);
    _cube.setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), _clock));
  }

  static (double, double) _run() {
    // #region flame-layer
    // Flame's own layer: a plain PositionComponent, the same class every
    // sprite and shape in a Flame game already is. Nothing here has heard of
    // flutter3d.
    final flameShape = PositionComponent(position: Vector2(2.0, 0.0));
    // #endregion flame-layer

    // #region flutter3d-layer
    // flutter3d's own layer: a cube placed at a spot of its own, on the far
    // side of the origin from the Flame shape. Nothing here has heard of
    // Flame.
    const double cubeX = 9.0;
    // #endregion flutter3d-layer

    // #region unconnected
    // Ticking the Flame side does not move it towards the cube, and moving
    // the cube (above) never touched the Flame shape at all: no bridge sits
    // between them yet. That is every other page in this category, one
    // mechanism at a time.
    flameShape.update(1 / 60);
    final double flameX = flameShape.position.x;
    // #endregion unconnected

    return (flameX, cubeX);
  }

  /// The Flame game the page runs, for a test that steps it without a window.
  @visibleForTesting
  TransparentFlameGame get game => _game;

  @override
  Widget? customBody(BuildContext buildContext, DemoContext context) => _body;

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('the cube marker was not drawn');
    }
    if (_flameX != 2.0) {
      throw StateError(
        'the Flame shape should not have moved on its own, got $_flameX',
      );
    }
    if (_cubeX != 9.0) {
      throw StateError('the flutter3d cube should be at its own spot');
    }
  }
}

/// A square that Flame's own game slides to and fro across the top.
final class _Slider extends PositionComponent {
  _Slider() : super(position: Vector2(16.0, 40.0), size: Vector2.all(36.0));

  double _t = 0.0;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    position.x = 16.0 + 160.0 * (0.5 - 0.5 * math.cos(_t * 1.5));
  }

  @override
  void render(Canvas canvas) =>
      canvas.drawRect(size.toRect(), Paint()..color = const Color(0xFFE8A33D));
}
