/// Crates dropped one after another onto a floor: they land, stack, settle and
/// fall asleep, and a snapshot taken before any of it winds the pile back to
/// where it began. The physics runs live, a step to a frame.
///
/// Quoted by `rigid_bodies.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

final class RigidBodiesDemo extends ShowcaseDemo {
  late final CollisionWorld _world;
  late final Dynamics _dynamics;
  final List<RigidBody> _crates = <RigidBody>[];
  final List<double> _halves = <double>[];
  final List<MeshNode> _meshes = <MeshNode>[];
  final List<Map<String, Object?>> _start = <Map<String, Object?>>[];

  bool _shoveAsked = false;
  double _atRest = 0.0;
  double _age = 0.0;

  static const int _count = 8;
  static const double _step = 1 / 60;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 8.0
      ..pitch = 0.35
      ..yaw = 0.6;
    context.orbit.target.setValues(0.0, 1.0, 0.0);
  }

  @override
  Scene build(DemoContext context) {
    // #region world
    _world = CollisionWorld();
    _world.addBox(Vector3(0.0, -0.5, 0.0), Vector3(6.0, 1.0, 6.0));
    _dynamics = Dynamics(world: _world);
    // #endregion world

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25
      ..add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(6.0, 1.0, 6.0)).build(),
          ),
          Material(name: 'floor', baseColor: Vector4(0.42, 0.46, 0.43, 1.0)),
          name: 'floor',
        )..setPosition(0.0, -0.5, 0.0),
      )
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );

    // #region body
    // Eight crates, each higher up and a little off to one side of the last,
    // so they arrive one at a time and land on one another as often as on
    // the floor.
    for (var i = 0; i < _count; i++) {
      final double half = 0.3 + 0.08 * (i % 3);
      final RigidBody crate = _dynamics.add(
        RigidBody(
          world: _world,
          shape: CollisionBox(Vector3(half, half, half)),
          position: Vector3(
            0.5 * math.sin(i * 2.4),
            1.2 + i * 1.1,
            0.5 * math.cos(i * 1.9),
          ),
          mass: 2.0,
          friction: 0.7,
        ),
      );
      _crates.add(crate);
      _halves.add(half);
      final MeshNode mesh = MeshNode(
        DeviceMesh.upload(
          context.device,
          CuboidShape(size: Vector3.all(half * 2)).build(),
        ),
        Material(
          name: 'crate $i',
          baseColor: Vector4(
            0.55 + 0.4 * math.sin(i * 0.9),
            0.5 + 0.3 * math.sin(i * 1.7 + 1.0),
            0.35 + 0.3 * math.sin(i * 2.3 + 2.0),
            1.0,
          ),
          roughness: 0.7,
        ),
        name: 'crate $i',
      )..setPositionFrom(crate.position);
      _meshes.add(mesh);
      scene.add(mesh);
    }
    // #endregion body

    // #region snapshot
    // Taken before a single step: everything a body needs to be put back
    // exactly here — position, velocity, whether it is asleep.
    for (final RigidBody crate in _crates) {
      _start.add(crate.save());
    }
    // #endregion snapshot
    return scene;
  }

  @override
  void update(DemoContext context, double dt) {
    // #region live
    _age += dt;
    // A step of a sixtieth of a second, however long the frame took: the
    // same drop lands the same way on every machine.
    _dynamics.step(_step);
    // #endregion live

    if (_shoveAsked) {
      _shoveAsked = false;
      _shove();
    }

    _atRest = _crates.every((RigidBody c) => c.isAsleep) ? _atRest + dt : 0.0;
    // Watched for a moment at rest, then wound back and dropped again.
    if (_atRest > 1.5 || _age > 12.0) _rewind();

    for (var i = 0; i < _count; i++) {
      _meshes[i].setPositionFrom(_crates[i].position);
    }
  }

  // #region shove
  void _shove() {
    for (var i = 0; i < _count; i++) {
      _crates[i].applyImpulse(
        Vector3(math.sin(i * 2.1) * 3.0, 4.0, math.cos(i * 1.7) * 3.0),
      );
    }
    _atRest = 0.0;
  }
  // #endregion shove

  // #region restore
  void _rewind() {
    for (var i = 0; i < _count; i++) {
      _crates[i].restore(_start[i]);
    }
    _atRest = 0.0;
    _age = 0.0;
  }
  // #endregion restore

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Shove them',
      value: () => _shoveAsked,
      onChanged: (bool v) => _shoveAsked = v,
    ),
    ToggleControl(
      'Rewind to the start',
      value: () => false,
      onChanged: (bool v) {
        if (v) _rewind();
      },
    ),
  ];

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // Let the pile come to rest. Every crate has to end up on the floor or
    // on another crate: none fallen through, none left hanging in the air.
    for (var i = 0; i < 600; i++) {
      _dynamics.step(_step);
    }
    for (var i = 0; i < _count; i++) {
      final double y = _crates[i].position.y;
      if (y < _halves[i] - 0.05) {
        throw StateError('crate $i fell through the floor: y = $y');
      }
      if (y > 8.0) {
        throw StateError('crate $i is still in the air: y = $y');
      }
    }
    if (!_crates.every((RigidBody c) => c.isAsleep)) {
      throw StateError('the pile should have come to rest and gone to sleep');
    }

    // Winding back has to undo all of it, exactly.
    _rewind();
    for (var i = 0; i < _count; i++) {
      final Vector3 back = _crates[i].position;
      final Vector3 saved = Vector3(
        0.5 * math.sin(i * 2.4),
        1.2 + i * 1.1,
        0.5 * math.cos(i * 1.9),
      );
      if ((back - saved).length > 1e-6) {
        throw StateError('restore should have put crate $i back where it was');
      }
    }
    // #endregion check
    if (frame.drawCalls < 1) {
      throw StateError('the crates did not reach the frame');
    }
  }
}
