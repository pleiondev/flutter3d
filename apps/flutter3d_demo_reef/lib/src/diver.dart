/// The diver: a body the sea holds up as much as the water it displaces
/// weighs, pushed along by fins, trimmed by the air in a jacket that
/// shrinks as the diver goes down and swells on the way up, and breathing
/// from a tank that empties faster the deeper the breath is drawn.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// Pascals a metre of seawater weighs, over the atmosphere's: a diver at
/// ten metres breathes air at about two atmospheres.
const double _seaPerMetre = 1025.0 * 9.81, _atmosphere = 101325.0;

/// The pressure, atmospheres, [depth] metres under the surface.
double pressureAt(double depth) =>
    1.0 + math.max(depth, 0.0) * _seaPerMetre / _atmosphere;

/// The diver and their gear.
final class Diver {
  Diver(
    this._world,
    GraphicsDevice device,
    Scene scene,
    Material suit,
    Material gear,
    Vector3 at,
  ) {
    body = _world.addBody(position: at, mass: _mass);
    _world
      ..setShape(body, const NativeShape.capsule(_radius, _half))
      ..lockRotation(body);
    final torso = DeviceMesh.upload(
      device,
      const CapsuleShape(radius: 0.19, height: 0.9).build(),
    );
    final head = DeviceMesh.upload(
      device,
      const SphereShape(radius: 0.13, segments: 12, rings: 8).build(),
    );
    final tank = DeviceMesh.upload(
      device,
      const CylinderShape(
        radiusTop: 0.09,
        radiusBottom: 0.09,
        height: 0.65,
      ).build(),
    );
    final fin = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3(0.45, 0.02, 0.2)).build(),
    );
    // Drawn lying along +x, the way a diver swims; turned to the heading.
    final along = Quaternion.axisAngle(Vector3(0, 0, 1), -math.pi / 2);
    look = SceneNode(name: 'diver')
      ..add(MeshNode(torso, suit, name: 'torso')..setRotation(along))
      ..add(MeshNode(head, suit, name: 'head')..setPosition(0.62, 0.05, 0))
      ..add(
        MeshNode(tank, gear, name: 'tank')
          ..setRotation(along)
          ..setPosition(-0.05, 0.22, 0),
      )
      ..add(MeshNode(fin, gear, name: 'fin')..setPosition(-0.85, 0, 0.12))
      ..add(MeshNode(fin, gear, name: 'fin')..setPosition(-0.85, 0, -0.12));
    scene.add(look);
  }

  /// Body and weights, kilograms, and the capsule the sea sees: a tenth of
  /// a cubic metre, a little less than the water it would take to float
  /// the diver with the jacket empty.
  static const double _mass = 106.0, _radius = 0.17, _half = 0.45;

  /// How hard the fins push at most, N: a diver finning steadily.
  static const double thrust = 60.0;

  /// The tank: twelve litres at two hundred bar, as litres of air at the
  /// surface; and what a resting diver breathes a minute, at the surface.
  static const double tankLitres = 12.0 * 200.0, restingBreath = 18.0;

  /// The jacket: what it holds at most, litres at whatever depth it is, and
  /// how fast its inflator fills it and its valve lets it out, litres a
  /// second at that depth.
  static const double jacketMost = 15.0, inflates = 1.2, dumps = 2.0;

  final NativeWorld _world;
  late final NativeBody body;
  late final SceneNode look;

  /// Air left in the tank, and in the jacket, litres as at the surface.
  double air = tankLitres, jacket = 0.0;

  Vector3 get position => _world.positionOf(body);
  Vector3 get velocity => _world.velocityOf(body);

  /// Metres under the sea's [level], and the pressure there, atmospheres.
  double depthUnder(double level) => level - position.y;

  /// The tank's pressure, bar.
  double get tankBar => air / 12.0;

  /// The jacket's volume where the diver is, litres: Boyle's law, the air in
  /// it squeezed by the water's weight.
  double jacketVolume(double level) => jacket / pressureAt(depthUnder(level));

  /// Minutes of air left at this depth, breathing as now.
  double minutesLeft(double level, {double effort = 0.0}) =>
      air / (restingBreath * (1.0 + effort) * pressureAt(depthUnder(level)));

  /// A step: the fins pushing along [swim] (its length, up to one, how
  /// hard), the jacket filled by [fill] or emptied by [dump], each 0 to 1,
  /// a breath drawn from the tank, and the jacket's lift added.
  void step(
    double dt, {
    required double level,
    required Vector3 swim,
    double fill = 0.0,
    double dump = 0.0,
  }) {
    final effort = math.min(swim.length, 1.0);
    final p = pressureAt(depthUnder(level));
    // Breathing: litres at depth, each one p litres from the tank.
    _draw(restingBreath * (1.0 + effort) / 60.0 * p * dt);
    if (fill > 0.0) jacket += _draw(inflates * fill * p * dt);
    if (dump > 0.0) jacket = math.max(0.0, jacket - dumps * dump * p * dt);
    // Past full, the over-pressure valve lets the rest out.
    jacket = math.min(jacket, jacketMost * p);
    final lift = 1025.0 * 9.81 * jacket / p / 1000.0;
    final push = effort > 0.0
        ? swim.normalized() * (thrust * effort)
        : Vector3.zero();
    _world.addForce(body, push + Vector3(0.0, lift, 0.0));
  }

  /// [litres] of surface air drawn from the tank, as much as it has: what
  /// was drawn.
  double _draw(double litres) {
    final drawn = math.min(litres, air);
    air -= drawn;
    return drawn;
  }

  /// Out of the water at [at] with a full tank and an empty jacket.
  void restart(Vector3 at) {
    air = tankLitres;
    jacket = 0.0;
    _world
      ..setPosition(body, at)
      ..setVelocity(body, Vector3.zero());
  }

  /// Drawn where the body is, lying along [heading], radians about y.
  void update(double heading) {
    final p = position;
    final v = velocity;
    final level = math.sqrt(v.x * v.x + v.z * v.z);
    final pitch = math.atan2(v.y, math.max(level, 0.3)).clamp(-0.8, 0.8);
    look
      ..setPosition(p.x, p.y, p.z)
      ..setRotation(
        Quaternion.axisAngle(Vector3(0, 1, 0), heading) *
            Quaternion.axisAngle(Vector3(0, 0, 1), pitch),
      );
  }
}
