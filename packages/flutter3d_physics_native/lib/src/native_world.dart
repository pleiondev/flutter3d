/// A physics world stepped by the C core — P9.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math.dart';

import 'bindings.dart' as c;

/// A body in a [NativeWorld]: its slot and the slot's generation, packed as
/// the C core packs them. Nought is never one.
extension type const NativeBody(int raw) {
  /// The arena slot.
  int get slot => raw & 0xffffffff;

  /// How many times the slot had been used when this body took it.
  int get generation => raw >>> 32;
}

/// What kind of body — `F3dBodyType`.
///
/// A class of constants rather than an enum: kinematic bodies arrive in a
/// later phase, and a value added to an enum breaks every switch written
/// against it.
final class NativeBodyType {
  const NativeBodyType._(this.code, this.name);

  /// Moved by gravity, forces, wind and contacts.
  static const NativeBodyType dynamic = NativeBodyType._(
    c.BodyType.dynamic,
    'dynamic',
  );

  /// Never moves. It still heats, cools and burns.
  static const NativeBodyType fixed = NativeBodyType._(
    c.BodyType.fixed,
    'fixed',
  );

  /// The core's number for it.
  final int code;
  final String name;

  @override
  String toString() => 'NativeBodyType.$name';
}

/// What a body is shaped like: what it collides as, and its inertia, its
/// surface and its drag — `F3dShapeKind` and its three numbers.
final class NativeShape {
  const NativeShape._(this.kind, this.first, this.second, this.third);

  /// No extent: it touches nothing, does not turn, has no surface and feels
  /// no wind. What a new body is.
  static const NativeShape point = NativeShape._(c.ShapeKind.point, 0, 0, 0);

  const NativeShape.sphere(double radius)
    : this._(c.ShapeKind.sphere, radius, 0, 0);

  /// Half extents along the body's own axes.
  NativeShape.box(Vector3 halfExtents)
    : this._(c.ShapeKind.box, halfExtents.x, halfExtents.y, halfExtents.z);

  /// Upright along the body's y: a cylinder [halfLength] each way from the
  /// centre, capped by hemispheres of [radius].
  const NativeShape.capsule(double radius, double halfLength)
    : this._(c.ShapeKind.capsule, radius, halfLength, 0);

  /// Upright along the body's y, [halfHeight] each way from the centre.
  const NativeShape.cylinder(double radius, double halfHeight)
    : this._(c.ShapeKind.cylinder, radius, halfHeight, 0);

  /// Its apex up along the body's y, [height] tall over a base of
  /// [radius]; its origin at its centre of mass, a quarter of the height
  /// above the base.
  const NativeShape.cone(double radius, double height)
    : this._(c.ShapeKind.cone, radius, height, 0);

  /// `F3dShapeKind`.
  final int kind;

  /// The three numbers the kind reads, as the constructors name them.
  final double first, second, third;
}

/// A convex hull the world holds, for bodies to be shaped as
/// ([NativeWorld.setHull]). Numbered from one.
extension type const NativeHull(int id) {}

/// A triangle mesh the world holds, for fixed bodies to be shaped as
/// ([NativeWorld.setMesh]). Numbered from one.
extension type const NativeMesh(int id) {}

/// A joint in a [NativeWorld], named as a body is.
extension type const NativeJoint(int raw) {}

/// What kind of joint — `F3dJointType`.
final class NativeJointType {
  const NativeJointType._(this.code, this.name);

  /// Holds B where it was against A, place and turn.
  static const NativeJointType fixed = NativeJointType._(
    c.JointType.fixed,
    'fixed',
  );

  /// Holds a point of each together; they turn freely about it.
  static const NativeJointType spherical = NativeJointType._(
    c.JointType.spherical,
    'spherical',
  );

  /// A hinge about the axis.
  static const NativeJointType revolute = NativeJointType._(
    c.JointType.revolute,
    'revolute',
  );

  /// A slider along the axis.
  static const NativeJointType prismatic = NativeJointType._(
    c.JointType.prismatic,
    'prismatic',
  );

  final int code;
  final String name;

  @override
  String toString() => 'NativeJointType.$name';
}

/// What a body is made of, as heat and fire see it — `F3dMaterial`.
final class NativeMaterial {
  const NativeMaterial({
    required this.specificHeat,
    this.emissivity = 0.9,
    this.ignitionTemperature = 0.0,
    this.heatOfCombustion = 0.0,
    this.burnRate = 0.0,
    this.fuelFraction = 0.0,
    this.flameFeedback = 0.0,
    this.conductivity = 1.0,
  });

  /// The core's typical values for a material: one place they live, so the
  /// browser's module and the native library agree on them too.
  static NativeMaterial inert() => _preset(c.MaterialKind.inert);
  static NativeMaterial wood() => _preset(c.MaterialKind.wood);
  static NativeMaterial paper() => _preset(c.MaterialKind.paper);
  static NativeMaterial rubber() => _preset(c.MaterialKind.rubber);
  static NativeMaterial steel() => _preset(c.MaterialKind.steel);
  static NativeMaterial stone() => _preset(c.MaterialKind.stone);

