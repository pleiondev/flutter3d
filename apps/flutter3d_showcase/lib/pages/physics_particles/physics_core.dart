/// The same drop twice, side by side: the left pile stepped by the Dart
/// reference, the right one by the physics core in C. Both are the same
/// `RigidBody` objects on the same kind of `CollisionWorld`; only the
/// backend that steps them differs.
///
/// Quoted by `physics_core.md` and shown whole in the Source tab.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart';

/// One pile: its world, what steps it and the crates in it.
final class _Pile {
  _Pile(this.world, this.dynamics, this.crates);

  final CollisionWorld world;
  final RigidDynamics dynamics;
  final List<RigidBody> crates;
}

final class PhysicsCoreDemo extends ShowcaseDemo {
  late _Pile _left;
  late _Pile _right;
  final List<MeshNode> _leftMeshes = <MeshNode>[];
  final List<MeshNode> _rightMeshes = <MeshNode>[];

  /// Whether the right pile asks for the core. Off, both piles are the
  /// reference, and they move as one.
  bool onCore = true;

  /// Why the right pile is on the reference although it asked for the core,
  /// or null when it is not.
  String? fallback;

  double _age = 0.0;

  static const int _count = 6;
  static const double _step = 1 / 60;

  /// How far apart the two piles stand, in metres along x.
  static const double _apart = 2.6;

