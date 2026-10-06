/// Three balls fired at a wall a centimetre thick, each faster than the wall
/// is thin by a long way: one stopped by the core's soft speculative
/// contacts, one by the hard sweep a bullet gets, and one with neither,
/// which goes through.
///
/// Quoted by `continuous_collision.md` and shown whole in the Source tab.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// One ball: the world it flies in, its body, the lane it flies along and
/// what it is drawn as.
final class _Lane {
  _Lane(this.world, this.ball, this.z, this.mesh, this.trail);

  final NativeWorld world;
  final NativeBody ball;
  final double z;
  final MeshNode mesh;
  final MeshNode trail;
}

final class ContinuousCollisionDemo extends ShowcaseDemo {
  /// Speculative contacts on: the world a new `NativeWorld` is.
  NativeWorld? _soft;

  /// Speculative contacts off, for the bullet and the unprotected ball.
  NativeWorld? _hard;

  final List<_Lane> _lanes = <_Lane>[];

  /// Why there is nothing to fire, or null when the core started.
  String? fallback;

  /// Metres a second the balls leave at.
  double speed = 300.0;

  double _sinceShot = 0.0;

  static const double _step = 1 / 60;
  static const double _radius = 0.05;
  static const double _launchX = -3.0;
  static const double _height = 0.6;

