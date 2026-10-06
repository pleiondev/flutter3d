/// A car on four springs, driven round a loop by a simple driver on the
/// physics core: a box chassis, four wheels that are rays cast down from
/// it, a plank across the road to bump over, and a road that can be
/// tarmac or ice.
///
/// Quoted by `vehicle.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class VehicleDemo extends ShowcaseDemo {
  NativeWorld? _world;
  NativeBody? _chassis;
  NativeVehicle? _car;

  /// Why there is no car, or null when there is one.
  String? fallback;

  /// What the driver asks for: the steering angle along the car's middle,
  /// radians to the left, and the speed to hold, m/s.
  double steer = 0.25;
  double speed = 6.0;
  bool braking = false;

  /// Tarmac or ice: the tyres' grip.
  bool icy = false;

  late MeshNode _body;
  late MeshNode _cabin;
  final List<MeshNode> _tyres = <MeshNode>[];
  final List<MeshNode> _spokes = <MeshNode>[];
  final List<Material> _tyrePaint = <Material>[];

  static const double _step = 1 / 60;
  static const double _mass = 1200.0;
  static const double _stiffness = 30000.0;

  /// Front to back between the axles, and side to side between the wheels.
  static const double _wheelbase = 2.6;
  static const double _track = 1.6;

  /// Where the plank lies across the loop: the far side of the circle the
  /// default steering drives.
  static Vector3 get _plank => Vector3(20.4, 0.04, 0.0);

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 16.0
      ..pitch = 0.45
      ..yaw = 0.6;
    context.orbit.target.setValues(0.0, 0.8, 0.0);
  }

  NativeWorld? _open() {
    fallback = null;
    if (!physicsCoreLoaded) {
      fallback = 'the core is not loaded in this browser yet';
      return null;
    }
    try {
      return NativeWorld();
    } on Object catch (e) {
      fallback = '$e';
      return null;
    }
  }

  // #region road
  /// A floor, a plank across the loop, and a chassis of 1200 kg at the
  /// start, facing +z.
  void _restart() {
    _world?.dispose();
    final NativeWorld? world = _world = _open();
    if (world == null) return;
    final NativeBody floor = world.addBody(
      position: Vector3(0.0, -0.5, 0.0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(floor, NativeShape.box(Vector3(60.0, 0.5, 60.0)));
    final NativeBody plank = world.addBody(
      position: _plank,
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world.setShape(plank, NativeShape.box(Vector3(2.0, 0.04, 0.3)));
    final NativeBody chassis = _chassis = world.addBody(
      position: Vector3(0.0, 1.0, 0.0),
      mass: _mass,
    );
    world.setShape(chassis, NativeShape.box(Vector3(0.9, 0.3, 2.0)));
    _fit();
  }
  // #endregion road

  // #region wheels
  /// Puts the car's four wheels under its chassis, for the road's grip.
  /// Up is the chassis's +y and forward its +z; wheels 0 and 1 are the
  /// front pair, right then left, and 2 and 3 the rear.
  void _fit() {
    final NativeWorld world = _world!;
    final NativeBody chassis = _chassis!;
    if (_car case final NativeVehicle old) world.removeVehicle(old);
    final NativeVehicle car = _car = world.createVehicle(
      chassis,
      up: Vector3(0.0, 1.0, 0.0),
      forward: Vector3(0.0, 0.0, 1.0),
    );
    for (final (double x, double z) in const <(double, double)>[
      (-0.8, 1.3),
      (0.8, 1.3),
      (-0.8, -1.3),
      (0.8, -1.3),
    ]) {
      world.addWheel(car, (
        attach: Vector3(x, -0.2, z),
        rest: 0.4,
        radius: 0.35,
        stiffness: _stiffness,
        damping: 3000.0,
        grip: icy ? 0.1 : 1.0,
      ));
    }
  }
  // #endregion wheels

  // #region drive
  /// One step of the driver, then one of the world. The front wheels steer
  /// about the same point on the line of the rear axle, the inner one more;
  /// the rear wheels push to hold [speed]; the brake holds all four.
  void _drive() {
    final NativeWorld world = _world!;
    final NativeVehicle car = _car!;
    final NativeBody chassis = _chassis!;
    var right = 0.0;
    var left = 0.0;
    if (steer != 0.0) {
      final double radius = _wheelbase / math.tan(steer);
      right = math.atan(_wheelbase / (radius + _track / 2));
      left = math.atan(_wheelbase / (radius - _track / 2));
    }
    final Vector3 forward = world
        .orientationOf(chassis)
        .asRotationMatrix()
        .transformed(Vector3(0.0, 0.0, 1.0));
    final double going = world.velocityOf(chassis).dot(forward);
    final double push = braking
        ? 0.0
        : (800.0 * (speed - going)).clamp(-2400.0, 2400.0);
    final double brake = braking ? 4000.0 : 0.0;
    world
      ..setWheel(car, 0, steer: right, brake: brake)
      ..setWheel(car, 1, steer: left, brake: brake)
      ..setWheel(car, 2, drive: push, brake: brake)
      ..setWheel(car, 3, drive: push, brake: brake)
      ..step(_step);
  }
  // #endregion drive

  @override
  void dispose() => _world?.dispose();

  @override
  Scene build(DemoContext context) {
    _restart();
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
            CuboidShape(size: Vector3(120.0, 1.0, 120.0)).build(),
          ),
          Material(name: 'road', baseColor: Vector4(0.36, 0.38, 0.4, 1.0)),
          name: 'road',
        )..setPosition(0.0, -0.5, 0.0),
      )
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(4.0, 0.08, 0.6)).build(),
          ),
          Material(name: 'plank', baseColor: Vector4(0.62, 0.45, 0.28, 1.0)),
          name: 'plank',
        )..setPositionFrom(_plank),
      );
    // Posts inside and outside the loop, so the car's motion reads against
    // something. They are only drawn: the car never reaches them.
    final DeviceMesh post = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.25, 0.8, 0.25)).build(),
    );
    final postPaint = Material(
      name: 'post',
      baseColor: Vector4(0.9, 0.85, 0.75, 1.0),
    );
    for (var i = 0; i < 24; i++) {
      final double a = i * math.pi / 12;
      for (final double r in <double>[6.0, 15.0]) {
        scene.add(
          MeshNode(post, postPaint, name: 'post $r $i')
            ..setPosition(10.2 + r * math.cos(a), 0.4, r * math.sin(a)),
        );
      }
    }
    final paint = Material(
      name: 'chassis',
      baseColor: Vector4(0.75, 0.2, 0.15, 1.0),
      roughness: 0.4,
    );
    _body = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(1.8, 0.6, 4.0)).build(),
      ),
      paint,
      name: 'chassis',
    );
    _cabin = MeshNode(
      DeviceMesh.upload(
        context.device,
        CuboidShape(size: Vector3(1.5, 0.45, 1.9)).build(),
      ),
      Material(name: 'cabin', baseColor: Vector4(0.2, 0.25, 0.3, 1.0)),
      name: 'cabin',
    );
    scene
      ..add(_body)
      ..add(_cabin);
    final DeviceMesh tyre = DeviceMesh.upload(
      context.device,
      const CylinderShape(
        radiusTop: 0.35,
        radiusBottom: 0.35,
        height: 0.25,
        segments: 24,
      ).build(),
    );
    final DeviceMesh spoke = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3(0.27, 0.6, 0.1)).build(),
    );
    final spokePaint = Material(
      name: 'spoke',
      baseColor: Vector4(0.85, 0.85, 0.8, 1.0),
    );
    for (var i = 0; i < 4; i++) {
      final tyrePaint = Material(
        name: 'tyre $i',
        baseColor: Vector4(0.08, 0.08, 0.08, 1.0),
        roughness: 0.9,
      );
      _tyrePaint.add(tyrePaint);
      _tyres.add(MeshNode(tyre, tyrePaint, name: 'tyre $i'));
      _spokes.add(MeshNode(spoke, spokePaint, name: 'spoke $i'));
      scene
        ..add(_tyres[i])
        ..add(_spokes[i]);
    }
    _place(context);
    return scene;
  }

  // #region draw
  /// The chassis where the core has it, and each wheel at its centre,
  /// turned by its steering about the chassis's up and by its rotation
  /// about its axle. A tyre past its grip turns red.
  void _place(DemoContext context) {
    final NativeWorld? world = _world;
    if (world == null) return;
    final Vector3 at = world.positionOf(_chassis!);
    final Quaternion turn = world.orientationOf(_chassis!);
    final Matrix3 frame = turn.asRotationMatrix();
    final Vector3 roof = at + frame.transformed(Vector3(0.0, 0.5, -0.3));
    _body
      ..setPositionFrom(at)
      ..setRotation(turn);
    _cabin
      ..setPositionFrom(roof)
      ..setRotation(turn);
    final List<NativeWheelState> wheels = world.wheelsOf(_car!);
    for (var i = 0; i < wheels.length; i++) {
      final NativeWheelState w = wheels[i];
      final Quaternion rolled =
          turn *
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), w.steer) *
          Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), w.rotation);
      _spokes[i]
        ..setPositionFrom(w.centre)
        ..setRotation(rolled);
      _tyres[i]
        ..setPositionFrom(w.centre)
        // The cylinder stands along its y; its axle is the wheel's x.
        ..setRotation(
          rolled * Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), math.pi / 2),
        );
      final double slide = math.min(w.skid, 1.0);
      _tyrePaint[i].baseColor.setValues(0.08 + 0.8 * slide, 0.08, 0.08, 1.0);
    }
    context.orbit.target.setValues(at.x, 0.8, at.z);
    context.orbit.apply();
  }
  // #endregion draw

  @override
  void update(DemoContext context, double dt) {
    final NativeWorld? world = _world;
    if (world == null) return;
    _drive();
    // Off the road, or on its roof: start again.
    final Vector3 at = world.positionOf(_chassis!);
    final double up = world
        .orientationOf(_chassis!)
        .asRotationMatrix()
        .transformed(Vector3(0.0, 1.0, 0.0))
        .y;
    if (at.y < -2.0 || at.x.abs() > 55.0 || at.z.abs() > 55.0 || up < 0.2) {
      _restart();
    }
    _place(context);
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ChoiceControl(
      'Road',
      options: const <String>['Tarmac', 'Ice'],
      index: () => icy ? 1 : 0,
      onChanged: (int i) {
        icy = i == 1;
        // The same car, its wheels fitted again for the new grip.
        if (_world != null) _fit();
      },
    ),
    SliderControl(
      'Steering',
      min: -0.4,
      max: 0.4,
      value: () => steer,
      onChanged: (double v) => steer = v,
      format: (double v) => v == 0.0
          ? 'straight'
          : '${v.abs().toStringAsFixed(2)} rad ${v > 0 ? 'left' : 'right'}',
    ),
    SliderControl(
      'Speed',
      min: -4.0,
      max: 12.0,
      value: () => speed,
      onChanged: (double v) => speed = v,
      format: (double v) => '${v.toStringAsFixed(1)} m/s',
    ),
    ToggleControl('Brake', value: () => braking, onChanged: (v) => braking = v),
    ToggleControl(
      fallback == null ? 'Start again' : 'Unavailable: $fallback',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  /// Where the chassis is and which way it faces, for the check.
  ({Vector3 at, Vector3 forward}) get _pose {
    final NativeWorld world = _world!;
    return (
      at: world.positionOf(_chassis!),
      forward: world
          .orientationOf(_chassis!)
          .asRotationMatrix()
          .transformed(Vector3(0.0, 0.0, 1.0)),
    );
  }

  /// Runs [steps] of the driver as it is set.
  @visibleForTesting
  void drive(int steps) {
    for (var i = 0; i < steps; i++) {
      _drive();
    }
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
    if (_world == null) throw StateError('no physics core: $fallback');
    // #region check
    // On tarmac, standing still for three seconds: each spring holds a
    // quarter of the weight, squeezed m g / 4k from its rest length, which
    // puts the chassis 0.2 + 0.35 + 0.4 m, less that, over the road.
    icy = false;
    braking = false;
    steer = 0.0;
    speed = 0.0;
    _restart();
    drive(180);
    final double squeeze = _mass * 9.81 / 4 / _stiffness;
    final double height = _pose.at.y;
    if ((height - (0.95 - squeeze)).abs() > 3e-3) {
      throw StateError('the chassis rests at $height, not ${0.95 - squeeze}');
    }
    if (!_world!.wheelsOf(_car!).every((w) => w.touching)) {
      throw StateError('a wheel at rest is off the road');
    }
    // Two seconds asking for 5 m/s, straight: forward along +z, and not
    // sideways. The core gets 5.9 m.
    speed = 5.0;
    drive(120);
    final Vector3 straight = _pose.at;
    if (straight.z < 4.0 || straight.x.abs() > 0.05) {
      throw StateError('driving straight ended at $straight');
    }
    // A second and a half steered 0.2 rad to the left: left of a car facing
    // +z with +y up is +x, and it has turned that way, about +y. The core
    // ends 2.3 m to the left, facing 0.51 of the way round to +x.
    steer = 0.2;
    drive(90);
    final turned = _pose;
    final double yaw = _world!.angularVelocityOf(_chassis!).y;
    if (turned.at.x < 1.0 || turned.forward.x < 0.3 || yaw < 0.2) {
      throw StateError(
        'steering left ended at ${turned.at}, facing ${turned.forward}, '
        'turning at $yaw rad/s',
      );
    }
    // #endregion check
  }
}
