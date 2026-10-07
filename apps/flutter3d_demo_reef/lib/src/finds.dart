/// What lies on the bottom to be found, and the bags of air that bring it
/// up: open at the foot, so as a bag rises and the water's weight on it
/// lessens, the air in it swells — Boyle's law — until it is full and the
/// rest spills out under its rim.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'diver.dart' show pressureAt;
import 'terrain.dart';
import 'wreck.dart' show wreckFloor;

/// A thing on the bottom worth bringing up.
final class Find {
  Find(this.name, this.body, this.look);

  final String name;
  final NativeBody body;
  final SceneNode look;

  /// Whether it has been lifted into the boat.
  bool aboard = false;

  /// How long it has hung at the surface under its bag, s, waiting for the
  /// boat to come round for it.
  double surfaced = 0.0;
}

/// The finds, laid where they lie.
final class Finds {
  Finds(
    this._world,
    GraphicsDevice device,
    Scene scene,
    Material Function(String name, Vector4 colour) under,
  ) {
    void lay(
      String name,
      NativeShape shape,
      Shape drawn,
      double mass,
      Vector3 at,
      Vector4 colour, {
      Quaternion? turn,
    }) {
      final body = _world.addBody(position: at, mass: mass);
      _world
        ..setShape(body, shape)
        ..setMaterial(body, NativeMaterial.stone());
      if (turn != null) _world.setOrientation(body, turn);
      final node = SceneNode(name: name)
        ..add(
          MeshNode(
            DeviceMesh.upload(device, drawn.build()),
            under(name, colour),
          ),
        );
      scene.add(node);
      finds.add(Find(name, body, node));
    }

    // A bronze head, hollow-cast, fallen down the reef's wall.
    lay(
      'bronze head',
      const NativeShape.sphere(0.2),
      const SphereShape(radius: 0.2, segments: 16, rings: 10),
      55.0,
      _onFloor(23.5, 21.0, 0.2),
      Vector4(0.30, 0.38, 0.30, 1.0),
    );
    // The ship's bell, by its stern.
    lay(
      'ship\'s bell',
      const NativeShape.cylinder(0.18, 0.17),
      const CylinderShape(radiusTop: 0.12, radiusBottom: 0.18, height: 0.34),
      42.0,
      _onFloor(37.0, 30.5, 0.17),
      Vector4(0.42, 0.34, 0.20, 1.0),
    );
    // A chest of coins in the hold.
    lay(
      'chest',
      NativeShape.box(Vector3(0.3, 0.2, 0.2)),
      CuboidShape(size: Vector3(0.6, 0.4, 0.4)),
      120.0,
      Vector3(44.5, wreckFloor + 0.5, 34.8),
      Vector4(0.25, 0.17, 0.10, 1.0),
    );
    // An amphora on the plain, half in the sand.
    lay(
      'amphora',
      const NativeShape.cylinder(0.15, 0.3),
      const CylinderShape(radiusTop: 0.08, radiusBottom: 0.15, height: 0.6),
      // Its hold full of sand: heavier than the water it displaces.
      60.0,
      _onFloor(50.0, 24.0, 0.15),
      Vector4(0.55, 0.32, 0.20, 1.0),
      turn: Quaternion.axisAngle(Vector3(0, 0, 1), 1.3),
    );
  }

  final NativeWorld _world;
  final List<Find> finds = <Find>[];

  /// [lift] metres over the floor at (x, z).
  static Vector3 _onFloor(double x, double z, double lift) =>
      Vector3(x, floorAt(x, z) + lift, z);

  /// The find nearest [at] within [reach] that is not yet aboard.
  Find? nearest(Vector3 at, {double reach = 2.0}) {
    Find? best;
    var bestDistance = reach;
    for (final f in finds) {
      if (f.aboard) continue;
      final d = (_world.positionOf(f.body) - at).length;
      if (d < bestDistance) {
        bestDistance = d;
        best = f;
      }
    }
    return best;
  }

  void update() {
    for (final f in finds) {
      if (f.aboard) continue;
      final p = _world.positionOf(f.body);
      f.look
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(f.body));
    }
  }
}

/// A lift bag: a body as big as the air in it, on a rope to what it lifts.
final class LiftBag {
  LiftBag(this._world, this._node);

  /// What it holds at most, litres, and how long its rope is, m.
  static const double most = 120.0, rope = 1.6;

  /// Smallest it is drawn and solid, m: a folded bag.
  static const double _folded = 0.08;

  final NativeWorld _world;
  final SceneNode _node;

  NativeBody? _body;
  NativeJoint? _rope;
  Find? lifting;

  /// The air in it, litres as at the surface.
  double air = 0.0;
  double _radius = _folded;

  bool get inUse => lifting != null;
  Vector3? get position => _body == null ? null : _world.positionOf(_body!);

  /// Tied to [find], its rope's length above it, folded and empty.
  void tie(Find find) {
    final at = _world.positionOf(find.body) + Vector3(0, rope, 0);
    final body = _world.addBody(position: at, mass: 2.0);
    _world
      ..setShape(body, const NativeShape.sphere(_folded))
      ..lockRotation(body);
    final joint = _world.createDistanceJoint(
      find.body,
      body,
      anchorA: _world.positionOf(find.body),
      anchorB: at,
    );
    _world
      ..setJointSpring(joint, (hertz: 0.0, damping: 0.0))
      ..setJointLength(joint, length: rope, least: 0.0, most: rope);
    _body = body;
    _rope = joint;
    lifting = find;
    air = 0.0;
    _radius = _folded;
    _node.visible = true;
  }

  /// [litres] of surface air blown in.
  void fill(double litres) => air += litres;

  /// Cut loose, its air let go: it is folded and back with the diver.
  void untie() {
    if (_rope != null) _world.removeJoint(_rope!);
    if (_body != null) _world.removeBody(_body!);
    _rope = null;
    _body = null;
    lifting = null;
    air = 0.0;
    _node.visible = false;
  }

  /// The air in it at the depth it is under [level]: squeezed or swollen by
  /// the water's weight there, and past [most] spilled. The body is made
  /// as big as the air, so the sea lifts it by the water it displaces.
  void update(double level) {
    final body = _body;
    if (body == null) return;
    final p = _world.positionOf(body);
    final pressure = pressureAt(level - p.y);
    air = math.min(air, most * pressure);
    final litres = air / pressure;
    final radius = math.max(
      _folded,
      math.pow(3.0 * litres / 1000.0 / (4.0 * math.pi), 1.0 / 3.0).toDouble(),
    );
    if ((radius - _radius).abs() > 0.004) {
      _radius = radius;
      // A new shape does not wake a body the sea had let settle: the bag
      // and what it holds are woken to feel the lift they now have.
      _world
        ..setShape(body, NativeShape.sphere(radius))
        ..wake(body)
        ..wake(lifting!.body);
    }
    _node
      ..setPosition(p.x, p.y, p.z)
      ..setScale(radius, radius * 1.15, radius);
  }
}
