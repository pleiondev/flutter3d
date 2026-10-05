/// The physics core underneath `flutter3d_physics`' bodies — P9.
///
/// A [RigidDynamics], so a game builds one where it built a `Dynamics` and
/// nothing past that line changes: the bodies are still [RigidBody] objects
/// on a [CollisionWorld], their colliders still what the broadphase, the
/// sweeps and the character controller see.
///
/// ## Who holds what
///
/// The core holds the bodies' truth; a [RigidBody] is its mirror. Before a
/// step, whatever a game did to a body since the last one — an impulse, a
/// push, a teleport, a restore — is found by comparing it with what the
/// mirror was left at, and written in; after the step, every body is written
/// back: its collider moved, its velocity, spin and orientation, asleep or
/// not. The rest of the world — level geometry, characters, doors, lifts —
/// stands in the core as fixed bodies, made as colliders appear, moved as
/// they move and taken out as they go. Triggers stand nowhere: they block
/// nothing.
///
/// ## What is different from Dynamics
///
/// Contacts turn a body that can turn, a box falls flat off an edge, joints
/// and bullets are the core's own ([native]); the step is the core's, in
/// f32, to bits of its own — the same bits on every platform, but not the
/// reference's, so a run's digests are not the reference's either. A
/// rollback restores [snapshot]s, which carry the warm starts and the sleep
/// a body's own `save()` does not; a body restored on its own is put where
/// it was and moving as it was, and the core takes it from there.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:vector_math/vector_math.dart';

import 'native_world.dart';

final class NativeDynamics implements RigidDynamics {
  /// [gravity] as `Dynamics`' default, and its sleep: under 0.08 m/s for
  /// half a second. The air is all but taken away, as the reference has
  /// none; [native] can bring it back, with wind.
  NativeDynamics({
    required this.world,
    Vector3? gravity,
    int substeps = 4,
    int threads = 1,
  }) : gravity = gravity ?? Vector3(0.0, -22.0, 0.0) {
    native
      ..setAir(temperature: 293.15, density: 1e-30)
      ..setSleep(speed: 0.08, time: 0.5)
      ..substeps = substeps;
    if (threads != 1) native.threads = threads;
  }

  @override
  final CollisionWorld world;

  @override
  final Vector3 gravity;

  /// The core's world: joints, bullets, the air, the fast mode.
  final NativeWorld native = NativeWorld();

  @override
  final List<RigidBody> bodies = <RigidBody>[];

  final Map<Collider, RigidBody> _byCollider = <Collider, RigidBody>{};
  final Map<RigidBody, _Mirror> _mirrors = <RigidBody, _Mirror>{};
  final Map<Collider, _Standing> _standing = <Collider, _Standing>{};
  final Map<CollisionShape, (NativeHull, Vector3)> _hulls =
      <CollisionShape, (NativeHull, Vector3)>{};
  final Map<CollisionShape, NativeMesh> _meshes =
      <CollisionShape, NativeMesh>{};
  late final Pusher _pusher = Pusher(this);
  int _sweep = 0;

  /// The core's handle for [body]; null for a body not added. For a game
  /// that reaches past the bodies into [native]: joining two crates with a
  /// hinge, making a thrown body a bullet, giving one heat.
  NativeBody? handleOf(RigidBody body) => _mirrors[body]?.handle;

  @override
  RigidBody add(RigidBody body) {
    bodies.add(body);
    _byCollider[body.collider] = body;
    _mirrors[body] = _mirrorFor(body);
    return body;
  }

  /// [body] made in the core as it is now, and its mirror.
  _Mirror _mirrorFor(RigidBody body) {
    final (shape, offset) = _shapeOf(body.collider.shape);
    final handle = native.addBody(
      position: body.position + _turned(body.orientation, offset),
      mass: body.mass,
    );
    shape(handle);
    native
      ..setOrientation(handle, body.orientation)
      ..setVelocity(handle, body.velocity)
      ..setAngularVelocity(handle, body.angularVelocity)
      ..lockRotation(handle, locked: !body.canRotate)
      ..setDamping(handle, angular: body.angularDamping)
      ..setFriction(handle, body.friction)
      ..setRestitution(handle, body.restitution)
      ..setCollisionFilter(
        handle,
        layer: body.collider.layer & Layers.all,
        mask: body.collider.mask & Layers.all,
      );
    return _Mirror(handle, offset)..take(body);
  }

  @override
  void remove(RigidBody body) {
    bodies.remove(body);
    _byCollider.remove(body.collider);
    final mirror = _mirrors.remove(body);
    if (mirror != null) native.removeBody(mirror.handle);
    world.remove(body.collider);
  }

  @override
  RigidBody? bodyOf(Collider collider) => _byCollider[collider];

  @override
  void push(Collider by, Vector3 velocity, {double strength = 1.0}) =>
      _pusher.push(by, velocity, strength: strength);

