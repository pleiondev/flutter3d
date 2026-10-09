/// The car: a wooden bed on four stone rollers, pushed along by whoever
/// sits in it — the physics core's vehicle, its wheels on springs.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';

import 'looks.dart';

/// The car's bed, m: half its length (along x, forward), height and width.
const double _halfLength = 1.2, _halfHeight = 0.12, _halfWidth = 0.75;

/// A roller's radius and half its width, m.
const double _rollerRadius = 0.42, _rollerHalfWidth = 0.18;

/// How hard the feet push at most, N, and with what power at most, W —
/// two people running hard; how far the front rollers turn, radians; and
/// how hard the brake holds, N.
const double _push = 900.0, _power = 600.0, _steer = 0.45, _brake = 3000.0;

/// A stone roller's rolling resistance on earth: a twentieth of the weight
/// on it, as a cart's wooden wheel on a dirt road.
const double _rolling = 0.05;

/// The car on stone rollers.
final class StoneCar {
  StoneCar(
    this._world,
    GraphicsDevice device,
    Scene scene,
    Vector3 at,
    HollowLooks looks,
  ) {
    // The bed and its rails as one body: a deck with a low rail all round,
    // so what is put on it stays on it.
    const rail = 0.06;
    final shape = _world.createCompound(<NativeCompoundPart>[
      NativeCompoundPart(
        NativeShape.box(Vector3(_halfLength, _halfHeight, _halfWidth)),
      ),
      for (final side in <double>[-1, 1])
        NativeCompoundPart(
          NativeShape.box(Vector3(_halfLength, 0.15, rail)),
          at: Vector3(0, _halfHeight + 0.15, side * (_halfWidth - rail)),
        ),
      for (final end in <double>[-1, 1])
        NativeCompoundPart(
          NativeShape.box(Vector3(rail, 0.15, _halfWidth)),
          at: Vector3(end * (_halfLength - rail), _halfHeight + 0.15, 0),
        ),
    ]);
    body = _world.addBody(position: at, mass: 320.0);
    _world
      ..setCompound(body, shape)
      ..setMaterial(body, NativeMaterial.wood());
    vehicle = _world.createVehicle(
      body,
      up: Vector3(0.0, 1.0, 0.0),
      forward: Vector3(1.0, 0.0, 0.0),
    );
    for (final (x, z) in <(double, double)>[
      (0.8, -0.85),
      (0.8, 0.85),
      (-0.8, -0.85),
      (-0.8, 0.85),
    ]) {
      _world.addWheel(
        vehicle,
        NativeWheelSettings(
          attach: Vector3(x, -0.05, z),
          rest: 0.35,
          radius: _rollerRadius,
          // Stiff enough that a loaded bed sags a hand's breadth, damped near
          // critically.
          stiffness: 26000.0,
          damping: 2600.0,
          grip: 0.9,
          width: 2.0 * _rollerHalfWidth,
          rollingResistance: _rolling,
        ),
      );
    }
    // Drawn about the deck's middle, which sits below the body's origin by
    // as far as the rails lift the centre of mass.
    _below = -_world.compoundOffset(shape);
    final frame = SceneNode(name: 'frame')
      ..setPosition(_below.x, _below.y, _below.z);
    _bed = SceneNode(name: 'car')..add(frame);
    // A pole along y of [radius] and [length], turned to lie along x or z.
    final lengthwise = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);
    final across = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
    DeviceMesh pole(double radius, double length) => DeviceMesh.upload(
      device,
      CylinderShape(
        radiusTop: radius,
        radiusBottom: radius * 1.08,
        height: length,
        segments: 10,
      ).build(),
    );
    // The bed: five pine logs side by side along the car, as wide together
    // as the deck the core has, barked, a little uneven in girth.
    const logs = 5;
    const logRadius = _halfWidth / logs;
    final bark = covered('bark', looks.bark, repeat: Vector2(2.0, 3.0));
    final random = math.Random(3);
    // Each log's ends cut across, the pale wood showing rather than bark
    // drawn in to a point.
    final cut = covered(
      'cut',
      looks.wood,
      tint: Vector4(0.95, 0.75, 0.52, 1.0),
      repeat: Vector2.all(0.5),
    );
    for (var k = 0; k < logs; k++) {
      final r = logRadius * (0.92 + 0.12 * random.nextDouble());
      const length = 2 * _halfLength + 0.1;
      final end = DeviceMesh.upload(
        device,
        CylinderShape(
          radiusTop: r * 0.93,
          radiusBottom: r * 0.93,
          height: 0.012,
          segments: 10,
        ).build(),
      );
      frame.add(
        MeshNode(pole(r, length), bark, name: 'log')
          ..setPosition(
            0.04 * (random.nextDouble() - 0.5),
            0,
            -_halfWidth + logRadius * (2 * k + 1),
          )
          ..setRotation(lengthwise)
          ..add(MeshNode(end, cut, name: 'cut')..setPosition(0, length / 2, 0))
          ..add(
            MeshNode(end, cut, name: 'cut')..setPosition(0, -length / 2, 0),
          ),
      );
    }
    // The rails: thinner poles lashed on the bed's edges, one course along
    // each side and one across each end, on stakes at the corners.
    final wood = covered('wood', looks.wood, repeat: Vector2(1.0, 2.0));
    final railLong = pole(0.06, 2 * _halfLength);
    final railShort = pole(0.06, 2 * _halfWidth);
    final stake = pole(0.045, 0.42);
    const railY = _halfHeight + 0.22;
    for (final side in <double>[-1, 1]) {
      frame
        ..add(
          MeshNode(railLong, wood, name: 'rail')
            ..setPosition(0, railY, side * (_halfWidth - rail))
            ..setRotation(lengthwise),
        )
        ..add(
          MeshNode(railShort, wood, name: 'rail')
            ..setPosition(side * (_halfLength - rail), railY - 0.08, 0)
            ..setRotation(across),
        );
      for (final end in <double>[-1, 0, 1]) {
        frame.add(
          MeshNode(stake, wood, name: 'stake')..setPosition(
            end * (_halfLength - rail),
            _halfHeight + 0.12,
            side * (_halfWidth - rail),
          ),
        );
      }
    }
    // The axles the rollers turn on, under the bed.
    final axle = pole(0.07, 2 * 0.85 + 0.1);
    for (final x in <double>[-0.8, 0.8]) {
      frame.add(
        MeshNode(axle, bark, name: 'axle')
          ..setPosition(x, -_halfHeight - 0.12, 0)
          ..setRotation(across),
      );
    }
    // A barrel for water lashed at the back: staves bulging at the middle.
    _barrel = MeshNode(
      DeviceMesh.upload(
        device,
        LatheShape(
          profile: <Vector2>[
            Vector2(0.0, -0.3),
            Vector2(0.24, -0.3),
            Vector2(0.24, -0.3),
            Vector2(0.28, -0.12),
            Vector2(0.29, 0.0),
            Vector2(0.28, 0.12),
            Vector2(0.24, 0.3),
            Vector2(0.24, 0.3),
            Vector2(0.0, 0.3),
          ],
          segments: 18,
        ).build(),
      ),
      covered('barrel', looks.wood, repeat: Vector2(3.0, 1.0)),
      name: 'barrel',
    )..setPosition(-_halfLength + 0.4, _halfHeight + 0.42, 0);
    // Two hoops of twisted withies round the staves, where it bulges less.
    final hoop = RenderMaterial(
      name: 'hoop',
      baseColor: LinearColor.fromSrgb(0.2, 0.14, 0.08, 1.0),
      roughness: 0.8,
    );
    final hoopMesh = DeviceMesh.upload(
      device,
      const TorusShape(
        radius: 0.275,
        tubeRadius: 0.018,
        segments: 24,
        tubeSegments: 6,
      ).build(),
    );
    for (final y in <double>[-0.17, 0.17]) {
      _barrel.add(MeshNode(hoopMesh, hoop, name: 'hoop')..setPosition(0, y, 0));
    }
    frame.add(_barrel);
    scene.add(_bed);
    // A roller: a disc of granite, its rim worn round and a boss either
    // side where the axle goes through. It stands along y; turned to lie
    // along z, its axle.
    final roller = DeviceMesh.upload(
      device,
      LatheShape(
        profile: <Vector2>[
          Vector2(0.0, -_rollerHalfWidth - 0.05),
          Vector2(0.11, -_rollerHalfWidth - 0.05),
          Vector2(0.13, -_rollerHalfWidth),
          Vector2(_rollerRadius - 0.07, -_rollerHalfWidth),
          Vector2(_rollerRadius - 0.01, -_rollerHalfWidth + 0.04),
          Vector2(_rollerRadius, 0.0),
          Vector2(_rollerRadius - 0.01, _rollerHalfWidth - 0.04),
          Vector2(_rollerRadius - 0.07, _rollerHalfWidth),
          Vector2(0.13, _rollerHalfWidth),
          Vector2(0.11, _rollerHalfWidth + 0.05),
          Vector2(0.0, _rollerHalfWidth + 0.05),
        ],
        segments: 22,
      ).build(),
    );
    for (var k = 0; k < 4; k++) {
      final look = MeshNode(
        roller,
        covered(
          'roller',
          looks.granite,
          tint: Vector4(0.85, 0.83, 0.8, 1.0),
          repeat: Vector2(2.0, 1.0),
        ),
        name: 'roller',
      )..setRotation(Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2));
      final node = SceneNode(name: 'wheel')..add(look);
      scene.add(node);
      _rollers.add(node);
    }
  }

  final NativeWorld _world;
  late final NativeBody body;
  late final NativeVehicle vehicle;
  late final SceneNode _bed;
  late final MeshNode _barrel;
  final List<SceneNode> _rollers = <SceneNode>[];

  /// Kilograms of water in the barrel; a hundred is full.
  double water = 0.0;
  static const double barrelHolds = 100.0;

  /// Where the car is and which way it faces.
  Vector3 get position => _world.localPositionOf(body);
  Quaternion get orientation => _world.orientationOf(body);
  Vector3 get forward =>
      orientation.asRotationMatrix().transformed(Vector3(1.0, 0.0, 0.0));

  /// The middle of the deck's top, where a load stands.
  Vector3 get deck =>
      position +
      orientation.asRotationMatrix().transformed(
        _below + Vector3(0.3, _halfHeight, 0.0),
      );

  /// Where the deck's middle is from the body's origin.
  late final Vector3 _below;

  /// What the driver asks: [throttle] and [turn] from −1 to 1, and whether
  /// they [hold] the brake.
  void drive({
    required double throttle,
    required double turn,
    required bool hold,
  }) {
    // The feet push as hard as they can until their power runs out:
    // F = min(F_max, P / v).
    final speed = _world.velocityOf(body).length;
    final force = speed > 0.1 ? (_power / speed).clamp(0.0, _push) : _push;
    // Left alone, the rollers' own resistance holds it on any slope
    // gentler than a twentieth, and slows it on the flat; the brake is
    // the driver's feet, down only while held.
    for (var k = 0; k < 4; k++) {
      final front = k < 2;
      _world.setWheel(
        vehicle,
        k,
        steer: front ? _steer * turn : 0.0,
        drive: front ? 0.0 : 0.5 * force * throttle,
        brake: hold ? _brake : 0.0,
      );
    }
  }

  /// Back on its rollers where it lies, facing the way it faced.
  void rightUp() {
    final p = position;
    final f = forward..y = 0;
    final heading = f.length2 > 0 ? Portable.atan2(-f.z, f.x) : 0.0;
    _world
      ..setPosition(body, Vector3(p.x, p.y + 1.5, p.z))
      ..setOrientation(body, Quaternion.axisAngle(Vector3(0, 1, 0), heading))
      ..setVelocity(body, Vector3.zero())
      ..setAngularVelocity(body, Vector3.zero());
  }

  /// The car drawn where the world has it.
  void update() {
    final p = position;
    final q = orientation;
    _bed
      ..setPosition(p.x, p.y, p.z)
      ..setRotation(q);
    // Oak-brown staves, darker as the water soaks them.
    final soaked = water / barrelHolds;
    _barrel.material.baseColor = LinearColor.fromSrgb(
      0.95 * (1.0 - 0.45 * soaked),
      0.74 * (1.0 - 0.4 * soaked),
      0.52 * (1.0 - 0.25 * soaked),
      1.0,
    );
    final wheels = _world.wheelsOf(vehicle);
    for (var k = 0; k < wheels.length; k++) {
      final w = wheels[k];
      final turn =
          q *
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), w.steer) *
          Quaternion.axisAngle(Vector3(0.0, 0.0, -1.0), w.rotation);
      _rollers[k]
        ..setPosition(w.center.x, w.center.y, w.center.z)
        ..setRotation(turn);
    }
  }
}
