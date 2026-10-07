/// What lies on the bottom to be found, and the bags of air that bring it
/// up: open at the foot, so as a bag rises and the water's weight on it
/// lessens, the air in it swells — Boyle's law — until it is full and the
/// rest spills out under its rim.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

import 'diver.dart' show pressureAt;
import 'looks.dart';
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
    SeabedLook floor,
    ReefLooks looks,
  ) {
    void lay(
      String name,
      NativeShape shape,
      SceneNode drawn,
      double mass,
      Vector3 at, {
      Quaternion? turn,
    }) {
      final body = _world.addBody(position: at, mass: mass);
      _world
        ..setShape(body, shape)
        ..setMaterial(body, NativeMaterial.stone());
      if (turn != null) _world.setOrientation(body, turn);
      final node = SceneNode(name: name)..add(drawn);
      scene.add(node);
      finds.add(Find(name, body, node));
    }

    SceneNode turned(MeshData mesh, String name, Vector4 colour) =>
        SceneNode(name: name)..add(
          MeshNode(
            DeviceMesh.upload(device, mesh),
            floor.under(name, colour, roughness: 0.6),
          ),
        );

    // A bronze head, hollow-cast, fallen down the reef's wall: a bust
    // modelled in marble, its picture's veins under a bronze gone green.
    lay(
      'bronze head',
      const NativeShape.sphere(0.2),
      looks.bust.dress(
          floor,
          name: 'bronze head',
          recolour: (_) => Vector4(0.30, 0.40, 0.30, 1.0),
          roughness: 0.5,
        )
        ..setPosition(0, -0.2, 0)
        ..setScale(0.85, 0.85, 0.85),
      55.0,
      _onFloor(23.5, 21.0, 0.2),
    );
    // The ship's bell, by its stern: turned bronze, a crown to hang it by.
    lay(
      'ship\'s bell',
      const NativeShape.cylinder(0.18, 0.17),
      turned(_bell(), 'ship\'s bell', Vector4(0.38, 0.40, 0.26, 1.0)),
      42.0,
      _onFloor(37.0, 30.5, 0.17),
    );
    // A chest of coins in the hold, its wood darkened by the sea.
    lay(
      'chest',
      NativeShape.box(Vector3(0.3, 0.2, 0.2)),
      looks.chest.dress(
          floor,
          name: 'chest',
          recolour: (_) => Vector4(0.62, 0.62, 0.52, 1.0),
        )
        ..setPosition(0, -0.2, 0)
        ..setScale(0.64, 0.9, 0.77),
      120.0,
      Vector3(44.5, wreckFloor + 0.5, 34.8),
    );
    // An amphora on the plain, half in the sand.
    lay(
      'amphora',
      const NativeShape.cylinder(0.15, 0.3),
      turned(_amphora(), 'amphora', Vector4(0.55, 0.32, 0.20, 1.0)),
      // Its hold full of sand: heavier than the water it displaces.
      60.0,
      _onFloor(50.0, 24.0, 0.15),
      turn: Quaternion.axisAngle(Vector3(0, 0, 1), 1.3),
    );
  }

  /// A surface turned from [profile], (radius, height) pairs.
  static MeshData _lathe(List<(double, double)> profile) => LatheShape(
    profile: <Vector2>[for (final (r, y) in profile) Vector2(r, y)],
    segments: 24,
  ).build();

  /// A ship's bell, its mouth down, 0.36 m across and 0.34 m high about its
  /// middle: the inside of its mouth up to the crown, then its outside down
  /// to the lip and back up its waist and shoulder to the crown.
  static MeshData _bell() => MeshData.merge(<MeshData>[
    _lathe(<(double, double)>[
      (0.0, 0.10),
      (0.09, 0.09),
      (0.13, -0.04),
      (0.16, -0.15),
      (0.18, -0.17),
      (0.182, -0.155),
      (0.16, -0.10),
      (0.135, -0.02),
      (0.122, 0.06),
      (0.115, 0.12),
      (0.095, 0.155),
      (0.05, 0.17),
      (0.0, 0.172),
    ]),
    const TorusShape(
      radius: 0.035,
      tubeRadius: 0.012,
      segments: 16,
      tubeSegments: 8,
    ).build().transformed(
      Matrix4.compose(
        Vector3(0, 0.2, 0),
        Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
        Vector3(1, 1, 1),
      ),
    ),
  ]);

  /// An amphora: a pointed toe, a body swelling to the shoulder, a long
  /// neck with a rolled rim, and a handle each side from neck to shoulder.
  static MeshData _amphora() => MeshData.merge(<MeshData>[
    _lathe(<(double, double)>[
      (0.0, -0.33),
      (0.025, -0.33),
      (0.035, -0.29),
      (0.08, -0.22),
      (0.13, -0.10),
      (0.15, 0.02),
      (0.14, 0.12),
      (0.10, 0.18),
      (0.05, 0.21),
      (0.042, 0.28),
      (0.055, 0.30),
      (0.05, 0.32),
      (0.0, 0.32),
    ]),
    for (final side in <double>[-1.0, 1.0])
      const TorusShape(
        radius: 0.05,
        tubeRadius: 0.013,
        segments: 16,
        tubeSegments: 8,
      ).build().transformed(
        Matrix4.compose(
          Vector3(side * 0.075, 0.215, 0),
          Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
          Vector3(1.0, 1.0, 1.4),
        ),
      ),
  ]);

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