  /// The right pile's dynamics, for a test that checks what steps it.
  @visibleForTesting
  RigidDynamics get rightDynamics => _right.dynamics;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 10.0
      ..pitch = 0.3
      ..yaw = 0.0;
    context.orbit.target.setValues(0.0, 1.2, 0.0);
  }

  // #region backends
  /// The backend the right pile is stepped by: the core where it starts,
  /// the reference where it does not, and the reason kept to say so.
  PhysicsBackend _rightBackend() {
    fallback = null;
    if (!onCore) return const DartPhysics();
    if (!physicsCoreLoaded) {
      fallback = 'the core is not loaded in this browser yet';
      return const DartPhysics();
    }
    try {
      // Made and freed at once: the first call that would find a missing
      // library or bindings for another ABI.
      NativeWorld().dispose();
      return NativePhysics();
    } on Object catch (e) {
      fallback = '$e';
      return const DartPhysics();
    }
  }
  // #endregion backends

  // #region drop
  /// A floor and six crates over it, nearly in a column, on [backend]. Both
  /// piles are built by this, with the same numbers, so any difference
  /// between them is the backend's.
  static _Pile _drop(PhysicsBackend backend) {
    final world = CollisionWorld()
      ..addBox(Vector3(0.0, -0.5, 0.0), Vector3(2.4, 1.0, 2.4));
    final RigidDynamics dynamics = backend.dynamics(world);
    final crates = <RigidBody>[
      for (var i = 0; i < _count; i++)
        dynamics.add(
          RigidBody(
            world: world,
            shape: CollisionBox(Vector3.all(0.3)),
            position: Vector3(
              0.12 * math.sin(i * 2.4),
              1.0 + i * 0.9,
              0.12 * math.cos(i * 1.9),
            ),
            mass: 2.0,
            friction: 0.7,
          ),
        ),
    ];
    return _Pile(world, dynamics, crates);
  }
  // #endregion drop

  void _release(_Pile pile) {
    if (pile.dynamics case final NativeDynamics core) core.dispose();
  }

  void _restart() {
    _release(_left);
    _release(_right);
    _left = _drop(const DartPhysics());
    _right = _drop(_rightBackend());
    _age = 0.0;
  }

  @override
  void dispose() {
    _release(_left);
    _release(_right);
  }

  @override
  Scene build(DemoContext context) {
    _left = _drop(const DartPhysics());
    _right = _drop(_rightBackend());

    final Scene scene = Scene()
      ..ambientColor = Vector3(0.5, 0.55, 0.65)
      ..ambientIntensity = 0.25
      ..add(
        LightNode(name: 'sun', intensity: 2.5)
          ..setLocalForward(Vector3(-0.3, -0.6, -0.4)),
      );
    for (final (double x, String side, Vector4 colour)
        in <(double, String, Vector4)>[
          (-_apart, 'reference', Vector4(0.45, 0.47, 0.5, 1.0)),
          (_apart, 'core', Vector4(0.42, 0.5, 0.43, 1.0)),
        ]) {
      scene.add(
        MeshNode(
          DeviceMesh.upload(
            context.device,
            CuboidShape(size: Vector3(2.4, 1.0, 2.4)).build(),
          ),
          Material(name: 'floor $side', baseColor: colour),
          name: 'floor $side',
        )..setPosition(x, -0.5, 0.0),
      );
    }
    final DeviceMesh crate = DeviceMesh.upload(
      context.device,
      CuboidShape(size: Vector3.all(0.6)).build(),
    );
    for (var i = 0; i < _count; i++) {
      final material = Material(
        name: 'crate $i',
        baseColor: Vector4(
          0.55 + 0.4 * math.sin(i * 0.9),
          0.5 + 0.3 * math.sin(i * 1.7 + 1.0),
          0.35 + 0.3 * math.sin(i * 2.3 + 2.0),
          1.0,
        ),
        roughness: 0.7,
      );
      final left = MeshNode(crate, material, name: 'reference crate $i');
      final right = MeshNode(crate, material, name: 'core crate $i');
      _leftMeshes.add(left);
      _rightMeshes.add(right);
      scene
        ..add(left)
        ..add(right);
    }
    _place();
    return scene;
  }

  void _place() {
    for (var i = 0; i < _count; i++) {
      final Vector3 l = _left.crates[i].position;
      final Vector3 r = _right.crates[i].position;
      _leftMeshes[i].setPosition(l.x - _apart, l.y, l.z);
      _rightMeshes[i].setPosition(r.x + _apart, r.y, r.z);
    }
  }

  @override
  void update(DemoContext context, double dt) {
    // #region step
    // One step of each, the same sixtieth of a second.
    _left.dynamics.step(_step);
    _right.dynamics.step(_step);
    // #endregion step
    _age += dt;
    if (_age > 6.0) _restart();
    _place();
  }

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      fallback == null
          ? 'Right pile on the core'
          : 'Right pile on the core (unavailable: $fallback)',
      value: () => onCore && fallback == null,
      onChanged: (bool v) {
        onCore = v;
        _restart();
      },
    ),
    ToggleControl(
      'Drop again',
      value: () => false,
      onChanged: (bool v) {
        if (v) _restart();
      },
    ),
  ];

  /// The furthest a crate of one pile ends from the same crate of the
  /// other, in metres, once both have settled.
  @visibleForTesting
  double settledGap() {
    for (var i = 0; i < 400; i++) {
      _left.dynamics.step(_step);
      _right.dynamics.step(_step);
    }
    var gap = 0.0;
    for (var i = 0; i < _count; i++) {
      gap = math.max(
        gap,
        (_left.crates[i].position - _right.crates[i].position).length,
      );
    }
    return gap;
  }

  @override
  void verify(Scene scene, FrameResult frame) {
    // #region check
    // On a machine where the core starts, the right pile has to be on it.
    if (fallback == null && _right.dynamics is! NativeDynamics) {
      throw StateError('the right pile is not on the core');
    }
    final double gap = settledGap();
    for (final _Pile pile in <_Pile>[_left, _right]) {
      for (final RigidBody c in pile.crates) {
        if (c.position.y < 0.25) {
          throw StateError('a crate fell through the floor: ${c.position}');
        }
        if (!c.isAsleep) throw StateError('a crate never came to rest');
      }
    }
    // The core is not the reference to the bit, but this tower ends where
    // the reference's does to within three centimetres (one and a half,
    // measured, on macOS).
    if (gap > 0.03) {
      throw StateError('the two piles part by ${gap.toStringAsFixed(3)} m');
    }
    // #endregion check
    if (frame.drawCalls < 1) throw StateError('nothing reached the frame');
  }
}
