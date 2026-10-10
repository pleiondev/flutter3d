/// The core's joints in a row: a hinge swinging into its limits, a slider
/// driven by a motor, a ball joint held in a cone, and one distance joint
/// three ways, as a rod, a spring and a rope.
///
/// Quoted by `joints_and_motors.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';

/// Everything the row is made of in one world: the joints, and the bodies
/// they hold, in the order the scene draws them.
final class _Row {
  _Row(this.world);

  final NativeWorld world;
  late final NativeJoint hinge, slider, ball, rod, spring, rope;
  late final NativeBody arm, cart, limb, rodWeight, springWeight, ropeWeight;

  List<NativeBody> get moving => <NativeBody>[
    arm,
    cart,
    limb,
    rodWeight,
    springWeight,
    ropeWeight,
  ];
}

final class JointsAndMotorsDemo extends ShowcaseDemo {
  _Row? _row;

  /// Why nothing moves: the core would not start. Null when it did.
  String? unavailable;

  final List<MeshNode> _meshes = <MeshNode>[];
  final List<MeshNode> _cords = <MeshNode>[];
  double _age = 0.0;
  double _speed = 0.6;

  static const double _step = 1 / 60;

  /// Where each station's fixed point is.
  static Vector3 get _hingeAt => Vector3(-5.0, 3.0, 0.0);
  static Vector3 get _railAt => Vector3(-3.0, 1.5, 0.0);
  static Vector3 get _shoulderAt => Vector3(-1.0, 3.0, 0.0);
  static final List<Vector3> _hooks = <Vector3>[
    Vector3(1.0, 3.0, 0.0),
    Vector3(3.0, 3.0, 0.0),
    Vector3(5.0, 3.0, 0.0),
  ];