  static NativeMaterial _preset(int kind) {
    final out = calloc<c.F3dMaterial>();
    try {
      c.f3d_material_preset(kind, out);
      final m = out.ref;
      return NativeMaterial(
        specificHeat: m.specific_heat,
        emissivity: m.emissivity,
        ignitionTemperature: m.ignition_temperature,
        heatOfCombustion: m.heat_of_combustion,
        burnRate: m.burn_rate,
        fuelFraction: m.fuel_fraction,
        flameFeedback: m.flame_feedback,
        conductivity: m.conductivity,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// J / (kg K).
  final double specificHeat;

  /// Of the surface, nought to one.
  final double emissivity;

  /// K at which it catches and below which it goes out; nought for a
  /// material that never burns.
  final double ignitionTemperature;

  /// J released per kilogram burnt.
  final double heatOfCombustion;

  /// kg burnt per second per square metre of surface while alight.
  final double burnRate;

  /// The share of the mass that can burn, nought up to but not one.
  final double fuelFraction;

  /// The share of the fire's heat that goes back into the body; the rest
  /// leaves as the hot gas a smoke grid takes.
  final double flameFeedback;

  /// W / (m K): how readily heat crosses into what it touches.
  final double conductivity;
}

/// What a step said happened to a body — `F3dEventKind`. Constants rather
/// than an enum, for the reason [NativeBodyType] gives: the solver and the
/// joints will bring kinds of their own.
final class NativeEventKind {
  const NativeEventKind._(this.code, this.name);

  static const NativeEventKind slept = NativeEventKind._(
    c.EventKind.slept,
    'slept',
  );
  static const NativeEventKind woke = NativeEventKind._(
    c.EventKind.woke,
    'woke',
  );
  static const NativeEventKind ignited = NativeEventKind._(
    c.EventKind.ignited,
    'ignited',
  );
  static const NativeEventKind extinguished = NativeEventKind._(
    c.EventKind.extinguished,
    'extinguished',
  );
  static const NativeEventKind burntOut = NativeEventKind._(
    c.EventKind.burntOut,
    'burntOut',
  );

  /// Two bodies came to touch; the event's `other` is the second.
  static const NativeEventKind contactBegan = NativeEventKind._(
    c.EventKind.contactBegan,
    'contactBegan',
  );

  /// Two bodies stopped touching. Ended by a body's removal, it names a body
  /// no longer there.
  static const NativeEventKind contactEnded = NativeEventKind._(
    c.EventKind.contactEnded,
    'contactEnded',
  );

  static const List<NativeEventKind> _all = <NativeEventKind>[
    slept,
    woke,
    ignited,
    extinguished,
    burntOut,
    contactBegan,
    contactEnded,
  ];

  /// The kind the core's [code] names; one this binding does not know yet
  /// keeps its number.
  static NativeEventKind of(int code) => _all.firstWhere(
    (k) => k.code == code,
    orElse: () => NativeEventKind._(code, 'unknown($code)'),
  );

  final int code;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is NativeEventKind && other.code == code;

  @override
  int get hashCode => code;

  @override
  String toString() => 'NativeEventKind.$name';
}

/// One event, in the order the step raised it. [other] is the second body
/// of an event between two, and null for the rest.
typedef NativeEvent = ({
  NativeBody body,
  NativeBody? other,
  NativeEventKind kind,
});

/// Where two bodies touch: one point of their manifold.
typedef NativeContact = ({
  NativeBody a,
  NativeBody b,

  /// Out of [b], into [a]: the way [a] moves to come apart.
  Vector3 normal,

  /// Halfway between the two surfaces, relative to the origin.
  Vector3 point,

  /// Positive inside, negative for a gap within the margin.
  double depth,
});

/// Where a query met a body: the point and the normal there, out of the
/// body, relative to the origin, and the distance along a ray or the
/// fraction of a cast.
typedef NativeHit = ({
  NativeBody body,
  Vector3 point,
  Vector3 normal,
  double at,
});

/// Where a character ended up, and what it stood on.
typedef NativeCharacterMove = ({
  Vector3 position,
  bool grounded,
  bool hitWall,
  bool hitCeiling,
  bool stepped,

  /// The ground's normal, or zero in the air.
  Vector3 groundNormal,

  /// What it stands on, or null in the air.
  NativeBody? ground,
});

/// A point in doubles: the world's origin, or a body's place in the world's
/// own coordinates. Not a [Vector3], which holds single precision and
/// would round away what the origin is for.
typedef WorldPoint = ({double x, double y, double z});

/// A world of bodies owned and stepped by the C core.
///
/// **Numbers cross as f32.** The core is single precision throughout, which
/// is what makes its deterministic mode the same bits on every platform, so a
/// value set here is rounded to the nearest float on the way in. Positions
/// are relative to the world's [origin], held in doubles; a world far
/// larger than f32 can hold to a millimetre moves its origin to the play
/// with [shiftOrigin].
///
/// Freed by [dispose], or by the garbage collector when a world is dropped
/// without it. Every call after [dispose] throws a [StateError], so a world
/// used after it was freed is a Dart error rather than a native crash.
final class NativeWorld implements Finalizable {
  NativeWorld() : _world = c.f3d_world_create() {
    if (_world == nullptr) {
      throw StateError('the physics core could not allocate a world');
    }
    if (c.f3d_abi_version() != c.abiVersion || c.f3d_real_bytes() != 4) {
      c.f3d_world_destroy(_world);
      throw StateError(
        'the physics core is ABI ${c.f3d_abi_version()} with '
        '${c.f3d_real_bytes()}-byte reals, and these bindings were written '
        'for ABI ${c.abiVersion} with 4',
      );
    }
    _finalizer.attach(this, _world.cast(), detach: this);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<c.F3dWorld>)>>(
      c.f3d_world_destroy,
    ).cast(),
  );

  Pointer<c.F3dWorld> _world;

  /// Scratch the getters write into: the world's own, freed with it.
  final Pointer<Float> _out = malloc<Float>(4);
  final Pointer<Double> _outDouble = malloc<Double>(3);
  final Pointer<Int32> _outInt = malloc<Int32>(1);

  Pointer<c.F3dWorld> get _live {
    if (_world == nullptr) throw StateError('this world was disposed');
    return _world;
  }

  /// Frees the world and everything in it. Calling it again does nothing.
  void dispose() {
    if (_world == nullptr) return;
    _finalizer.detach(this);
    c.f3d_world_destroy(_world);
    malloc
      ..free(_out)
      ..free(_outDouble)
      ..free(_outInt);
    _world = nullptr;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _world == nullptr;

  Vector3 _read3() => Vector3(_out[0], _out[1], _out[2]);

  // ---------------------------------------------------------------- world

  /// Metres per second squared; (0, −9.81, 0) for a new world.
  Vector3 get gravity {
    c.f3d_world_get_gravity(_live, _out);
    return _read3();
  }

  set gravity(Vector3 value) =>
      c.f3d_world_set_gravity(_live, value.x, value.y, value.z);

  /// The air's temperature, K; 293.15 for a new world.
  double get airTemperature {
    c.f3d_world_get_air(_live, _out);
    return _out[0];
  }

  /// The air's density, kg/m³; 1.204 for a new world.
  double get airDensity {
    c.f3d_world_get_air(_live, _out);
    return _out[1];
  }

  /// Sets both. Throws an [ArgumentError] for a value that is not finite
  /// and positive.
  void setAir({required double temperature, required double density}) {
    if (c.f3d_world_set_air(_live, temperature, density) == 0) {
      throw ArgumentError('air of $temperature K and $density kg/m³');
    }
  }

  /// The wind everywhere, m/s, added to the grid's where there is one.
  /// Changing it wakes every body that feels it.
  set wind(Vector3 value) =>
      c.f3d_world_set_wind(_live, value.x, value.y, value.z);

  /// A wind field of [nx] × [ny] × [nz] samples, three floats each, x
  /// fastest, the first at [origin] (relative to the world's origin) and
  /// [cell] metres apart; read trilinearly and held at its edge. Throws an
  /// [ArgumentError] for a size or spacing that is not positive or a list
  /// of the wrong length.
  void setWindGrid({
    required Vector3 origin,
    required double cell,
    required int nx,
    required int ny,
    required int nz,
    required Float32List velocities,
  }) {
    if (velocities.length != nx * ny * nz * 3) {
      throw ArgumentError.value(
        velocities.length,
        'velocities',
        'not 3 × $nx × $ny × $nz',
      );
    }
    final buffer = malloc<Float>(velocities.isEmpty ? 1 : velocities.length);
    try {
      buffer.asTypedList(velocities.length).setAll(0, velocities);
      final done = c.f3d_world_set_wind_grid(
        _live,
        origin.x,
        origin.y,
        origin.z,
        cell,
        nx,
        ny,
        nz,
        buffer,
      );
      if (done == 0) {
        throw ArgumentError('a wind grid of $nx × $ny × $nz, $cell m apart');
      }
    } finally {
      malloc.free(buffer);
    }
  }

  /// Takes the wind grid away, leaving the uniform wind.
  void clearWindGrid() =>
      c.f3d_world_set_wind_grid(_live, 0, 0, 0, 1, 0, 0, 0, nullptr);

  /// The wind at [at], relative to the origin.
  Vector3 windAt(Vector3 at) {
    c.f3d_world_sample_wind(_live, at.x, at.y, at.z, _out);
    return _read3();
  }

  /// How long, s, a body must stay slower than [speed] (m/s and rad/s) to
  /// fall asleep; a [time] of nought turns sleep off. Defaults 0.05 and 0.5.
  void setSleep({required double speed, required double time}) {
    if (c.f3d_world_set_sleep(_live, speed, time) == 0) {
      throw ArgumentError('sleep after $time s under $speed');
    }
  }

  /// Where the world's origin is, in doubles.
  WorldPoint get origin {
    c.f3d_world_get_origin(_live, _outDouble);
    return (x: _outDouble[0], y: _outDouble[1], z: _outDouble[2]);
  }

  /// Moves the origin by (dx, dy, dz), and every body and the wind grid
  /// the other way, so that nothing moves in the world and what is near
  /// the new origin gets f32's full precision back.
  void shiftOrigin(double dx, double dy, double dz) =>
      c.f3d_world_shift_origin(_live, dx, dy, dz);

  /// How many bodies the world holds.
  int get bodyCount => c.f3d_world_body_count(_live);

  /// Advances the world by [dt] seconds; nothing for a [dt] that is not
  /// finite and positive.
  void step(double dt) => c.f3d_world_step(_live, dt);

  /// Every body's transform, seven floats apiece — position xyz relative to
  /// the origin, then the orientation quaternion xyzw — and its handle, in
  /// the world's slot order: what the renderer uploads as instance
  /// transforms.
  ({Float32List transforms, List<NativeBody> bodies}) readTransforms() =>
      _readPer(bodyCount, c.transformFloats, c.f3d_world_read_transforms);

  /// Every burning body: its position and the watts it gives off as hot gas,
  /// four floats apiece — what a smoke grid takes its sources from.
  ({Float32List fires, List<NativeBody> bodies}) readFires() {
    final read = _readPer(bodyCount, c.fireFloats, c.f3d_world_read_fires);
    return (fires: read.transforms, bodies: read.bodies);
  }

  ({Float32List transforms, List<NativeBody> bodies}) _readPer(
    int count,
    int floats,
    int Function(Pointer<c.F3dWorld>, Pointer<Float>, Pointer<Uint64>, int)
    read,
  ) {
    if (count == 0) {
      return (transforms: Float32List(0), bodies: const <NativeBody>[]);
    }
    final values = malloc<Float>(count * floats);
    final handles = malloc<Uint64>(count);
    try {
      final written = read(_live, values, handles, count);
      return (
        transforms: Float32List.fromList(values.asTypedList(written * floats)),
        bodies: <NativeBody>[
          for (var i = 0; i < written; i++) NativeBody(handles[i]),
        ],
      );
    } finally {
      malloc
        ..free(values)
        ..free(handles);
    }
  }

  /// The events the steps raised since the last call, oldest first.
  List<NativeEvent> readEvents() {
    const batch = 256;
    final bodies = malloc<Uint64>(batch);
    final others = malloc<Uint64>(batch);
    final kinds = malloc<Uint32>(batch);
    try {
      final events = <NativeEvent>[];
      while (true) {
        final read = c.f3d_world_read_events(
          _live,
          bodies,
          others,
          kinds,
          batch,
        );
        for (var i = 0; i < read; i++) {
          events.add((
            body: NativeBody(bodies[i]),
            other: others[i] == 0 ? null : NativeBody(others[i]),
            kind: NativeEventKind.of(kinds[i]),
          ));
        }
        if (read < batch) return events;
      }
    } finally {
      malloc
        ..free(bodies)
        ..free(others)
        ..free(kinds);
    }
  }

  /// A convex hull of [points], built and kept by the world: moved so its
  /// centre of mass, taken as solid, is at the origin of the bodies shaped
  /// as it — [hullOffset] says by how much. Throws an [ArgumentError] for
  /// fewer than four points not all in a plane, more than 4096, or a point
  /// not finite.
  NativeHull createHull(List<Vector3> points) {
    final buffer = malloc<Float>(points.isEmpty ? 3 : points.length * 3);
    try {
      for (var i = 0; i < points.length; i++) {
        buffer[i * 3] = points[i].x;
        buffer[i * 3 + 1] = points[i].y;
        buffer[i * 3 + 2] = points[i].z;
      }
      final id = c.f3d_world_create_hull(_live, buffer, points.length);
      if (id == 0) {
        throw ArgumentError.value(
          points.length,
          'points',
          'not four or more points, finite, not all in one plane',
        );
      }
      return NativeHull(id);
    } finally {
      malloc.free(buffer);
    }
  }

  /// What was subtracted from every point [hull] was made from.
  Vector3 hullOffset(NativeHull hull) {
    if (c.f3d_world_get_hull_offset(_live, hull.id, _out) == 0) {
      throw ArgumentError.value(hull.id, 'hull', 'not in this world');
    }
    return _read3();
  }

  /// How many of the points [hull] was made from are its corners.
  int hullVertexCount(NativeHull hull) =>
      c.f3d_world_hull_vertex_count(_live, hull.id);

  /// A triangle mesh of [vertices] and [indices], three a triangle, wound
  /// counter-clockwise seen from the side bodies touch: level geometry,
  /// terrain, walls. One sided. Triangles that share an edge by index
  /// slide a body across it without a bump. Throws an [ArgumentError] for
  /// no triangles, an index past the vertices or a vertex not finite.
  NativeMesh createMesh(List<Vector3> vertices, List<int> indices) {
    if (indices.length % 3 != 0) {
      throw ArgumentError.value(
        indices.length,
        'indices',
        'not three a triangle',
      );
    }
    final v = malloc<Float>(vertices.isEmpty ? 3 : vertices.length * 3);
    final t = malloc<Uint32>(indices.isEmpty ? 3 : indices.length);
    try {
      for (var i = 0; i < vertices.length; i++) {
        v[i * 3] = vertices[i].x;
        v[i * 3 + 1] = vertices[i].y;
        v[i * 3 + 2] = vertices[i].z;
      }
      for (var i = 0; i < indices.length; i++) {
        if (indices[i] < 0) {
          throw ArgumentError.value(indices[i], 'indices', 'negative');
        }
        t[i] = indices[i];
      }
      final id = c.f3d_world_create_mesh(
        _live,
        v,
        vertices.length,
        t,
        indices.length ~/ 3,
      );
      if (id == 0) {
        throw ArgumentError.value(
          indices.length ~/ 3,
          'indices',
          'no triangles, an index past the vertices, or a vertex not finite',
        );
      }
      return NativeMesh(id);
    } finally {
      malloc
        ..free(v)
        ..free(t);
    }
  }

  /// How many triangles [mesh] has.
  int meshTriangleCount(NativeMesh mesh) =>
      c.f3d_world_mesh_triangle_count(_live, mesh.id);

  /// How many of [mesh]'s edges are internal: shared with a neighbour
  /// across a flat or hollow fold.
  int meshInternalEdges(NativeMesh mesh) =>
      c.f3d_world_mesh_internal_edges(_live, mesh.id);

  /// A joint of [type] between [a] and [b] at [anchor], along [axis] for a
  /// hinge or a slider, taken where the bodies stand now. Joined bodies do
  /// not collide with each other unless [setJointCollide] says so. Throws an
  /// [ArgumentError] for a body not in the world, a body joined to itself,
  /// or a hinge or slider with no axis.
  NativeJoint createJoint(
    NativeJointType type,
    NativeBody a,
    NativeBody b, {
    required Vector3 anchor,
    Vector3? axis,
  }) {
    final u = axis ?? Vector3.zero();
    final raw = c.f3d_joint_create(
      _live,
      type.code,
      a.raw,
      b.raw,
      anchor.x,
      anchor.y,
      anchor.z,
      u.x,
      u.y,
      u.z,
    );
    if (raw == 0) {
      throw ArgumentError('a ${type.name} joint the core would not make');
    }
    return NativeJoint(raw);
  }

  /// A distance joint from [anchorA] on [a] to [anchorB] on [b], held at
  /// the length between them now: a rod, until [setJointSpring] makes it a
  /// spring, or with nought hertz and a least of nought, a rope.
  NativeJoint createDistanceJoint(
    NativeBody a,
    NativeBody b, {
    required Vector3 anchorA,
    required Vector3 anchorB,
  }) {
    final raw = c.f3d_joint_create_distance(
      _live,
      a.raw,
      b.raw,
      anchorA.x,
      anchorA.y,
      anchorA.z,
      anchorB.x,
      anchorB.y,
      anchorB.z,
    );
    if (raw == 0) {
      throw ArgumentError('a distance joint the core would not make');
    }
    return NativeJoint(raw);
  }

  /// Takes [joint] out, and says whether it was there. A body's joints go
  /// with it.
  bool removeJoint(NativeJoint joint) =>
      c.f3d_joint_destroy(_live, joint.raw) == 1;

  bool containsJoint(NativeJoint joint) =>
      c.f3d_joint_is_valid(_live, joint.raw) == 1;

  int get jointCount => c.f3d_world_joint_count(_live);

  void _checkJoint(int answer, NativeJoint joint) {
    if (answer != 0) return;
    if (c.f3d_joint_is_valid(_live, joint.raw) == 0) {
      throw ArgumentError.value(joint.raw, 'joint', 'not in this world');
    }
    throw ArgumentError('not a setting this joint takes, or out of range');
  }

  /// Limits on a hinge's angle, radians, or a slider's travel, m; null
  /// takes them off.
  void setJointLimits(
    NativeJoint joint,
    ({double lower, double upper})? limits,
  ) => _checkJoint(
    c.f3d_joint_set_limits(
      _live,
      joint.raw,
      limits == null ? 0 : 1,
      limits?.lower ?? 0.0,
      limits?.upper ?? 0.0,
    ),
    joint,
  );

  /// A motor driving a hinge or slider at [speed] with at most [maxForce];
  /// null takes it off.
  void setJointMotor(
    NativeJoint joint,
    ({double speed, double maxForce})? motor,
  ) => _checkJoint(
    c.f3d_joint_set_motor(
      _live,
      joint.raw,
      motor == null ? 0 : 1,
      motor?.speed ?? 0.0,
      motor?.maxForce ?? 0.0,
    ),
    joint,
  );

  /// A spring pulling a hinge or slider back to where it started, or a
  /// distance joint to its length; null takes it off.
  void setJointSpring(
    NativeJoint joint,
    ({double hertz, double damping})? spring,
  ) => _checkJoint(
    c.f3d_joint_set_spring(
      _live,
      joint.raw,
      spring == null ? 0 : 1,
      spring?.hertz ?? 0.0,
      spring?.damping ?? 0.0,
    ),
    joint,
  );

  /// A distance joint's rest [length] and the [least] and [most] its
  /// spring may stretch it to.
  void setJointLength(
    NativeJoint joint, {
    required double length,
    required double least,
    required double most,
  }) => _checkJoint(
    c.f3d_joint_set_length(_live, joint.raw, length, least, most),
    joint,
  );

  /// Whether [joint]'s bodies collide with each other.
  void setJointCollide(NativeJoint joint, {required bool collide}) =>
      _checkJoint(
        c.f3d_joint_set_collide(_live, joint.raw, collide ? 1 : 0),
        joint,
      );

  /// A hinge's angle from where it started, a slider's travel, a distance
  /// joint's length; nought for the others.
  double jointValue(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_value(_live, joint.raw, _out), joint);
    return _out[0];
  }

  /// The force [joint] held its second body with over the last substep, N.
  Vector3 jointForce(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_force(_live, joint.raw, _out), joint);
    return _read3();
  }

  /// How many substeps a step is solved in, one to sixty-four; four for a
  /// new world. More holds tall stacks and fast bodies better and costs that
  /// many times the solver. A step of n substeps is n steps of dt / n.
  set substeps(int count) {
    if (c.f3d_world_set_substeps(_live, count) == 0) {
      throw ArgumentError.value(count, 'substeps', 'not between 1 and 64');
    }
  }

  /// How many threads a step runs on, the caller one of them; one for a
  /// new world. The tree's queries and the narrow phase are shared out
  /// among them, and the world steps to the same bits on any number.
  int get threads => c.f3d_world_threads(_live);

  /// Asks for [count] threads, one to sixty-four, from the next step on.
  /// Throws for a count out of range, threads that would not start, or —
  /// on the web — more than one.
  set threads(int count) {
    if (c.f3d_world_set_threads(_live, count) == 0) {
      throw ArgumentError.value(
        count,
        'threads',
        'not between 1 and 64, or the threads would not start',
      );
    }
  }

  /// The fast mode, off for a new world: contacts coloured each step so
  /// that no two of a colour share a moving body, and a colour's contacts
  /// solved at once on every thread. Other bits than the deterministic
  /// mode's, since the contacts are solved in another order — but the same
  /// bits on any number of threads. Kept in a snapshot.
  bool get fast => c.f3d_world_fast(_live) != 0;

  set fast(bool enabled) => c.f3d_world_set_fast(_live, enabled ? 1 : 0);

  /// Soft continuous collision, on for a new world: a contact reaches as
  /// far as its two bodies can close in a step, so a body stops at a wall
  /// it would cross in one.
  set speculative(bool enabled) =>
      c.f3d_world_set_speculative(_live, enabled ? 1 : 0);

  /// How near two shapes must come to make a contact, m; 0.02 for a new
  /// world. A contact inside it but not touching has a negative depth.
  set contactMargin(double margin) {
    if (c.f3d_world_set_contact_margin(_live, margin) == 0) {
      throw ArgumentError.value(margin, 'margin', 'negative or not finite');
    }
  }

  /// Every body whose shape's box overlaps the box from [lo] to [hi],
  /// relative to the origin, in slot order: what the broadphase tree finds,
  /// checked against each body's own box. Bodies with no shape are never
  /// found.
  List<NativeBody> queryBox(Vector3 lo, Vector3 hi) {
    var capacity = 64;
    while (true) {
      final out = malloc<Uint64>(capacity);
      try {
        final count = c.f3d_world_query_box(
          _live,
          lo.x,
          lo.y,
          lo.z,
          hi.x,
          hi.y,
          hi.z,
          out,
          capacity,
        );
        if (count <= capacity) {
          return <NativeBody>[
            for (var i = 0; i < count; i++) NativeBody(out[i]),
          ];
        }
        capacity = count;
      } finally {
        malloc.free(out);
      }
    }
  }

  NativeHit _hitAt(int body, Pointer<Float> h) => (
    body: NativeBody(body),
    point: Vector3(h[0], h[1], h[2]),
    normal: Vector3(h[3], h[4], h[5]),
    at: h[6],
  );

  /// The nearest body a ray from [origin] along [direction] meets within
  /// [maxDistance], or null. Bodies whose layer has no bit in [mask], and
  /// [ignore], are not seen; nor is a shape the ray starts inside; meshes
  /// only from their front.
  NativeHit? rayCast(
    Vector3 origin,
    Vector3 direction,
    double maxDistance, {
    int mask = 0xffffffff,
    NativeBody? ignore,
  }) {
    final body = malloc<Uint64>(1);
    final hit = malloc<Float>(c.hitFloats);
    try {
      final found = c.f3d_world_ray_cast(
        _live,
        origin.x,
        origin.y,
        origin.z,
        direction.x,
        direction.y,
        direction.z,
        maxDistance,
        mask,
        ignore?.raw ?? 0,
        body,
        hit,
      );
      return found == 0 ? null : _hitAt(body[0], hit);
    } finally {
      malloc
        ..free(body)
        ..free(hit);
    }
  }

  /// Every body the ray meets, nearest first.
  List<NativeHit> rayCastAll(
    Vector3 origin,
    Vector3 direction,
    double maxDistance, {
    int mask = 0xffffffff,
    NativeBody? ignore,
  }) {
    var capacity = 16;
    while (true) {
      final bodies = malloc<Uint64>(capacity);
      final hits = malloc<Float>(capacity * c.hitFloats);
      try {
        final count = c.f3d_world_ray_cast_all(
          _live,
          origin.x,
          origin.y,
          origin.z,
          direction.x,
          direction.y,
          direction.z,
          maxDistance,
          mask,
          ignore?.raw ?? 0,
          bodies,
          hits,
          capacity,
        );
        if (count <= capacity) {
          return <NativeHit>[
            for (var i = 0; i < count; i++)
              _hitAt(bodies[i], hits + i * c.hitFloats),
          ];
        }
        capacity = count;
      } finally {
        malloc
          ..free(bodies)
          ..free(hits);
      }
    }
  }

  /// Every body overlapping [shape] (not a point, a hull or a mesh),
  /// rounded by [rounding], at [position] turned by [orientation], in slot
  /// order.
  List<NativeBody> overlapShape(
    NativeShape shape,
    Vector3 position, {
    Quaternion? orientation,
    double rounding = 0.0,
    int mask = 0xffffffff,
    NativeBody? ignore,
  }) {
    final q = orientation ?? Quaternion.identity();
    var capacity = 32;
    while (true) {
      final out = malloc<Uint64>(capacity);
      try {
        final count = c.f3d_world_overlap_shape(
          _live,
          shape.kind,
          shape.first,
          shape.second,
          shape.third,
          rounding,
          position.x,
          position.y,
          position.z,
          q.x,
          q.y,
          q.z,
          q.w,
          mask,
          ignore?.raw ?? 0,
          out,
          capacity,
        );
        if (count <= capacity) {
          return <NativeBody>[
            for (var i = 0; i < count; i++) NativeBody(out[i]),
          ];
        }
        capacity = count;
      } finally {
        malloc.free(out);
      }
    }
  }

  /// The first body [shape] meets moved from [position] by [translation]
  /// without turning, and the fraction of the move it got; nought when it
  /// starts overlapping.
  NativeHit? castShape(
    NativeShape shape,
    Vector3 position,
    Vector3 translation, {
    Quaternion? orientation,
    double rounding = 0.0,
    int mask = 0xffffffff,
    NativeBody? ignore,
  }) {
    final q = orientation ?? Quaternion.identity();
    final body = malloc<Uint64>(1);
    final hit = malloc<Float>(c.hitFloats);
    try {
      final found = c.f3d_world_cast_shape(
        _live,
        shape.kind,
        shape.first,
        shape.second,
        shape.third,
        rounding,
        position.x,
        position.y,
        position.z,
        q.x,
        q.y,
        q.z,
        q.w,
        translation.x,
        translation.y,
        translation.z,
        mask,
        ignore?.raw ?? 0,
        body,
        hit,
      );
      return found == 0 ? null : _hitAt(body[0], hit);
    } finally {
      malloc
        ..free(body)
        ..free(hit);
    }
  }

  /// Moves an upright capsule — a character — of [radius] and straight
  /// [halfHeight] from [position] by [move], sliding along what it meets:
  /// ground whose normal's height is at least [maxSlopeCos] — the cosine of
  /// the steepest slope it stands on, forty-five degrees by default — it
  /// stands on, steeper it slides along as a wall, a step up to
  /// [stepHeight] it climbs, and walking down it keeps to the ground.
  /// Kinematic: nothing pushes it, and it moves nothing.
  ///
  /// **A cosine, not an angle.** Turning an angle into one here would ask
  /// the platform's library, whose last bit differs from machine to
  /// machine, and a character's step must not.
  NativeCharacterMove moveCharacter({
    required double radius,
    required double halfHeight,
    required Vector3 position,
    required Vector3 move,
    double maxSlopeCos = 0.7071067811865476,
    double stepHeight = 0.35,
    int mask = 0xffffffff,
    NativeBody? ignore,
  }) {
    final p = malloc<Float>(3);
    final ground = malloc<Float>(3);
    final body = malloc<Uint64>(1);
    try {
      p[0] = position.x;
      p[1] = position.y;
      p[2] = position.z;
      final flags = c.f3d_world_move_character(
        _live,
        radius,
        halfHeight,
        p,
        move.x,
        move.y,
        move.z,
        maxSlopeCos,
        stepHeight,
        mask,
        ignore?.raw ?? 0,
        body,
        ground,
      );
      return (
        position: Vector3(p[0], p[1], p[2]),
        grounded: flags & c.CharacterFlags.grounded != 0,
        hitWall: flags & c.CharacterFlags.wall != 0,
        hitCeiling: flags & c.CharacterFlags.ceiling != 0,
        stepped: flags & c.CharacterFlags.stepped != 0,
        groundNormal: Vector3(ground[0], ground[1], ground[2]),
        ground: body[0] == 0 ? null : NativeBody(body[0]),
      );
    } finally {
      malloc
        ..free(p)
        ..free(ground)
        ..free(body);
    }
  }

  /// Every contact point the last step found, in order of the pair's slots.
  List<NativeContact> readContacts() {
    final count = c.f3d_world_contact_count(_live);
    if (count == 0) return const <NativeContact>[];
    final values = malloc<Float>(count * c.contactFloats);
    final pairs = malloc<Uint64>(count * 2);
    try {
      final read = c.f3d_world_read_contacts(_live, values, pairs, count);
      return <NativeContact>[
        for (var i = 0; i < read; i++)
          (
            a: NativeBody(pairs[i * 2]),
            b: NativeBody(pairs[i * 2 + 1]),
            normal: Vector3(
              values[i * c.contactFloats],
              values[i * c.contactFloats + 1],
              values[i * c.contactFloats + 2],
            ),
            point: Vector3(
              values[i * c.contactFloats + 3],
              values[i * c.contactFloats + 4],
              values[i * c.contactFloats + 5],
            ),
            depth: values[i * c.contactFloats + 6],
          ),
      ];
    } finally {
      malloc
        ..free(values)
        ..free(pairs);
    }
  }

  /// Events dropped because 65 536 were waiting unread.
  int get eventsDropped => c.f3d_world_events_dropped(_live);

  // ------------------------------------------------------------ snapshots

  /// The world's whole state. A world [restore]d from it steps to the same
  /// bits this one does.
  Uint8List snapshot() {
    final size = c.f3d_world_snapshot_size(_live);
    final buffer = malloc<Uint8>(size);
    try {
      final written = c.f3d_world_snapshot_write(_live, buffer, size);
      if (written != size) {
        throw StateError('the physics core wrote $written of $size bytes');
      }
      return Uint8List.fromList(buffer.asTypedList(size));
    } finally {
      malloc.free(buffer);
    }
  }

  /// Puts the world back as [snapshot] says. Throws an [ArgumentError] for
  /// bytes that are not a snapshot from this build of the core, and leaves
  /// the world as it was.
  void restore(Uint8List snapshot) {
    final buffer = malloc<Uint8>(snapshot.isEmpty ? 1 : snapshot.length);
    try {
      buffer.asTypedList(snapshot.length).setAll(0, snapshot);
      if (c.f3d_world_restore(_live, buffer, snapshot.length) == 0) {
        throw ArgumentError.value(
          snapshot.length,
          'snapshot',
          'not a snapshot from this build of the physics core',
        );
      }
    } finally {
      malloc.free(buffer);
    }
  }

  // --------------------------------------------------------------- bodies

  /// Adds a body at [position] and returns it: at rest, unrotated, a point
  /// of inert material at the air's temperature. A fixed body's [mass] is
  /// its thermal mass only.
  ///
  /// Throws an [ArgumentError] for a dynamic body whose [mass] is not
  /// finite and positive, or a [position] that is not finite — the core
  /// refuses both, and a refusal here says which.
  NativeBody addBody({
    required Vector3 position,
    NativeBodyType type = NativeBodyType.dynamic,
    double mass = 1.0,
  }) {
    final raw = c.f3d_body_create(
      _live,
      type.code,
      position.x,
      position.y,
      position.z,
      mass,
    );
    if (raw == 0) {
      if (type == NativeBodyType.dynamic && !(mass.isFinite && mass > 0.0)) {
        throw ArgumentError.value(mass, 'mass', 'not finite and positive');
      }
      if (!(position.x.isFinite &&
          position.y.isFinite &&
          position.z.isFinite)) {
        throw ArgumentError.value(position, 'position', 'not finite');
      }
      throw StateError('the physics core could not grow its arena');
    }
    return NativeBody(raw);
  }

  /// Takes [body] out of the world, and says whether it was there.
  bool removeBody(NativeBody body) => c.f3d_body_destroy(_live, body.raw) == 1;

  /// Whether [body] names a body in this world.
  bool contains(NativeBody body) => c.f3d_body_is_valid(_live, body.raw) == 1;

  /// [body]'s position, relative to the origin. Throws an [ArgumentError]
  /// for a body not in the world.
  Vector3 positionOf(NativeBody body) {
    _check(c.f3d_body_get_position(_live, body.raw, _out), body);
    return _read3();
  }

  void setPosition(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_position(_live, body.raw, value.x, value.y, value.z),
    body,
    value,
  );

  /// [body]'s position in the world's own coordinates, origin added.
  WorldPoint worldPositionOf(NativeBody body) {
    _check(c.f3d_body_get_world_position(_live, body.raw, _outDouble), body);
    return (x: _outDouble[0], y: _outDouble[1], z: _outDouble[2]);
  }

  /// [body]'s velocity, metres per second.
  Vector3 velocityOf(NativeBody body) {
    _check(c.f3d_body_get_velocity(_live, body.raw, _out), body);
    return _read3();
  }

  void setVelocity(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_velocity(_live, body.raw, value.x, value.y, value.z),
    body,
    value,
  );

  /// Radians per second about the world's axes. Nothing turns a body that
  /// cannot: a point, a fixed body, or one whose rotation is locked.
  Vector3 angularVelocityOf(NativeBody body) {
    _check(c.f3d_body_get_angular_velocity(_live, body.raw, _out), body);
    return _read3();
  }

  void setAngularVelocity(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_angular_velocity(_live, body.raw, value.x, value.y, value.z),
    body,
    value,
  );

  /// How [body] is turned, from its own axes into the world's.
  Quaternion orientationOf(NativeBody body) {
    _check(c.f3d_body_get_orientation(_live, body.raw, _out), body);
    return Quaternion(_out[0], _out[1], _out[2], _out[3]);
  }

  /// Normalised on the way in; a zero quaternion is the identity.
  void setOrientation(NativeBody body, Quaternion value) => _check(
    c.f3d_body_set_orientation(
      _live,
      body.raw,
      value.x,
      value.y,
      value.z,
      value.w,
    ),
    body,
    value,
  );

  /// Gives [body] a shape: its inertia follows from its mass, its surface
  /// and drag from its size.
  void setShape(NativeBody body, NativeShape shape) => _check(
    c.f3d_body_set_shape(
      _live,
      body.raw,
      shape.kind,
      shape.first,
      shape.second,
      shape.third,
    ),
    body,
    shape,
  );

  /// The principal moments of inertia, kg m², in the body's own axes.
  Vector3 inertiaOf(NativeBody body) {
    _check(c.f3d_body_get_inertia(_live, body.raw, _out), body);
    return _read3();
  }

  /// The whole inertia tensor in the body's axes, kg m²: a hull's has
  /// products of inertia off the diagonal.
  Matrix3 inertiaTensorOf(NativeBody body) {
    final out = malloc<Float>(6);
    try {
      _check(c.f3d_body_get_inertia_tensor(_live, body.raw, out), body);
      return Matrix3(
        out[0],
        out[3],
        out[4], //
        out[3],
        out[1],
        out[5], //
        out[4],
        out[5],
        out[2],
      );
    } finally {
      malloc.free(out);
    }
  }

  /// Rounds [body]'s shape out by [radius]: the shape grown by a ball, so a
  /// box gets rounded edges and corners.
  void setRounding(NativeBody body, double radius) =>
      _check(c.f3d_body_set_rounding(_live, body.raw, radius), body, radius);

  /// Shapes [body] as [hull].
  void setHull(NativeBody body, NativeHull hull) =>
      _check(c.f3d_body_set_hull(_live, body.raw, hull.id), body, hull.id);

  /// Shapes a fixed [body] as [mesh]; an [ArgumentError] for one that is
  /// not fixed.
  void setMesh(NativeBody body, NativeMesh mesh) =>
      _check(c.f3d_body_set_mesh(_live, body.raw, mesh.id), body, mesh.id);

  /// Kilograms: less, once it has burnt.
  double massOf(NativeBody body) {
    _check(c.f3d_body_get_mass(_live, body.raw, _out), body);
    return _out[0];
  }

  /// Keeps [body] from turning, whatever its shape, or lets it again.
  void lockRotation(NativeBody body, {bool locked = true}) =>
      _check(c.f3d_body_lock_rotation(_live, body.raw, locked ? 1 : 0), body);

  /// Per second, the share of velocity and of spin taken away, each as
  /// `1 / (1 + dt · damping)`.
  void setDamping(NativeBody body, {double linear = 0, double angular = 0}) =>
      _check(c.f3d_body_set_damping(_live, body.raw, linear, angular), body, (
        linear,
        angular,
      ));

  /// The drag coefficient against the wind; nought takes the shape's own.
  void setDrag(NativeBody body, double coefficient) => _check(
    c.f3d_body_set_drag(_live, body.raw, coefficient),
    body,
    coefficient,
  );

  /// An impulse, N s, through the centre, or at [at] (relative to the
  /// origin), which spins the body as well.
  void applyImpulse(NativeBody body, Vector3 impulse, {Vector3? at}) {
    if (at == null) {
      _check(
        c.f3d_body_apply_impulse(
          _live,
          body.raw,
          impulse.x,
          impulse.y,
          impulse.z,
        ),
        body,
        impulse,
      );
      return;
    }
    _check(
      c.f3d_body_apply_impulse_at(
        _live,
        body.raw,
        impulse.x,
        impulse.y,
        impulse.z,
        at.x,
        at.y,
        at.z,
      ),
      body,
      (impulse, at),
    );
  }

  /// A force, N, held over the next step and spent by it.
  void addForce(NativeBody body, Vector3 force) => _check(
    c.f3d_body_add_force(_live, body.raw, force.x, force.y, force.z),
    body,
    force,
  );

  /// A torque, N m about the world's axes, held over the next step.
  void addTorque(NativeBody body, Vector3 torque) => _check(
    c.f3d_body_add_torque(_live, body.raw, torque.x, torque.y, torque.z),
    body,
    torque,
  );

  /// What [body] is, [layer], and what it meets, [mask]: two bodies collide
  /// when each one's layer has a bit in the other's mask. Defaults 1 and
  /// every bit.
  void setCollisionFilter(
    NativeBody body, {
    required int layer,
    required int mask,
  }) => _check(
    c.f3d_body_set_collision_filter(_live, body.raw, layer, mask),
    body,
  );

  /// Hard continuous collision for [body]: swept after the solve from where
  /// the step began to where it ended, and put back at its first impact.
  /// For what is small and fast.
  void setBullet(NativeBody body, {bool bullet = true}) =>
      _check(c.f3d_body_set_bullet(_live, body.raw, bullet ? 1 : 0), body);

  /// Coulomb's coefficient, nought up; 0.6 for a new body. A pair slides on
  /// the geometric mean of its two.
  void setFriction(NativeBody body, double friction) => _check(
    c.f3d_body_set_friction(_live, body.raw, friction),
    body,
    friction,
  );

  /// The share of the approach speed that comes back, nought to one; nought
  /// for a new body. A pair bounces with the larger of its two, and nothing
  /// bounces that met slower than a metre a second.
  void setRestitution(NativeBody body, double restitution) => _check(
    c.f3d_body_set_restitution(_live, body.raw, restitution),
    body,
    restitution,
  );

  /// Whether [body] sleeps. Bodies sleep and wake by islands: those joined
  /// by their contacts sleep when all have been still for the sleep time,
  /// and wake together when any of them moves.
  bool isAsleep(NativeBody body) {
    _check(c.f3d_body_is_valid(_live, body.raw), body);
    return c.f3d_body_is_asleep(_live, body.raw) == 1;
  }

  /// Wakes [body] and starts its sleep clock again.
  void wake(NativeBody body) => _check(c.f3d_body_wake(_live, body.raw), body);

  // ------------------------------------------------------ heat and fire

  /// What [body] is made of. Its fuel is its mass times the material's fuel
  /// fraction, counted from now.
  void setMaterial(NativeBody body, NativeMaterial material) {
    final m = calloc<c.F3dMaterial>();
    try {
      m.ref
        ..specific_heat = material.specificHeat
        ..emissivity = material.emissivity
        ..ignition_temperature = material.ignitionTemperature
        ..heat_of_combustion = material.heatOfCombustion
        ..burn_rate = material.burnRate
        ..fuel_fraction = material.fuelFraction
        ..flame_feedback = material.flameFeedback
        ..conductivity = material.conductivity;
      _check(c.f3d_body_set_material(_live, body.raw, m), body, material);
    } finally {
      calloc.free(m);
    }
  }

  /// Kelvin.
  double temperatureOf(NativeBody body) {
    _check(c.f3d_body_get_temperature(_live, body.raw, _out), body);
    return _out[0];
  }

  /// Sets it; the next step decides whether that lights a fire or puts one
  /// out.
  void setTemperature(NativeBody body, double kelvin) =>
      _check(c.f3d_body_set_temperature(_live, body.raw, kelvin), body, kelvin);

  /// Joules into [body] over the next step, or out of it.
  void addHeat(NativeBody body, double joules) =>
      _check(c.f3d_body_add_heat(_live, body.raw, joules), body, joules);

  /// Kilograms of water onto [body] at the air's temperature, or off it.
  /// Water holds the body at its boiling point until it has boiled away.
  void addWater(NativeBody body, double kilograms) =>
      _check(c.f3d_body_add_water(_live, body.raw, kilograms), body, kilograms);

  /// Kilograms of water on [body].
  double waterOf(NativeBody body) {
    _check(c.f3d_body_get_water(_live, body.raw, _out), body);
    return _out[0];
  }

  /// Kilograms that can still burn.
  double fuelOf(NativeBody body) {
    _check(c.f3d_body_get_fuel(_live, body.raw, _out), body);
    return _out[0];
  }

  bool isBurning(NativeBody body) {
    _check(c.f3d_body_is_burning(_live, body.raw, _outInt), body);
    return _outInt[0] == 1;
  }

  /// Watts the fire gave off as hot gas over the last step.
  double heatReleaseOf(NativeBody body) {
    _check(c.f3d_body_get_heat_release(_live, body.raw, _out), body);
    return _out[0];
  }

  /// A refusal, said: a body that is not in the world, or a value the core
  /// would not take.
  void _check(int answer, NativeBody body, [Object? value]) {
    if (answer != 0) return;
    if (c.f3d_body_is_valid(_live, body.raw) == 0) {
      throw ArgumentError.value(body.raw, 'body', 'not in this world');
    }
    throw ArgumentError.value(value, 'value', 'not finite, or out of range');
  }
}