  @override
  void step(double dt) {
    if (dt <= 0.0) return;
    _stand(dt);
    for (final body in bodies) {
      _mirrors[body]!.give(native, body);
    }
    native
      ..gravity = gravity
      ..step(dt);
    for (final body in bodies) {
      _mirrors[body]!.fetch(native, body);
    }
    world.reindex();
  }

  /// The whole world as the core holds it, warm starts and sleep and all,
  /// for a rollback.
  Uint8List snapshot() => native.snapshot();

  /// The [snapshot], as text a simulation's save can hold.
  @override
  Object? saveState() => base64Encode(snapshot());

  @override
  void restoreState(Object? saved) {
    if (saved is String) restore(base64Decode(saved));
  }

  /// Back to [bytes], every body's mirror with it.
  ///
  /// What came and went since the snapshot is put right, as a simulation
  /// restoring a save has already put its own world right: a body added
  /// since is made again as it is now, a collider standing since stands
  /// again next step, and whatever the snapshot holds that nothing here
  /// names any more — a crate since broken, a wall since taken out — goes.
  /// Handles carry a generation, so a slot used again since is told apart.
  /// Hulls and meshes made since are gone with the snapshot, so they are
  /// made again as they are needed.
  void restore(Uint8List bytes) {
    native.restore(bytes);
    _hulls.clear();
    _meshes.clear();
    _standing.removeWhere((_, standing) => !native.contains(standing.handle));
    // Where each stands, and whether it moves, as the snapshot has it: a
    // lift restored to where it was is not a lift that jumped there.
    _standing.forEach(
      (collider, standing) => standing.resume(native, collider),
    );
    for (final body in bodies) {
      if (!native.contains(_mirrors[body]!.handle)) {
        _mirrors[body] = _mirrorFor(body);
      }
    }
    final named = <NativeBody>{
      for (final mirror in _mirrors.values) mirror.handle,
      for (final standing in _standing.values) standing.handle,
    };
    for (final body in native.readTransforms().bodies) {
      if (!named.contains(body)) native.removeBody(body);
    }
    for (final body in bodies) {
      _mirrors[body]!.fetch(native, body);
    }
    world.reindex();
  }

  /// Lets the core go. Nothing can be stepped after.
  void dispose() => native.dispose();

  /// Every collider that is not a body's and not a trigger, standing in the
  /// core as a fixed body where it is now.
  void _stand(double dt) {
    final sweep = ++_sweep;
    void consider(Collider collider) {
      if (collider.kind == ColliderKind.trigger) return;
      if (_byCollider.containsKey(collider)) return;
      final standing = _standing[collider] ??= _standingFor(collider);
      standing.sweep = sweep;
      standing.follow(native, collider, dt);
    }

    world.statics.forEach(consider);
    world.movers.forEach(consider);
    _standing.removeWhere((collider, standing) {
      if (standing.sweep == sweep) return false;
      native.removeBody(standing.handle);
      return true;
    });
  }

  _Standing _standingFor(Collider collider) {
    final (shape, offset) = _shapeOf(collider.shape);
    final handle = native.addBody(
      position: collider.position + offset,
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    shape(handle);
    return _Standing(handle, offset)..placed(native, collider);
  }

  /// What shapes a core body as [shape], and where the core puts its origin
  /// from the collider's: nowhere else but for a hull, which the core
  /// centres on its centre of mass.
  (void Function(NativeBody), Vector3) _shapeOf(CollisionShape shape) {
    switch (shape) {
      case CollisionBox(:final halfExtents):
        return (
          (b) => native.setShape(b, NativeShape.box(halfExtents)),
          Vector3.zero(),
        );
      case CollisionSphere(:final radius):
        return (
          (b) => native.setShape(b, NativeShape.sphere(radius)),
          Vector3.zero(),
        );
      case CollisionCapsule(:final radius, :final halfHeight):
        return (
          (b) => native.setShape(b, NativeShape.capsule(radius, halfHeight)),
          Vector3.zero(),
        );
      case CollisionWedge():
        final (hull, offset) = _hulls[shape] ??= _hullOf(shape);
        return ((b) => native.setHull(b, hull), offset);
      case CollisionHeightfield():
        final mesh = _meshes[shape] ??= _meshOf(shape);
        return ((b) => native.setMesh(b, mesh), Vector3.zero());
    }
  }

  /// A wedge as six corners: the floor's four, and the top edge's two over
  /// its uphill side.
  (NativeHull, Vector3) _hullOf(CollisionWedge wedge) {
    final h = wedge.halfExtents;
    final axis = wedge.uphill.axis;
    final high = wedge.uphill.sign * h[axis];
    final points = <Vector3>[
      for (final x in <double>[-h.x, h.x])
        for (final z in <double>[-h.z, h.z]) Vector3(x, -h.y, z),
      for (final across in <double>[-1.0, 1.0])
        axis == 0
            ? Vector3(high, h.y, across * h.z)
            : Vector3(across * h.x, h.y, high),
    ];
    final hull = native.createHull(points);
    return (hull, native.hullOffset(hull));
  }

  /// A height field as the triangles its own heights describe, split the
  /// way it splits them — corner (0, 0) to (1, 1) — and wound up.
  NativeMesh _meshOf(CollisionHeightfield field) {
    final x0 = -field.width * 0.5;
    final z0 = -field.depth * 0.5;
    final y0 = -(field.highest + field.lowest) * 0.5;
    final vertices = <Vector3>[
      for (var row = 0; row < field.rows; row++)
        for (var column = 0; column < field.columns; column++)
          Vector3(
            x0 + column * field.cellSize,
            y0 + field.sample(column, row),
            z0 + row * field.cellSize,
          ),
    ];
    final indices = <int>[
      for (var row = 0; row + 1 < field.rows; row++)
        for (var column = 0; column + 1 < field.columns; column++)
          ...() {
            final a = row * field.columns + column;
            final right = a + 1, below = a + field.columns;
            return <int>[a, below + 1, right, a, below, below + 1];
          }(),
    ];
    return native.createMesh(vertices, indices);
  }
}

/// [offset] turned by [q].
Vector3 _turned(Quaternion q, Vector3 offset) =>
    offset.length2 == 0.0 ? Vector3.zero() : q.rotated(offset);

/// A body's mirror: its handle, the core's origin from the collider's, and
/// what the body was left at after the last step, to tell what a game did
/// to it since.
final class _Mirror {
  _Mirror(this.handle, this.offset);