  /// Half the wall's thickness: a centimetre in all.
  static const double _wallHalf = 0.005;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 6.5
      ..pitch = 0.45
      ..yaw = -0.5;
    context.orbit.target.setValues(-0.6, 0.4, 0.0);
  }

  // #region worlds
  /// Two worlds of the core. Speculative contacts are a setting of the
  /// world, on for a new one, so the lane that shows them on lives in a
  /// world of its own, and the two that show them off share the other.
  void _makeWorlds() {
    try {
      _soft = NativeWorld()..gravity = Vector3.zero();
      _hard = NativeWorld()
        ..gravity = Vector3.zero()
        ..speculative = false;
    } on Object catch (e) {
      _soft?.dispose();
      _soft = null;
      _hard = null;
      fallback = physicsCoreLoaded
          ? '$e'
          : 'the core is not loaded in this browser yet';
    }
  }
  // #endregion worlds

  // #region lanes
  /// A fixed wall a centimetre thick across [world], and a small ball in
  /// front of it at [z], made a bullet when [bullet] is set.
  static NativeBody _wallAndBall(
    NativeWorld world,
    double z, {
    required bool bullet,
  }) {
    final NativeBody wall = world.addBody(
      position: Vector3(0.0, _height, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(wall, NativeShape.box(Vector3(_wallHalf, 0.6, 1.2)));
    final NativeBody ball = world.addBody(
      position: Vector3(_launchX, _height, z),
      mass: 0.03,
    );
    world.setShape(ball, const NativeShape.sphere(_radius));
    // Hard continuous collision: swept from where the step began to where it
    // ended, and put back at the first thing it met.
    if (bullet) world.setBullet(ball);
    return ball;
  }
  // #endregion lanes

  /// The wall in the soft world is added once, with its ball; the hard
  /// world's wall stands for both of its balls.
  void _buildLanes(DemoContext context, Scene scene) {
    final NativeWorld soft = _soft!;
    final NativeWorld hard = _hard!;
    final NativeBody softBall = _wallAndBall(soft, -0.7, bullet: false);
    final NativeBody bulletBall = _wallAndBall(hard, 0.0, bullet: true);
    final NativeBody plainBall = hard.addBody(
      position: Vector3(_launchX, _height, 0.7),
      mass: 0.03,
    );
    hard.setShape(plainBall, const NativeShape.sphere(_radius));

    final DeviceMesh sphere = DeviceMesh.upload(
      context.device,
      const SphereShape(radius: _radius, segments: 16, rings: 8).build(),
    );
    final DeviceMesh unit = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(1.0)).build(),
    );
    for (final (NativeWorld world, NativeBody ball, double z, Vector3 colour)
        in <(NativeWorld, NativeBody, double, Vector3)>[
          (soft, softBall, -0.7, Vector3(0.35, 0.85, 0.45)),
          (hard, bulletBall, 0.0, Vector3(0.95, 0.7, 0.25)),
          (hard, plainBall, 0.7, Vector3(0.95, 0.3, 0.3)),
        ]) {
      final mesh = MeshNode(
        sphere,
        Material(
          name: 'ball $z',
          baseColor: Vector4(colour.x, colour.y, colour.z, 1.0),
          emissive: colour * 0.4,
        ),
        name: 'ball $z',
      );
      final trail = MeshNode(
        unit,
        Material(
          name: 'trail $z',
          baseColor: Vector4(colour.x, colour.y, colour.z, 1.0),
          emissive: colour * 0.8,
        ),
        name: 'trail $z',
      );
      scene
        ..add(mesh)
        ..add(trail);
      _lanes.add(_Lane(world, ball, z, mesh, trail));
    }
  }

  // #region fire
  /// Every ball back at the line and off again at [speed].
  void _fire() {
    for (final _Lane lane in _lanes) {
      lane.world
        ..setPosition(lane.ball, Vector3(_launchX, _height, lane.z))
        ..setAngularVelocity(lane.ball, Vector3.zero())
        ..setVelocity(lane.ball, Vector3(speed, 0.0, 0.0))
        ..wake(lane.ball);
    }
    _sinceShot = 0.0;
  }
  // #endregion fire

  @override
  void dispose() {
    _soft?.dispose();
    _hard?.dispose();
  }

  @override
  Scene build(DemoContext context) {
    _makeWorlds();
    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.7, -0.4)),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(8.0, 0.1, 2.6)).build(),
          ),
          Material(name: 'ground', baseColor: Vector4(0.3, 0.32, 0.35, 1.0)),
          name: 'ground',
        )..setPosition(-0.5, -0.05, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(2 * _wallHalf, 1.2, 2.4)).build(),
          ),
          Material(name: 'wall', baseColor: Vector4(0.75, 0.78, 0.82, 1.0)),
          name: 'wall',
        )..setPosition(0.0, _height, 0.0),
      );
    if (_soft != null) {
      _buildLanes(context, scene);
      _fire();
      _place();
    }
    return scene;
  }

  /// Each ball where its world has it, and a streak from the line to it so
  /// a ball too fast to see in a frame leaves its path behind.
  void _place() {
    for (final _Lane lane in _lanes) {
      final Vector3 p = lane.world.positionOf(lane.ball);
      lane.mesh.setPosition(p.x, p.y, p.z);
      final double end = p.x.clamp(_launchX, 3.0);
      final double length = end - _launchX;
      lane.trail
        ..visible = length > 0.01
        ..setPosition(_launchX + 0.5 * length, p.y, lane.z)
        ..setScale(length, 0.012, 0.012);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    if (_soft == null) return;
    // #region step
    _soft!.step(_step);
    _hard!.step(_step);
    // #endregion step
    _sinceShot += dt;
    if (_sinceShot > 1.5) _fire();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    SliderControl(
      'Speed',
      min: 50.0,
      max: 600.0,
      value: () => speed,
      onChanged: (double v) => speed = v,
      format: (double v) => '${v.round()} m/s',
    ),
    ToggleControl(
      fallback == null ? 'Fire again' : 'Fire again (unavailable: $fallback)',
      value: () => false,
      onChanged: (bool v) {
        if (v && _soft != null) _fire();
      },
    ),
  ];

  /// Where each ball is along x after [steps] steps from a fresh shot: the
  /// soft one, the bullet, the unprotected one.
  @visibleForTesting
  List<double> shoot({int steps = 30}) {
    _fire();
    for (var i = 0; i < steps; i++) {
      _soft!.step(_step);
      _hard!.step(_step);
    }
    return <double>[
      for (final _Lane lane in _lanes) lane.world.positionOf(lane.ball).x,
    ];
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (_soft == null) throw StateError('the core did not start: $fallback');
    // #region check
    // At three hundred metres a second a ball goes five metres a step, five
    // hundred times the wall's thickness. The soft ball and the bullet have
    // to end on the near side of it, the ball with neither on the far side.
    speed = 300.0;
    final [double soft, double bullet, double plain] = shoot();
    if (soft >= 0.0) {
      throw StateError('the soft ball went through, to x = $soft');
    }
    if (bullet >= 0.0) {
      throw StateError('the bullet went through, to x = $bullet');
    }
    if (plain <= 0.0) {
      throw StateError('the unprotected ball stopped at x = $plain');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
