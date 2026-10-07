/// The quarry's crane: a long-necked beast standing on the quarry's rim,
/// swinging its neck over the pit and lifting stone on a rope from its jaw.
///
/// The physics core's multibody: a fixed body, a torso that turns on it, a
/// neck of four links each bending at its root and a head, every joint in
/// reduced coordinates so the neck cannot come apart however heavy the
/// stone; and the rope a distance joint from the jaw to the stone.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// A neck link's length and radius, m, and how many there are.
const double _neckLength = 1.3, _neckRadius = 0.22;
const int _neckLinks = 4;

/// How fast the neck lifts and the torso turns at most, rad/s, and with
/// what force their muscles drive them.
const double _lift = 0.35, _swing = 0.5, _muscle = 4.0e5;

Vector4 get _hide => Vector4(0.33, 0.40, 0.24, 1.0);
Vector4 get _belly => Vector4(0.62, 0.58, 0.42, 1.0);

/// The crane on the quarry's rim at [at], facing [facing] (radians about
/// up, nought along +x).
final class DinoCrane {
  DinoCrane(
    this._world,
    GraphicsDevice device,
    Scene scene, {
    required Vector3 at,
    required double facing,
  }) {
    final turn = Quaternion.axisAngle(Vector3(0, 1, 0), facing);
    Vector3 local(double x, double y, double z) =>
        at + turn.rotated(Vector3(x, y, z));
    // The legs and body: fixed, the multibody's root.
    final root = _world.addBody(
      position: local(0, 1.2, 0),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    _world.setShape(root, NativeShape.box(Vector3(1.4, 0.9, 0.7)));
    _world.setOrientation(root, turn);
    _crane = _world.createMultibody(root);
    // The torso, turning about up on the body's back.
    final torso = _world.addBody(position: local(0.6, 2.4, 0), mass: 1800.0);
    _world
      ..setShape(torso, NativeShape.box(Vector3(0.7, 0.4, 0.5)))
      ..setOrientation(torso, turn);
    _torso = _world.addLink(
      _crane,
      torso,
      type: NativeJointType.revolute,
      anchor: local(0.6, 2.1, 0),
      axis: Vector3(0, 1, 0),
    );
    // The neck: links laid along the torso's forward, rising at forty
    // degrees, each bending about the torso's side at its root.
    final side = turn.rotated(Vector3(0, 0, 1));
    final rise = 40.0 * math.pi / 180.0;
    final along = turn.rotated(Vector3(math.cos(rise), math.sin(rise), 0));
    var root2 = local(1.2, 2.6, 0);
    var parent = _torso;
    final tilt = Quaternion.axisAngle(side, rise) * turn;
    for (var k = 0; k < _neckLinks; k++) {
      final middle = root2 + along * (0.5 * _neckLength);
      final link = _world.addBody(position: middle, mass: 220.0 - 30.0 * k);
      _world
        ..setShape(
          link,
          NativeShape.capsule(
            _neckRadius * (1.0 - 0.12 * k),
            0.5 * _neckLength - _neckRadius,
          ),
        )
        // A capsule lies along y; turn it to lie along the neck.
        ..setOrientation(
          link,
          Quaternion.fromTwoVectors(Vector3(0, 1, 0), along),
        );
      parent = _world.addLink(
        _crane,
        link,
        parent: parent,
        type: NativeJointType.revolute,
        anchor: root2,
        axis: side,
      );
      _world.setLinkLimits(_crane, parent, lower: -0.5, upper: 0.5);
      _neck.add(parent);
      _neckBodies.add(link);
      root2 = root2 + along * _neckLength;
    }
    // The head, held fixed at the neck's tip.
    head = _world.addBody(position: root2 + along * 0.3, mass: 60.0);
    _world
      ..setShape(head, NativeShape.box(Vector3(0.35, 0.2, 0.2)))
      ..setOrientation(head, tilt);
    _world.addLink(
      _crane,
      head,
      parent: parent,
      type: NativeJointType.fixed,
      anchor: root2,
    );
    _bodies.addAll(<NativeBody>[root, torso, ..._neckBodies, head]);
    _looks.addAll(<MeshNode>[
      _look(device, CuboidShape(size: Vector3(2.8, 1.8, 1.4)).build(), _hide),
      _look(device, CuboidShape(size: Vector3(1.4, 0.8, 1.0)).build(), _belly),
      for (var k = 0; k < _neckLinks; k++)
        _look(
          device,
          CapsuleShape(
            radius: _neckRadius * (1.0 - 0.12 * k),
            height: _neckLength,
          ).build(),
          _hide,
        ),
      _look(device, CuboidShape(size: Vector3(0.7, 0.4, 0.4)).build(), _hide),
    ]);
    _looks.forEach(scene.add);
    _rope = _look(
      device,
      const CylinderShape(
        radiusTop: 0.025,
        radiusBottom: 0.025,
        height: 1.0,
      ).build(),
      Vector4(0.55, 0.45, 0.30, 1.0),
    )..visible = false;
    scene.add(_rope);
  }

  final NativeWorld _world;
  late final NativeMultibody _crane;
  late final int _torso;
  final List<int> _neck = <int>[];
  final List<NativeBody> _neckBodies = <NativeBody>[];
  final List<NativeBody> _bodies = <NativeBody>[];
  final List<MeshNode> _looks = <MeshNode>[];
  late final MeshNode _rope;
  late final NativeBody head;

  /// The rope, and what hangs on it.
  NativeJoint? _hold;
  NativeBody? carried;

  static MeshNode _look(
    GraphicsDevice device,
    MeshData shape,
    Vector4 colour,
  ) => MeshNode(
    DeviceMesh.upload(device, shape),
    Material(name: 'crane', baseColor: colour, roughness: 0.8),
    name: 'crane',
  );

  /// Where the jaw is.
  Vector3 get jaw => _world.positionOf(head);

  /// What the operator asks: [lift] and [swing] from −1 to 1.
  void work({required double lift, required double swing}) {
    _world.setLinkMotor(_crane, _torso, speed: _swing * swing, force: _muscle);
    for (final link in _neck) {
      _world.setLinkMotor(
        _crane,
        link,
        speed: -_lift * lift / _neckLinks,
        force: _muscle,
      );
    }
  }

  /// Takes up the nearest of [stones] within reach of the jaw on the rope,
  /// or lets go of what it carries.
  void grab(List<NativeBody> stones) {
    if (_hold != null) {
      _world.removeJoint(_hold!);
      _hold = null;
      carried = null;
      _rope.visible = false;
      return;
    }
    final at = jaw;
    NativeBody? best;
    var nearest = 4.0;
    for (final s in stones) {
      final d = (_world.positionOf(s) - at).length;
      if (d < nearest) {
        nearest = d;
        best = s;
      }
    }
    if (best == null) return;
    _hold = _world.createDistanceJoint(
      head,
      best,
      anchorA: at,
      anchorB: _world.positionOf(best) + Vector3(0, 0.3, 0),
    );
    carried = best;
    _rope.visible = true;
  }

  /// The crane drawn where the world has it.
  void update() {
    for (var k = 0; k < _bodies.length; k++) {
      final p = _world.positionOf(_bodies[k]);
      _looks[k]
        ..setPosition(p.x, p.y, p.z)
        ..setRotation(_world.orientationOf(_bodies[k]));
    }
    final stone = carried;
    if (stone != null) {
      final a = jaw, b = _world.positionOf(stone) + Vector3(0, 0.3, 0);
      final span = b - a;
      final length = span.length;
      _rope
        ..setPosition((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        ..setRotation(
          Quaternion.fromTwoVectors(Vector3(0, 1, 0), span.normalized()),
        )
        ..setScale(1.0, length, 1.0);
    }
  }
}