  final NativeBody handle;
  final Vector3 offset;
  final Vector3 _at = Vector3.zero();
  final Vector3 _velocity = Vector3.zero();
  final Vector3 _spin = Vector3.zero();
  final Quaternion _turn = Quaternion.identity();
  bool _asleep = false;

  /// Remembers [body] as it is now.
  void take(RigidBody body) {
    _at.setFrom(body.position);
    _velocity.setFrom(body.velocity);
    _spin.setFrom(body.angularVelocity);
    _turn.setFrom(body.orientation);
    _asleep = body.isAsleep;
  }

  /// Whatever changed in [body] since [take], into the core.
  void give(NativeWorld native, RigidBody body) {
    final turned = !_same(_turn, body.orientation);
    if (turned) native.setOrientation(handle, body.orientation);
    if (turned || _at != body.position) {
      native.setPosition(
        handle,
        body.position + _turned(body.orientation, offset),
      );
    }
    if (_velocity != body.velocity) native.setVelocity(handle, body.velocity);
    if (_spin != body.angularVelocity) {
      native.setAngularVelocity(handle, body.angularVelocity);
    }
    if (_asleep && !body.isAsleep && native.isAsleep(handle)) {
      native.wake(handle);
    }
  }

  /// The core's body into [body], and remembered.
  void fetch(NativeWorld native, RigidBody body) {
    final turn = native.orientationOf(handle);
    if (body.canRotate) body.orientation = turn;
    body.collider.moveTo(
      native.positionOf(handle) - _turned(body.orientation, offset),
    );
    body.velocity.setFrom(native.velocityOf(handle));
    body.angularVelocity.setFrom(native.angularVelocityOf(handle));
    final asleep = native.isAsleep(handle);
    if (asleep && !body.isAsleep) body.sleep();
    if (!asleep && body.isAsleep) body.wake();
    take(body);
  }
}

bool _same(Quaternion a, Quaternion b) =>
    a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;

/// A collider standing in the core as a fixed body, and where it was put.
final class _Standing {
  _Standing(this.handle, this.offset);

  final NativeBody handle;
  final Vector3 offset;
  final Vector3 _at = Vector3.zero();
  int _layer = 0, _mask = 0;
  bool _moving = false;
  int sweep = 0;

  void placed(NativeWorld native, Collider collider) {
    _at.setFrom(collider.position);
    _layer = collider.layer;
    _mask = collider.mask;
    native.setCollisionFilter(
      handle,
      layer: _layer & Layers.all,
      mask: _mask & Layers.all,
    );
  }

  /// Where [collider] is now — put back by its owner's restore before the
  /// core's — and whether it was moving when the core's snapshot was taken.
  /// The collider's own position rather than the core's, which is rounded
  /// to f32 and would read as a move.
  void resume(NativeWorld native, Collider collider) {
    _at.setFrom(collider.position);
    _moving = native.velocityOf(handle).length2 != 0.0;
  }

  /// Moved, or refiltered, as [collider] was. Moved, it is given the
  /// velocity it moved at over the [dt] coming: a lift that only jumped would
  /// push a crate on it out of its floor a little each step and leave it
  /// behind, where one that moves carries it.
  void follow(NativeWorld native, Collider collider, double dt) {
    final moved = _at != collider.position;
    if (moved) {
      native
        ..setPosition(handle, collider.position + offset)
        ..setVelocity(handle, (collider.position - _at) / dt);
      _at.setFrom(collider.position);
    } else if (_moving) {
      native.setVelocity(handle, Vector3.zero());
    }
    _moving = moved;
    if (_layer != collider.layer || _mask != collider.mask) {
      placed(native, collider);
    }
  }
}