  static const double _limit = 0.5;
  static const double _travel = 0.8;
  static const double _cone = 0.6;
  static const double _twist = 0.3;
  static const double _rodLength = 1.5;
  static const double _ropeLength = 1.5;
  static const ({double length, double least, double most}) _springLength = (
    length: 1.2,
    least: 0.6,
    most: 1.8,
  );

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 13.0
      ..pitch = 0.15
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 2.0, 0.0);
  }

  static NativeBody _fixed(NativeWorld w, Vector3 at) =>
      w.addBody(position: at, type: NativeBodyType.fixed, mass: 0.0);

  // #region hinge
  /// A bar hung from a pin, free to turn about z but only half a radian
  /// either way, and started swinging hard enough to reach both stops.
  static void _hinge(_Row row) {
    final NativeWorld w = row.world;
    final NativeBody pin = _fixed(w, _hingeAt);
    row.arm = w.addBody(position: _hingeAt - Vector3(0.0, 0.6, 0.0), mass: 2.0);
    w.setShape(row.arm, NativeShape.box(Vector3(0.06, 0.6, 0.06)));
    row.hinge = w.createJoint(
      NativeJointType.revolute,
      pin,
      row.arm,
      anchor: _hingeAt,
      axis: Vector3(0.0, 0.0, 1.0),
    );
    w
      ..setJointLimits(row.hinge, (lower: -_limit, upper: _limit))
      // Five radians a second about the pin; its centre, 0.6 m below,
      // moves at three metres a second.
      ..setAngularVelocity(row.arm, Vector3(0.0, 0.0, 5.0))
      ..setVelocity(row.arm, Vector3(3.0, 0.0, 0.0));
  }
  // #endregion hinge

  // #region slider
  /// A carriage on a rail along x, its travel limited to 0.8 m each way
  /// and a motor driving it at [speed] with at most forty newtons.
  static void _slider(_Row row, double speed) {
    final NativeWorld w = row.world;
    final NativeBody rail = _fixed(w, _railAt);
    row.cart = w.addBody(position: _railAt.clone(), mass: 1.0);
    w.setShape(row.cart, NativeShape.box(Vector3(0.15, 0.1, 0.15)));
    row.slider = w.createJoint(
      NativeJointType.prismatic,
      rail,
      row.cart,
      anchor: _railAt,
      axis: Vector3(1.0, 0.0, 0.0),
    );
    w
      ..setJointLimits(row.slider, (lower: -_travel, upper: _travel))
      ..setJointMotor(row.slider, (speed: speed, maxForce: 40.0));
  }

  /// Turns the motor round at either end of the rail, so the carriage runs
  /// back and forth.
  void _drive(_Row row) {
    final double at = row.world.jointValue(row.slider);
    if (at > _travel - 0.05 && _speed > 0 ||
        at < -_travel + 0.05 && _speed < 0) {
      _speed = -_speed;
      row.world.setJointMotor(row.slider, (speed: _speed, maxForce: 40.0));
    }
  }
  // #endregion slider

  // #region ball
  /// A limb hung from a ball joint: it swings any way, but its axis stays
  /// within 0.6 rad of straight down, its twist about itself within ±0.3,
  /// and a little friction lets it settle.
  static void _ball(_Row row) {
    final NativeWorld w = row.world;
    final NativeBody shoulder = _fixed(w, _shoulderAt);
    row.limb = w.addBody(position: _shoulderAt - Vector3(0.0, 0.5, 0.0));
    w.setShape(row.limb, NativeShape.box(Vector3(0.05, 0.5, 0.05)));
    row.ball = w.createJoint(
      NativeJointType.spherical,
      shoulder,
      row.limb,
      anchor: _shoulderAt,
      axis: Vector3(0.0, -1.0, 0.0),
    );
    w
      ..setJointCone(row.ball, _cone)
      ..setJointLimits(row.ball, (lower: -_twist, upper: _twist))
      ..setJointFriction(row.ball, 0.2)
      ..setVelocity(row.limb, Vector3(4.0, 0.0, 2.0))
      ..setAngularVelocity(row.limb, Vector3(-4.0, 8.0, 8.0));
  }
  // #endregion ball

  // #region distance
  /// One distance joint, made three ways. It is made at the length between
  /// its two points now, which is a rod. A spring is the same joint with a
  /// rest length, a least and a most, and a frequency. A rope is a spring
  /// of nought hertz that may be anything from nought to its most: slack
  /// until it is taut.
  static void _distances(_Row row) {
    final NativeWorld w = row.world;
    NativeJoint hang(Vector3 hook, NativeBody weight) => w.createDistanceJoint(
      _fixed(w, hook),
      weight,
      anchorA: hook,
      anchorB: w.localPositionOf(weight),
    );
    NativeBody weight(Vector3 at) {
      final NativeBody b = w.addBody(position: at);
      w.setShape(b, const NativeShape.sphere(0.15));
      return b;
    }

    // A rod 1.5 m long, the weight pushed sideways.
    row.rodWeight = weight(_hooks[0] - Vector3(0.0, _rodLength, 0.0));
    row.rod = hang(_hooks[0], row.rodWeight);
    w.setVelocity(row.rodWeight, Vector3(3.0, 0.0, 0.0));

    // A spring that rests at 1.2 m, let go stretched to 1.5.
    row.springWeight = weight(_hooks[1] - Vector3(0.0, 1.5, 0.0));
    row.spring = hang(_hooks[1], row.springWeight);
    w
      ..setJointLength(
        row.spring,
        length: _springLength.length,
        least: _springLength.least,
        most: _springLength.most,
      )
      ..setJointSpring(row.spring, (hertz: 1.2, damping: 0.05));

    // A rope 1.5 m long, its weight let go beside the hook: it falls
    // slack until the rope catches it.
    row.ropeWeight = weight(_hooks[2] + Vector3(0.3, -0.2, 0.0));
    row.rope = hang(_hooks[2], row.ropeWeight);
    w
      ..setJointLength(
        row.rope,
        length: _ropeLength,
        least: 0.0,
        most: _ropeLength,
      )
      ..setJointSpring(row.rope, (hertz: 0.0, damping: 0.0))
      ..setVelocity(row.ropeWeight, Vector3(1.0, 0.0, 0.0));
  }
  // #endregion distance

  /// A new world with the whole row in it, or null when the core will not
  /// start, with the reason kept in [unavailable].
  _Row? _build() {
    unavailable = null;
    if (!physicsCoreLoaded) {
      unavailable = 'the core is not loaded in this browser yet';
      return null;
    }
    final NativeWorld world;
    try {
      world = NativeWorld();
    } on Object catch (e) {
      unavailable = '$e';
      return null;
    }
    _speed = 0.6;
    final row = _Row(world);
    _hinge(row);
    _slider(row, _speed);
    _ball(row);
    _distances(row);
    return row;
  }

  void _restart() {
    _row?.world.dispose();
    _row = _build();
    _age = 0.0;
  }

  @override
  void dispose() => _row?.world.dispose();

  @override
  Scene build(DemoContext context) {
    _row = _build();
    final Scene scene = Scene()
      ..ambientColor = LinearColor(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.3 * Photometric.legacyUnit
      ..add(
        LightNode(name: 'sun', intensity: 2.5 * Photometric.legacyUnit)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.5)),
      );
    DeviceMesh upload(MeshData data) => DeviceMesh.upload(context.device, data);
    RenderMaterial paint(String name, double r, double g, double b) =>
        RenderMaterial(
          name: name,
          baseColor: LinearColor.fromSrgb(r, g, b, 1.0),
          roughness: 0.6,
        );

    scene.add(
      MeshNode(
        upload(CuboidShape(size: Vector3(13.0, 0.1, 3.0)).build()),
        paint('floor', 0.42, 0.44, 0.47),
        name: 'floor',
      )..setPosition(0.0, -0.05, 0.0),
    );
    // The fixed points: a pin, a rail, a shoulder and three hooks.
    final DeviceMesh pin = upload(const SphereShape(radius: 0.07).build());
    final RenderMaterial steel = paint('steel', 0.3, 0.32, 0.36);
    for (final Vector3 at in <Vector3>[_hingeAt, _shoulderAt, ..._hooks]) {
      scene.add(MeshNode(pin, steel, name: 'pin')..setPositionFrom(at));
    }
    scene.add(
      MeshNode(
        upload(
          CuboidShape(size: Vector3(2 * _travel + 0.3, 0.04, 0.04)).build(),
        ),
        steel,
        name: 'rail',
      )..setPosition(_railAt.x, _railAt.y - 0.12, _railAt.z),
    );
    // The moving bodies, in the order [_Row.moving] gives them.
    final DeviceMesh ball = upload(const SphereShape(radius: 0.15).build());
    _meshes.addAll(<MeshNode>[
      MeshNode(
        upload(CuboidShape(size: Vector3(0.12, 1.2, 0.12)).build()),
        paint('hinged bar', 0.8, 0.55, 0.3),
        name: 'hinged bar',
      ),
      MeshNode(
        upload(CuboidShape(size: Vector3(0.3, 0.2, 0.3)).build()),
        paint('carriage', 0.35, 0.6, 0.8),
        name: 'carriage',
      ),
      MeshNode(
        upload(CuboidShape(size: Vector3(0.1, 1.0, 0.1)).build()),
        paint('limb', 0.75, 0.45, 0.55),
        name: 'limb',
      ),
      MeshNode(ball, paint('rod weight', 0.55, 0.55, 0.6), name: 'rod weight'),
      MeshNode(ball, paint('spring weight', 0.4, 0.7, 0.4), name: 'spring'),
      MeshNode(ball, paint('rope weight', 0.8, 0.7, 0.35), name: 'rope weight'),
    ]);
    // A cord from each hook to its weight, a unit cylinder stretched.
    final DeviceMesh cord = upload(
      const CylinderShape(
        radiusTop: 0.02,
        radiusBottom: 0.02,
        height: 1.0,
      ).build(),
    );
    _cords.addAll(<MeshNode>[
      MeshNode(cord, steel, name: 'rod'),
      MeshNode(cord, paint('spring', 0.3, 0.6, 0.3), name: 'spring'),
      MeshNode(cord, paint('rope', 0.6, 0.5, 0.3), name: 'rope'),
    ]);
    _meshes.forEach(scene.add);
    _cords.forEach(scene.add);
    _place();
    return scene;
  }

  /// Every mesh where its body is, and every cord from its hook to its
  /// weight.
  void _place() {
    final _Row? row = _row;
    if (row == null) return;
    final List<NativeBody> moving = row.moving;
    for (var i = 0; i < moving.length; i++) {
      _meshes[i]
        ..setPositionFrom(row.world.localPositionOf(moving[i]))
        ..setRotation(row.world.orientationOf(moving[i]));
    }
    final List<NativeBody> weights = moving.sublist(3);
    for (var i = 0; i < _cords.length; i++) {
      final Vector3 to = row.world.localPositionOf(weights[i]);
      final Vector3 along = to - _hooks[i];
      _cords[i]
        ..setPositionFrom((to + _hooks[i]) * 0.5)
        ..setRotation(
          Quaternion.fromTwoVectors(Vector3(0.0, 1.0, 0.0), along.normalized()),
        )
        ..setScale(1.0, along.length, 1.0);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    final _Row? row = _row;
    if (row == null) return;
    // #region step
    _drive(row);
    row.world.step(_step);
    // #endregion step
    _age += dt;
    if (_age > 12.0) _restart();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      unavailable == null
          ? 'Start again'
          : 'Start again (the core is unavailable: $unavailable)',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    // Where the core does not start there is nothing to hold it to; the
    // control says why.
    if (unavailable != null) return;
    // #region check
    // Six seconds from the start, every joint read after every step.
    _restart();
    final _Row row = _row!;
    final NativeWorld w = row.world;
    var hinge = 0.0, swing = 0.0, twist = 0.0, rod = 0.0;
    var ropeLeast = double.infinity, ropeMost = 0.0;
    var springLeast = double.infinity, springMost = 0.0;
    var cartSpeed = 0.0;
    for (var i = 0; i < 360; i++) {
      _drive(row);
      w.step(_step);
      hinge = math.max(hinge, w.jointValue(row.hinge).abs());
      swing = math.max(swing, w.jointSwing(row.ball));
      twist = math.max(twist, w.jointValue(row.ball).abs());
      rod = math.max(rod, (w.jointValue(row.rod) - _rodLength).abs());
      ropeLeast = math.min(ropeLeast, w.jointValue(row.rope));
      ropeMost = math.max(ropeMost, w.jointValue(row.rope));
      springLeast = math.min(springLeast, w.jointValue(row.spring));
      springMost = math.max(springMost, w.jointValue(row.spring));
      // Two thirds of a second in, the carriage is halfway along the rail.
      if (i == 40) cartSpeed = w.velocityOf(row.cart).x;
    }
    void claim(bool holds, String what) {
      if (!holds) throw StateError(what);
    }

    // The hinge reaches its stops and never goes more than 2° past them.
    claim(hinge > _limit - 0.1, 'the hinge never reached its limits: $hinge');
    claim(hinge < _limit + 0.035, 'the hinge went past its limits: $hinge');
    // The slider runs at the motor's speed.
    claim((cartSpeed - 0.6).abs() < 0.01, 'the slider ran at $cartSpeed m/s');
    // The ball joint swings out to its cone and stays in it, and its twist
    // in its limits.
    claim(swing > _cone - 0.15 && swing < _cone + 0.05, 'swing $swing');
    claim(twist > _twist - 0.1 && twist < _twist + 0.05, 'twist $twist');
    // The rod holds its length to 5 mm; the rope is slack, then taut, and
    // never longer than itself; the spring stays between its least and most.
    claim(rod < 0.005, 'the rod changed length by $rod m');
    claim(ropeLeast < 1.0, 'the rope was never slack: $ropeLeast');
    claim(ropeMost > _ropeLength - 0.01, 'the rope never went taut');
    claim(ropeMost < _ropeLength + 0.005, 'the rope stretched to $ropeMost');
    claim(
      springLeast >= _springLength.least && springMost <= _springLength.most,
      'the spring went from $springLeast to $springMost m',
    );
    claim(springMost - springLeast > 0.1, 'the spring never moved');
    // #endregion check
  }
}
