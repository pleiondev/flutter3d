/// A physics world stepped by the C core — P9.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'core/core.dart' as c;

/// A body in a [NativeWorld]: its slot and the slot's generation, packed as
/// the C core packs them. Nought is never one.
extension type const NativeBody(int raw) {
  /// The arena slot.
  int get slot => raw % 0x100000000;

  /// How many times the slot had been used when this body took it. By
  /// division, not a shift: compiled to JavaScript, Dart's shifts and masks
  /// see 32 bits.
  int get generation => raw ~/ 0x100000000;
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

/// A liquid over ground in a [NativeWorld]: a stream, a pond, a waterfall
/// into it — or a pool of oil, a river of molten rock, as its
/// [NativeLiquidProperties] say. The shallow-water equations on a grid of
/// [nx] × [nz] cells [cell] metres square, the first cell's corner at
/// [origin].
final class NativeShallowLiquid {
  const NativeShallowLiquid._(this.id, this.nx, this.nz, this.cell, this.origin);

  /// Numbered from one; a number is never given out again.
  final int id;
  final int nx, nz;
  final double cell;
  final Vector3 origin;

  /// How many cells: the length of what [NativeWorld.readShallowSurface]
  /// and its depths return.
  int get cells => nx * nz;
}

/// What a liquid is: its density, kg/m³, its viscosity, Pa·s, and its
/// surface tension, N/m — [NativeWorld.setShallowProperties].
///
/// The density is what a body in it is held up by and pushes against. The
/// viscosity is what a body's drag answers to at its Reynolds number — a
/// ball sinks through honey at Stokes's speed and through water as Newton's
/// drag allows — what mixes the flow, and the ground's laminar hold where it
/// runs thin and slow, so honey and molten rock creep down a slope as a film. With
/// the tension, it is what spray and falling sheets break up by.
final class NativeLiquidProperties {
  const NativeLiquidProperties({
    required this.density,
    required this.viscosity,
    required this.tension,
  });

  /// Fresh water at room temperature: what a shallow liquid starts as.
  static const NativeLiquidProperties water = NativeLiquidProperties(
    density: 1000.0,
    viscosity: 1.0e-3,
    tension: 0.072,
  );

  /// The sea: salt makes it heavier and a little thicker. For a game set
  /// in the sea — a harbour, a reef a diver swims over.
  static const NativeLiquidProperties seawater = NativeLiquidProperties(
    density: 1025.0,
    viscosity: 1.08e-3,
    tension: 0.073,
  );

  /// Olive oil: lighter than water, eighty times as thick.
  static const NativeLiquidProperties oil = NativeLiquidProperties(
    density: 910.0,
    viscosity: 0.081,
    tension: 0.032,
  );

  /// Honey: ten thousand times as thick as water.
  static const NativeLiquidProperties honey = NativeLiquidProperties(
    density: 1420.0,
    viscosity: 10.0,
    tension: 0.05,
  );

  /// Molten basalt, a hundred pascal-seconds as it flows from a vent: a
  /// stone floats on it, and it creeps. For a game with a volcano whose
  /// flow runs downhill — the stone-age valley's.
  static const NativeLiquidProperties moltenBasalt = NativeLiquidProperties(
    density: 2700.0,
    viscosity: 100.0,
    tension: 0.35,
  );

  final double density, viscosity, tension;

  @override
  String toString() =>
      'NativeLiquidProperties($density kg/m³, $viscosity Pa·s, $tension N/m)';
}

/// Reals one piece of falling water takes in [NativeWorld.readSpray]: where
/// it is xyz, its velocity xyz, the water it carries, m³; then for a sheet
/// its width and its thickness — the flow it left with over its speed now,
/// so it thins as it falls — and for drops their diameter, twice; its kind,
/// [nativeSpraySheet] or [nativeSprayDrops]; and the face of the lip it
/// left, one past its index, nought for drops, so a sheet's pieces join into
/// one ribbon in the order they left.
const int nativeSprayFloats = c.sprayFloats;

/// Reals one fire takes in [NativeWorld.readFires]: where it is xyz, the
/// watts it gives off as hot gas, how far its flame reaches from there, m,
/// and the unit axis xyz the flame stands along.
const int nativeFireFloats = c.fireFloats;
const int nativeSpraySheet = c.spraySheet;
const int nativeSprayDrops = c.sprayDrops;

/// Reals one cloud of bubbles takes in [NativeWorld.readBubbles]: where it
/// is xyz, the bubbles' radius, and the air the cloud holds, m³.
const int nativeBubbleFloats = c.bubbleFloats;

/// What water is like at a point: its surface's height above the water's
/// origin, its depth, and the flow's velocity in x and z.
typedef NativeShallowSample = ({
  double surface,
  double depth,
  double flowX,
  double flowZ,
});

/// A multibody in a [NativeWorld]: a tree of bodies held by joints in
/// reduced coordinates. Numbered from one; a number is never given out
/// again.
extension type const NativeMultibody(int id) {}

/// A vehicle in a [NativeWorld]: a chassis on wheels that hang from it on
/// springs. Numbered from one; a number is never given out again.
extension type const NativeVehicle(int id) {}

/// A wheel as it is made: where its suspension is fixed to the chassis, in
/// the chassis's own frame; the suspension's length at rest and the
/// wheel's radius, m; the spring's stiffness, N/m, and damping, N s/m; and
/// the tyre's grip, the friction coefficient of the road under it.
typedef NativeWheel = ({
  Vector3 attach,
  double rest,
  double radius,
  double stiffness,
  double damping,
  double grip,
});

/// A wheel as the last step left it.
typedef NativeWheelState = ({
  /// Whether it stands on something.
  bool touching,

  /// The suspension's length now, m.
  double length,

  /// The steering angle, radians.
  double steer,

  /// How far it has turned about its axle, radians, and how fast, rad/s.
  double rotation,
  double spin,

  /// Its centre, and the normal of what it stands on.
  Vector3 centre,
  Vector3 normal,

  /// The spring's force, N.
  double force,

  /// How fast it slides sideways, m/s.
  double lateral,

  /// How far past its grip the tyre is asked to go: nought while it grips.
  double skid,
});

/// Several shapes the world holds as one, for bodies to be shaped as
/// ([NativeWorld.setCompound]). Numbered from one.
extension type const NativeCompound(int id) {}

/// One part of a compound: a shape, where it sits in the compound and how
/// it is turned there, and how far it is rounded.
final class NativeCompoundPart {
  /// A sphere, box, capsule, cylinder or cone part. Its [at] is where its
  /// centre goes: a cone's centre is its centre of mass.
  NativeCompoundPart(
    this.shape, {
    Vector3? at,
    Quaternion? turn,
    this.rounding = 0,
  }) : hull = null,
       at = at ?? Vector3.zero(),
       turn = turn ?? Quaternion.identity();

  /// A hull part. Its [at] is where the hull's own origin goes, which
  /// [NativeWorld.createHull] put at its centre of mass.
  NativeCompoundPart.hull(
    NativeHull this.hull, {
    Vector3? at,
    Quaternion? turn,
    this.rounding = 0,
  }) : shape = null,
       at = at ?? Vector3.zero(),
       turn = turn ?? Quaternion.identity();

  final NativeShape? shape;
  final NativeHull? hull;
  final Vector3 at;
  final Quaternion turn;
  final double rounding;
}

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
    this.flameTemperature = 0.0,
    this.flameConvection = 0.0,
    this.flameRadiant = 0.0,
    this.flameAbsorption = 0.0,
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
    final out = c.coreAlloc(c.F3dMaterialLayout.size);
    try {
      c.f3d_material_preset(kind, out);
      double at(int offset) => c.readF32(out + offset);
      return NativeMaterial(
        specificHeat: at(c.F3dMaterialLayout.specificHeat),
        emissivity: at(c.F3dMaterialLayout.emissivity),
        ignitionTemperature: at(c.F3dMaterialLayout.ignitionTemperature),
        heatOfCombustion: at(c.F3dMaterialLayout.heatOfCombustion),
        burnRate: at(c.F3dMaterialLayout.burnRate),
        fuelFraction: at(c.F3dMaterialLayout.fuelFraction),
        flameFeedback: at(c.F3dMaterialLayout.flameFeedback),
        conductivity: at(c.F3dMaterialLayout.conductivity),
        flameTemperature: at(c.F3dMaterialLayout.flameTemperature),
        flameConvection: at(c.F3dMaterialLayout.flameConvection),
        flameRadiant: at(c.F3dMaterialLayout.flameRadiant),
        flameAbsorption: at(c.F3dMaterialLayout.flameAbsorption),
      );
    } finally {
      c.coreFree(out);
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

  /// The gas of its fire's flame, K: above [ignitionTemperature] for a
  /// material that burns, and what heats a body standing in the flame.
  final double flameTemperature;

  /// W / (m² K): what the flame's gas passes to a surface standing in it.
  final double flameConvection;

  /// The share of the heat its fire gives off that leaves as radiation
  /// rather than in the gas, nought to one: about a third for wood, nearly
  /// half for a sooty rubber fire.
  final double flameRadiant;

  /// Per metre of flame seen through: its emissivity is 1 − e^(−κL).
  final double flameAbsorption;
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

  /// A joint held past its break and let go; the event names its two
  /// bodies.
  static const NativeEventKind jointBroken = NativeEventKind._(
    c.EventKind.jointBroken,
    'jointBroken',
  );

  static const List<NativeEventKind> _all = <NativeEventKind>[
    slept,
    woke,
    ignited,
    extinguished,
    burntOut,
    contactBegan,
    contactEnded,
    jointBroken,
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

  /// How far a step lifted it, m; nought when it did not step.
  double steppedUp,

  /// The velocity it was moved with, less the speed into what it met.
  Vector3 velocity,

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
final class NativeWorld {
  NativeWorld() : _world = c.f3d_world_create() {
    if (_world == 0) {
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
    _finalizer.attach(this, _world, detach: this);
  }

  /// Frees a world dropped without [dispose]. Its scratch goes with the
  /// process: the core's few bytes a world.
  static final Finalizer<int> _finalizer = Finalizer<int>(c.f3d_world_destroy);

  int _world;

  /// Scratch the getters write into: the world's own, freed with it.
  final c.F32s _out = c.F32s.alloc(4);
  final c.F64s _outDouble = c.F64s.alloc(3);
  final c.I32s _outInt = c.I32s.alloc(1);

  int get _live {
    if (_world == 0) throw StateError('this world was disposed');
    return _world;
  }

  /// Frees the world and everything in it. Calling it again does nothing.
  void dispose() {
    if (_world == 0) return;
    _finalizer.detach(this);
    c.f3d_world_destroy(_world);
    _out.free();
    _outDouble.free();
    _outInt.free();
    _world = 0;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _world == 0;

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
    final buffer = c.F32s.alloc(velocities.isEmpty ? 1 : velocities.length);
    try {
      buffer.setAll(velocities);
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
      buffer.free();
    }
  }

  /// Takes the wind grid away, leaving the uniform wind.
  void clearWindGrid() =>
      c.f3d_world_set_wind_grid(_live, 0, 0, 0, 1, 0, 0, 0, 0);

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

  /// Every burning body, or burning part of a compound, eight floats apiece:
  /// its position, the watts it gives off as hot gas — what a smoke grid
  /// takes its sources from — how far its flame reaches from that position,
  /// m, by Heskestad's length over a base as wide as what burns, and the
  /// unit axis the flame stands along, up and leaning with the wind by the
  /// speed of its own buoyancy: what a renderer draws the flame along.
  ({Float32List fires, List<NativeBody> bodies}) readFires() {
    final read = _readPer(bodyCount, nativeFireFloats, c.f3d_world_read_fires);
    return (fires: read.transforms, bodies: read.bodies);
  }

  ({Float32List transforms, List<NativeBody> bodies}) _readPer(
    int count,
    int floats,
    int Function(int, c.F32s, c.U64s, int) read,
  ) {
    if (count == 0) {
      return (transforms: Float32List(0), bodies: const <NativeBody>[]);
    }
    final values = c.F32s.alloc(count * floats);
    final handles = c.U64s.alloc(count);
    try {
      final written = read(_live, values, handles, count);
      return (
        transforms: values.copy(written * floats),
        bodies: <NativeBody>[
          for (var i = 0; i < written; i++) NativeBody(handles[i]),
        ],
      );
    } finally {
      values.free();
      handles.free();
    }
  }

  /// The events the steps raised since the last call, oldest first.
  List<NativeEvent> readEvents() {
    const batch = 256;
    final bodies = c.U64s.alloc(batch);
    final others = c.U64s.alloc(batch);
    final kinds = c.U32s.alloc(batch);
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
      bodies.free();
      others.free();
      kinds.free();
    }
  }

  /// A convex hull of [points], built and kept by the world: moved so its
  /// centre of mass, taken as solid, is at the origin of the bodies shaped
  /// as it — [hullOffset] says by how much. Throws an [ArgumentError] for
  /// fewer than four points not all in a plane, more than 4096, or a point
  /// not finite.
  NativeHull createHull(List<Vector3> points) {
    final buffer = c.F32s.alloc(points.isEmpty ? 3 : points.length * 3);
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
      buffer.free();
    }
  }

  /// What was subtracted from every point [hull] was made from.
  Vector3 hullOffset(NativeHull hull) {
    if (c.f3d_world_get_hull_offset(_live, hull.id, _out) == 0) {
      throw ArgumentError.value(hull.id, 'hull', 'not in this world');
    }
    return _read3();
  }

  /// A compound of [parts], built and kept by the world: one solid of even
  /// density, moved so its centre of mass is at the origin of the bodies
  /// shaped as it — [compoundOffset] says by how much. Its contacts are its
  /// parts', joined into one manifold along the deepest one's normal.
  /// Throws an [ArgumentError] for no parts, more than sixty-four, a point
  /// or mesh part, or a size, place or turn the core refuses.
  NativeCompound createCompound(List<NativeCompoundPart> parts) {
    final n = parts.length;
    final kinds = c.U32s.alloc(n == 0 ? 1 : n);
    final hulls = c.U32s.alloc(n == 0 ? 1 : n);
    final reals = c.F32s.alloc((n == 0 ? 1 : n) * c.compoundPartFloats);
    try {
      for (var i = 0; i < n; i++) {
        final part = parts[i];
        final shape = part.shape;
        final r = i * c.compoundPartFloats;
        kinds[i] = shape?.kind ?? c.ShapeKind.hull;
        hulls[i] = part.hull?.id ?? 0;
        reals[r] = shape?.first ?? 0;
        reals[r + 1] = shape?.second ?? 0;
        reals[r + 2] = shape?.third ?? 0;
        reals[r + 3] = part.rounding;
        reals[r + 4] = part.at.x;
        reals[r + 5] = part.at.y;
        reals[r + 6] = part.at.z;
        reals[r + 7] = part.turn.x;
        reals[r + 8] = part.turn.y;
        reals[r + 9] = part.turn.z;
        reals[r + 10] = part.turn.w;
      }
      final id = c.f3d_world_create_compound(_live, kinds, hulls, reals, n);
      if (id == 0) {
        throw ArgumentError.value(
          n,
          'parts',
          'not one to ${c.compoundMostParts} parts the core takes',
        );
      }
      return NativeCompound(id);
    } finally {
      kinds.free();
      hulls.free();
      reals.free();
    }
  }

  /// What was subtracted from every part's place in [compound].
  Vector3 compoundOffset(NativeCompound compound) {
    if (c.f3d_world_get_compound_offset(_live, compound.id, _out) == 0) {
      throw ArgumentError.value(compound.id, 'compound', 'not in this world');
    }
    return _read3();
  }

  /// How many parts [compound] has.
  int compoundPartCount(NativeCompound compound) =>
      c.f3d_world_compound_part_count(_live, compound.id);

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
    final v = c.F32s.alloc(vertices.isEmpty ? 3 : vertices.length * 3);
    final t = c.U32s.alloc(indices.isEmpty ? 3 : indices.length);
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
      v.free();
      t.free();
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

  /// Limits on a hinge's angle or a ball joint's twist about its axis,
  /// radians, or a slider's travel, m; null takes them off.
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

  /// A ball joint's swing held within [angle] radians of its axis, above
  /// nought and at most π — a shoulder, a hip, a neck; null takes it off.
  void setJointCone(NativeJoint joint, double? angle) => _checkJoint(
    c.f3d_joint_set_cone(_live, joint.raw, angle == null ? 0 : 1, angle ?? 0.0),
    joint,
  );

  /// A ball joint's friction: its bodies' turn against each other
  /// resisted with at most [torque], N m — what lets a ragdoll come to
  /// rest; null takes it off. A hinge or slider has it as a motor of speed
  /// nought.
  void setJointFriction(NativeJoint joint, double? torque) => _checkJoint(
    c.f3d_joint_set_friction(
      _live,
      joint.raw,
      torque == null ? 0 : 1,
      torque ?? 0.0,
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

  /// A hinge's angle from where it started, a ball joint's twist, a
  /// slider's travel, a distance joint's length; nought for the others.
  double jointValue(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_value(_live, joint.raw, _out), joint);
    return _out[0];
  }

  /// A ball joint's swing: the angle between its bodies' axes, radians;
  /// nought for the others.
  double jointSwing(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_swing(_live, joint.raw, _out), joint);
    return _out[0];
  }

  /// The force [joint] held its second body with over the last substep, N.
  Vector3 jointForce(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_force(_live, joint.raw, _out), joint);
    return _read3();
  }

  /// The torque [joint]'s locked turns held its second body with over the
  /// last substep, N m.
  Vector3 jointTorque(NativeJoint joint) {
    _checkJoint(c.f3d_joint_get_torque(_live, joint.raw, _out), joint);
    return _read3();
  }

  /// Lets [joint] break: at the end of a step in which it held its second
  /// body with more than [force] newtons ([jointForce]) or more than
  /// [torque] newton metres ([jointTorque]), it is taken out and a
  /// [NativeEventKind.jointBroken] names its bodies. Nought is never, and
  /// is what a joint starts with.
  void setJointBreak(
    NativeJoint joint, {
    double force = 0,
    double torque = 0,
  }) => _checkJoint(
    c.f3d_joint_set_break(_live, joint.raw, force, torque),
    joint,
  );

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
      final out = c.U64s.alloc(capacity);
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
        out.free();
      }
    }
  }

  NativeHit _hitAt(int body, c.F32s h) => (
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
    final body = c.U64s.alloc(1);
    final hit = c.F32s.alloc(c.hitFloats);
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
      body.free();
      hit.free();
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
      final bodies = c.U64s.alloc(capacity);
      final hits = c.F32s.alloc(capacity * c.hitFloats);
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
              _hitAt(bodies[i], c.F32s(hits + i * c.hitFloats * 4)),
          ];
        }
        capacity = count;
      } finally {
        bodies.free();
        hits.free();
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
      final out = c.U64s.alloc(capacity);
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
        out.free();
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
    final body = c.U64s.alloc(1);
    final hit = c.F32s.alloc(c.hitFloats);
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
      body.free();
      hit.free();
    }
  }

  /// Moves an upright [shape] — a character: a box or a capsule — from
  /// [position] by [move], sliding along what it meets:
  /// ground whose normal's height is at least [maxSlopeCos] — the cosine of
  /// the steepest slope it stands on, forty-five degrees by default — it
  /// stands on, steeper it slides along as a wall, a step up to
  /// [stepHeight] it climbs, and walking down it keeps to the ground.
  /// Kinematic: nothing pushes it, and it moves nothing.
  ///
  /// A body on a layer in [fromAbove] is a floor from above and nothing else:
  /// met only standing on it, passed through rising into it or walking into
  /// its side — a platform jumped up through and landed on.
  ///
  /// **A cosine, not an angle.** Turning an angle into one here would ask
  /// the platform's library, whose last bit differs from machine to
  /// machine, and a character's step must not.
  NativeCharacterMove moveCharacter({
    required NativeShape shape,
    required Vector3 position,
    required Vector3 move,
    Vector3? velocity,
    double maxSlopeCos = 0.7071067811865476,
    double stepHeight = 0.35,
    bool mayStep = true,
    int mask = 0xffffffff,
    int fromAbove = 0,
    NativeBody? ignore,
  }) {
    final p = c.F32s.alloc(3);
    final v = c.F32s.alloc(3);
    final lifted = c.F32s.alloc(1);
    final ground = c.F32s.alloc(3);
    final body = c.U64s.alloc(1);
    try {
      p[0] = position.x;
      p[1] = position.y;
      p[2] = position.z;
      v[0] = velocity?.x ?? 0.0;
      v[1] = velocity?.y ?? 0.0;
      v[2] = velocity?.z ?? 0.0;
      final flags = c.f3d_world_move_character(
        _live,
        shape.kind,
        shape.first,
        shape.second,
        shape.third,
        p,
        move.x,
        move.y,
        move.z,
        v,
        maxSlopeCos,
        stepHeight,
        mask,
        fromAbove,
        mayStep ? c.CharacterFlags.mayStep : 0,
        ignore?.raw ?? 0,
        body,
        ground,
        lifted,
      );
      return (
        position: Vector3(p[0], p[1], p[2]),
        grounded: flags & c.CharacterFlags.grounded != 0,
        hitWall: flags & c.CharacterFlags.wall != 0,
        hitCeiling: flags & c.CharacterFlags.ceiling != 0,
        stepped: flags & c.CharacterFlags.stepped != 0,
        steppedUp: lifted[0],
        velocity: Vector3(v[0], v[1], v[2]),
        groundNormal: Vector3(ground[0], ground[1], ground[2]),
        ground: body[0] == 0 ? null : NativeBody(body[0]),
      );
    } finally {
      p.free();
      v.free();
      lifted.free();
      ground.free();
      body.free();
    }
  }

  /// Every contact point the last step found, in order of the pair's slots.
  List<NativeContact> readContacts() {
    final count = c.f3d_world_contact_count(_live);
    if (count == 0) return const <NativeContact>[];
    final values = c.F32s.alloc(count * c.contactFloats);
    final pairs = c.U64s.alloc(count * 2);
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
      values.free();
      pairs.free();
    }
  }

  /// Events dropped because 65 536 were waiting unread.
  int get eventsDropped => c.f3d_world_events_dropped(_live);

  // ------------------------------------------------------------ snapshots

  /// The world's whole state. A world [restore]d from it steps to the same
  /// bits this one does.
  Uint8List snapshot() {
    final size = c.f3d_world_snapshot_size(_live);
    final buffer = c.U8s.alloc(size);
    try {
      final written = c.f3d_world_snapshot_write(_live, buffer, size);
      if (written != size) {
        throw StateError('the physics core wrote $written of $size bytes');
      }
      return buffer.copy(size);
    } finally {
      buffer.free();
    }
  }

  /// Puts the world back as [snapshot] says. Throws an [ArgumentError] for
  /// bytes that are not a snapshot from this build of the core, and leaves
  /// the world as it was.
  void restore(Uint8List snapshot) {
    final buffer = c.U8s.alloc(snapshot.isEmpty ? 1 : snapshot.length);
    try {
      buffer.setAll(snapshot);
      if (c.f3d_world_restore(_live, buffer, snapshot.length) == 0) {
        throw ArgumentError.value(
          snapshot.length,
          'snapshot',
          'not a snapshot from this build of the physics core',
        );
      }
    } finally {
      buffer.free();
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
    final out = c.F32s.alloc(6);
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
      out.free();
    }
  }

  /// Rounds [body]'s shape out by [radius]: the shape grown by a ball, so a
  /// box gets rounded edges and corners.
  void setRounding(NativeBody body, double radius) =>
      _check(c.f3d_body_set_rounding(_live, body.raw, radius), body, radius);

  /// Shapes [body] as [hull].
  void setHull(NativeBody body, NativeHull hull) =>
      _check(c.f3d_body_set_hull(_live, body.raw, hull.id), body, hull.id);

  /// A liquid over ground — water, until [setShallowProperties] says
  /// otherwise: [nx] × [nz] cells [cell] metres square, the first cell's
  /// corner at [origin], and [ground] the height of the ground at each
  /// cell's centre above the origin, x fastest. It starts dry.
  ///
  /// In each column the liquid moves as one, its depth carried across the
  /// columns' faces, so none is made or lost but by springs, open edges and
  /// what is taken off; it runs down the slope of its surface and is held
  /// back by the bed — its roughness where the flow is turbulent, its
  /// viscosity where it creeps. Off a drop steeper than forty-five degrees it
  /// leaves as spray, falls and lands below — a waterfall. A dynamic body in
  /// it pushes the liquid aside, so a stone dropped in makes waves; it is
  /// held up by what it displaces, dragged as its Reynolds number says,
  /// heavier to speed up by the liquid it carries, and pushes the flow back
  /// as hard, so it leaves a wake.
  NativeShallowLiquid createShallowLiquid({
    required int nx,
    required int nz,
    required double cell,
    required Vector3 origin,
    required List<double> ground,
  }) {
    if (ground.length != nx * nz) {
      throw ArgumentError.value(
        ground.length,
        'ground',
        'not nx × nz = ${nx * nz} heights',
      );
    }
    final g = c.F32s.alloc(ground.isEmpty ? 1 : ground.length);
    try {
      g.setAll(ground);
      final id = c.f3d_shallow_create(
        _live,
        nx,
        nz,
        cell,
        origin.x,
        origin.y,
        origin.z,
        g,
      );
      if (id == 0) {
        throw ArgumentError(
          'water of $nx × $nz cells of $cell m: a size or '
          'a cell out of range, or a height not finite',
        );
      }
      return NativeShallowLiquid._(id, nx, nz, cell, origin.clone());
    } finally {
      g.free();
    }
  }

  bool removeShallowLiquid(NativeShallowLiquid water) =>
      c.f3d_shallow_destroy(_live, water.id) == 1;

  bool containsShallowLiquid(NativeShallowLiquid water) =>
      c.f3d_shallow_is_valid(_live, water.id) == 1;

  /// The ground again, dug or built up, as [createShallowLiquid] took it.
  void setShallowGround(NativeShallowLiquid water, List<double> ground) {
    if (ground.length != water.cells) {
      throw ArgumentError.value(ground.length, 'ground', 'not ${water.cells}');
    }
    final g = c.F32s.alloc(ground.length);
    try {
      g.setAll(ground);
      if (c.f3d_shallow_set_ground(_live, water.id, g) == 0) {
        throw ArgumentError('a height not finite');
      }
    } finally {
      g.free();
    }
  }

  /// Every cell between ([x0], [z0]) and ([x1], [z1]) filled, or drained, to
  /// [level] above the water's origin: a pond put in place.
  void fillShallowLiquid(
    NativeShallowLiquid water, {
    required double x0,
    required double z0,
    required double x1,
    required double z1,
    required double level,
  }) {
    if (c.f3d_shallow_fill(_live, water.id, x0, z0, x1, z1, level) == 0) {
      throw ArgumentError('a fill not finite');
    }
  }

  /// [volume] m³ poured in at ([x], [z]) over a disc of [radius], or taken
  /// out where it is negative.
  void pourShallowLiquid(
    NativeShallowLiquid water,
    double x,
    double z, {
    double radius = 0.0,
    required double volume,
  }) {
    if (c.f3d_shallow_pour(_live, water.id, x, z, radius, volume) == 0) {
      throw ArgumentError('a pour not finite');
    }
  }

  /// Spring [index]: [rate] m³/s welling up at ([x], [z]) over a disc of
  /// [radius]; a rate of nought stops it. At most [c.shallowMostSources].
  void setShallowSource(
    NativeShallowLiquid water,
    int index, {
    required double x,
    required double z,
    double radius = 0.0,
    required double rate,
  }) {
    if (c.f3d_shallow_set_source(_live, water.id, index, x, z, radius, rate) ==
        0) {
      throw ArgumentError(
        'spring $index: past ${c.shallowMostSources}, or a '
        'radius or rate below nought',
      );
    }
  }

  /// Manning's roughness of the bed, about 0.03 for a stream's and 0.012 for
  /// smooth concrete; and whether water reaching the grid's edge runs off.
  void setShallowBed(
    NativeShallowLiquid water, {
    double roughness = 0.03,
    bool openEdges = false,
  }) {
    if (c.f3d_shallow_set_bed(_live, water.id, roughness, openEdges ? 1 : 0) ==
        0) {
      throw ArgumentError.value(roughness, 'roughness', 'below nought');
    }
  }

  /// What [water] is — water, as it starts, or honey, oil, molten rock: what holds
  /// a body up and drags it, how the flow mixes and creeps over the ground,
  /// and how its spray breaks up.
  void setShallowProperties(NativeShallowLiquid water, NativeLiquidProperties fluid) {
    if (c.f3d_shallow_set_fluid(
          _live,
          water.id,
          fluid.density,
          fluid.viscosity,
          fluid.tension,
        ) ==
        0) {
      throw ArgumentError.value(fluid, 'fluid', 'not a fluid');
    }
  }

  /// The water at ([x], [z]), or null outside its grid.
  NativeShallowSample? sampleShallow(NativeShallowLiquid water, double x, double z) {
    final out = c.F32s.alloc(4);
    try {
      if (c.f3d_shallow_sample(_live, water.id, x, z, out) == 0) return null;
      return (surface: out[0], depth: out[1], flowX: out[2], flowZ: out[3]);
    } finally {
      out.free();
    }
  }

  /// Every cell's surface height above the water's origin and its depth,
  /// x fastest; where it is dry the surface is the ground.
  ({Float32List surface, Float32List depth}) readShallowSurface(
    NativeShallowLiquid water,
  ) {
    final n = water.cells;
    final surface = c.F32s.alloc(n);
    final depth = c.F32s.alloc(n);
    try {
      c.f3d_shallow_read(_live, water.id, surface, depth);
      return (surface: surface.copy(n), depth: depth.copy(n));
    } finally {
      surface.free();
      depth.free();
    }
  }

  /// Every cell's flow, its velocity x and z: two a cell.
  Float32List readShallowFlow(NativeShallowLiquid water) {
    final n = water.cells * 2;
    final flow = c.F32s.alloc(n);
    try {
      c.f3d_shallow_read_flow(_live, water.id, flow);
      return flow.copy(n);
    } finally {
      flow.free();
    }
  }

  /// The water it holds, m³, in its cells and in the air as spray, and what
  /// has run off its open edges.
  ({double held, double lost}) shallowVolume(NativeShallowLiquid water) {
    final out = c.F32s.alloc(2);
    try {
      c.f3d_shallow_volume(_live, water.id, out, out + 4);
      return (held: out[0], lost: out[1]);
    } finally {
      out.free();
    }
  }

  /// The spray in flight, [nativeSprayFloats] reals a drop — where it is, its
  /// velocity, and the water it carries — up to [capacity] drops; of every
  /// water in the world, or only of [of].
  Float32List readSpray({int capacity = c.shallowMostSpray, NativeShallowLiquid? of}) =>
      _readOfWater(capacity, c.sprayFloats, c.f3d_world_read_spray, of);

  /// Up to [capacity] pieces of [floats] reals each read by [read], and of
  /// them, when [of] is given, only the ones in that water.
  Float32List _readOfWater(
    int capacity,
    int floats,
    int Function(int, int, int, int) read,
    NativeShallowLiquid? of,
  ) {
    final out = c.F32s.alloc(capacity * floats);
    final waters = of == null ? null : c.U32s.alloc(capacity);
    try {
      final count = read(_live, out, waters ?? 0, capacity);
      final all = out.copy(count * floats);
      if (waters == null) return all;
      final kept = <int>[
        for (var k = 0; k < count; k++)
          if (waters[k] == of!.id) k,
      ];
      return Float32List(kept.length * floats)..setAll(0, <double>[
        for (final k in kept) ...all.sublist(k * floats, (k + 1) * floats),
      ]);
    } finally {
      out.free();
      waters?.free();
    }
  }

  /// The bubbles in the water, [nativeBubbleFloats] reals a cloud, up to
  /// [capacity] clouds: what a sheet plunging into water dragged down,
  /// rising and carried by the flow until they reach the surface; in every
  /// water in the world, or only in [of].
  Float32List readBubbles({
    int capacity = c.shallowMostBubbles,
    NativeShallowLiquid? of,
  }) => _readOfWater(capacity, c.bubbleFloats, c.f3d_world_read_bubbles, of);

  /// A multibody rooted at [root]: a tree of bodies held by joints in
  /// reduced coordinates, each link placed by its parent and its joint's
  /// angle or travel and nothing else, so no joint comes apart however long
  /// the chain or heavy its end. A fixed root is a fixed base; a dynamic one
  /// floats. The links stay ordinary bodies that collide and sleep; a link
  /// does not collide with its parent. The root is link nought.
  NativeMultibody createMultibody(NativeBody root) {
    final id = c.f3d_multibody_create(_live, root.raw);
    if (id == 0) {
      throw ArgumentError.value(
        root.raw,
        'root',
        'not in this world, or a link already',
      );
    }
    return NativeMultibody(id);
  }

  /// Adds [body] as a link under link [parent], on a joint of [type] —
  /// fixed, revolute, prismatic or spherical — at [anchor] and along
  /// [axis], taken where the bodies stand now, which is the joint's nought.
  /// Returns the link's index.
  int addLink(
    NativeMultibody multibody,
    NativeBody body, {
    int parent = 0,
    required NativeJointType type,
    required Vector3 anchor,
    Vector3? axis,
  }) {
    final a = axis ?? Vector3(0.0, 1.0, 0.0);
    final index = c.f3d_multibody_add_link(
      _live,
      multibody.id,
      parent,
      body.raw,
      type.code,
      anchor.x,
      anchor.y,
      anchor.z,
      a.x,
      a.y,
      a.z,
    );
    if (index < 0) {
      throw ArgumentError(
        'link ${body.raw} under $parent: a body not dynamic or a link '
        'already, a ${type.name} joint a multibody does not take, an axis of '
        'nought, or ${c.multibodyMostLinks} links or '
        '${c.multibodyMostDofs} degrees of freedom already',
      );
    }
    return index;
  }

  /// Takes [multibody] out; its bodies stay.
  bool removeMultibody(NativeMultibody multibody) =>
      c.f3d_multibody_destroy(_live, multibody.id) == 1;

  /// Whether [multibody] is still in this world: a link taken out takes it
  /// out too.
  bool containsMultibody(NativeMultibody multibody) =>
      c.f3d_multibody_is_valid(_live, multibody.id) == 1;

  int linkCount(NativeMultibody multibody) =>
      c.f3d_multibody_link_count(_live, multibody.id);

  /// The root's six degrees of freedom when it floats, and its joints'.
  int dofCount(NativeMultibody multibody) =>
      c.f3d_multibody_dof_count(_live, multibody.id);

  /// Limits on a revolute link's angle, radians, or a prismatic link's
  /// travel, m; null for both takes them off.
  void setLinkLimits(
    NativeMultibody multibody,
    int link, {
    double? lower,
    double? upper,
  }) {
    final on = lower != null && upper != null;
    if (c.f3d_multibody_set_limits(
          _live,
          multibody.id,
          link,
          on ? 1 : 0,
          lower ?? 0.0,
          upper ?? 0.0,
        ) ==
        0) {
      throw ArgumentError(
        'limits on link $link: not a revolute or '
        'prismatic link, or a lower above the upper',
      );
    }
  }

  /// A motor on a revolute or prismatic link, driving its speed towards
  /// [speed] with at most [force]; null [speed] takes it off.
  void setLinkMotor(
    NativeMultibody multibody,
    int link, {
    double? speed,
    double force = 0.0,
  }) {
    if (c.f3d_multibody_set_motor(
          _live,
          multibody.id,
          link,
          speed != null ? 1 : 0,
          speed ?? 0.0,
          force,
        ) ==
        0) {
      throw ArgumentError(
        'a motor on link $link: not a revolute or '
        'prismatic link, or a force below nought',
      );
    }
  }

  /// A revolute link's angle or a prismatic link's travel, and its speed,
  /// as the last step left them.
  ({double position, double speed}) linkJoint(
    NativeMultibody multibody,
    int link,
  ) {
    final out = c.F32s.alloc(8);
    try {
      if (c.f3d_multibody_read_joint(_live, multibody.id, link, out) == 0) {
        throw ArgumentError.value(link, 'link', 'not in this multibody');
      }
      return (position: out[0], speed: out[1]);
    } finally {
      out.free();
    }
  }

  /// A cone on a spherical link: its axis, the one given to [addLink],
  /// swings at most [swing] radians from where the parent holds it, and the
  /// link twists about it at most [twist] either way. Null [swing] takes it
  /// off. A shoulder in a ragdoll, a lamp on a ball joint that must not
  /// flop over.
  void setLinkCone(
    NativeMultibody multibody,
    int link, {
    double? swing,
    double twist = 3.141592653589793,
  }) {
    if (c.f3d_multibody_set_cone(
          _live,
          multibody.id,
          link,
          swing != null ? 1 : 0,
          swing ?? 0.0,
          twist,
        ) ==
        0) {
      throw ArgumentError(
        'a cone on link $link: not a spherical link, a '
        'swing outside (0, π] or a twist outside [0, π]',
      );
    }
  }

  /// A spherical link's turn in its parent's frame and its spin relative to
  /// the parent, as the last step left them.
  ({Quaternion turn, Vector3 spin}) linkTurn(
    NativeMultibody multibody,
    int link,
  ) {
    final out = c.F32s.alloc(8);
    try {
      if (c.f3d_multibody_read_joint(_live, multibody.id, link, out) == 0) {
        throw ArgumentError.value(link, 'link', 'not in this multibody');
      }
      return (
        turn: Quaternion(out[0], out[1], out[2], out[3]),
        spin: Vector3(out[4], out[5], out[6]),
      );
    } finally {
      out.free();
    }
  }

  /// A vehicle on [chassis], a dynamic body: [up] and [forward] are the
  /// chassis's own, square to each other. Its wheels hang along the down,
  /// steer about the up and roll along the forward. Each step, after the
  /// contacts and before the solver, every wheel that touches pushes the
  /// chassis up by its spring, along the road by its drive and brake, and
  /// across it to hold it from sliding, together no more than its grip
  /// times the spring allows; and pushes what it stands on back.
  NativeVehicle createVehicle(
    NativeBody chassis, {
    Vector3? up,
    Vector3? forward,
  }) {
    final u = up ?? Vector3(0.0, 1.0, 0.0);
    final f = forward ?? Vector3(0.0, 0.0, 1.0);
    final id = c.f3d_vehicle_create(
      _live,
      chassis.raw,
      u.x,
      u.y,
      u.z,
      f.x,
      f.y,
      f.z,
    );
    if (id == 0) {
      throw ArgumentError(
        'a chassis not in this world or not dynamic, or axes that are not '
        'square to each other',
      );
    }
    return NativeVehicle(id);
  }

  /// Takes [vehicle] out; its chassis stays.
  bool removeVehicle(NativeVehicle vehicle) =>
      c.f3d_vehicle_destroy(_live, vehicle.id) == 1;

  /// Whether [vehicle] and its chassis are still in this world.
  bool containsVehicle(NativeVehicle vehicle) =>
      c.f3d_vehicle_is_valid(_live, vehicle.id) == 1;

  /// Adds [wheel] to [vehicle] and returns its index, from nought.
  int addWheel(NativeVehicle vehicle, NativeWheel wheel) {
    final w = c.F32s.alloc(c.wheelFloats);
    try {
      w[0] = wheel.attach.x;
      w[1] = wheel.attach.y;
      w[2] = wheel.attach.z;
      w[3] = wheel.rest;
      w[4] = wheel.radius;
      w[5] = wheel.stiffness;
      w[6] = wheel.damping;
      w[7] = wheel.grip;
      final index = c.f3d_vehicle_add_wheel(_live, vehicle.id, w);
      if (index < 0) {
        throw ArgumentError(
          'a vehicle not in this world, one with ${c.vehicleMostWheels} '
          'wheels already, or a wheel the core refuses',
        );
      }
      return index;
    } finally {
      w.free();
    }
  }

  /// What the driver asks of [wheel]: its [steer], radians to the left; the
  /// force its [drive] pushes along the road with, N, negative backwards;
  /// and the force its [brake] holds with, N. Held until set again.
  void setWheel(
    NativeVehicle vehicle,
    int wheel, {
    double steer = 0.0,
    double drive = 0.0,
    double brake = 0.0,
  }) {
    if (c.f3d_vehicle_set_wheel(
          _live,
          vehicle.id,
          wheel,
          steer,
          drive,
          brake,
        ) ==
        0) {
      throw ArgumentError(
        'wheel $wheel of vehicle ${vehicle.id}: not there, or a brake below '
        'nought',
      );
    }
  }

  /// How many wheels [vehicle] has.
  int wheelCount(NativeVehicle vehicle) =>
      c.f3d_vehicle_wheel_count(_live, vehicle.id);

  /// Every wheel of [vehicle], as the last step left them.
  List<NativeWheelState> wheelsOf(NativeVehicle vehicle) {
    final out = c.F32s.alloc(c.vehicleMostWheels * c.wheelStateFloats);
    try {
      final n = c.f3d_vehicle_read_wheels(
        _live,
        vehicle.id,
        out,
        c.vehicleMostWheels,
      );
      return <NativeWheelState>[
        for (var i = 0; i < n; i++)
          (
            touching: out[i * c.wheelStateFloats] != 0.0,
            length: out[i * c.wheelStateFloats + 1],
            steer: out[i * c.wheelStateFloats + 2],
            rotation: out[i * c.wheelStateFloats + 3],
            spin: out[i * c.wheelStateFloats + 4],
            centre: Vector3(
              out[i * c.wheelStateFloats + 5],
              out[i * c.wheelStateFloats + 6],
              out[i * c.wheelStateFloats + 7],
            ),
            normal: Vector3(
              out[i * c.wheelStateFloats + 8],
              out[i * c.wheelStateFloats + 9],
              out[i * c.wheelStateFloats + 10],
            ),
            force: out[i * c.wheelStateFloats + 11],
            lateral: out[i * c.wheelStateFloats + 12],
            skid: out[i * c.wheelStateFloats + 13],
          ),
      ];
    } finally {
      out.free();
    }
  }

  /// Shapes [body] as [compound].
  void setCompound(NativeBody body, NativeCompound compound) => _check(
    c.f3d_body_set_compound(_live, body.raw, compound.id),
    body,
    compound.id,
  );

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
    final m = c.coreAlloc(c.F3dMaterialLayout.size);
    try {
      c.writeF32(m + c.F3dMaterialLayout.specificHeat, material.specificHeat);
      c.writeF32(m + c.F3dMaterialLayout.emissivity, material.emissivity);
      c.writeF32(
        m + c.F3dMaterialLayout.ignitionTemperature,
        material.ignitionTemperature,
      );
      c.writeF32(
        m + c.F3dMaterialLayout.heatOfCombustion,
        material.heatOfCombustion,
      );
      c.writeF32(m + c.F3dMaterialLayout.burnRate, material.burnRate);
      c.writeF32(m + c.F3dMaterialLayout.fuelFraction, material.fuelFraction);
      c.writeF32(m + c.F3dMaterialLayout.flameFeedback, material.flameFeedback);
      c.writeF32(m + c.F3dMaterialLayout.conductivity, material.conductivity);
      c.writeF32(
        m + c.F3dMaterialLayout.flameTemperature,
        material.flameTemperature,
      );
      c.writeF32(
        m + c.F3dMaterialLayout.flameConvection,
        material.flameConvection,
      );
      c.writeF32(m + c.F3dMaterialLayout.flameRadiant, material.flameRadiant);
      c.writeF32(
        m + c.F3dMaterialLayout.flameAbsorption,
        material.flameAbsorption,
      );
      _check(c.f3d_body_set_material(_live, body.raw, m), body, material);
    } finally {
      c.coreFree(m);
    }
  }

  /// Kelvin: its mean, what the heat in it says.
  double temperatureOf(NativeBody body) {
    _check(c.f3d_body_get_temperature(_live, body.raw, _out), body);
    return _out[0];
  }

  /// Kelvin: its surface's over the last step. Heat reaches into a body
  /// from its surface over a layer that thickens with the square root of
  /// time, so a thick body's surface runs ahead of its mean — a log's
  /// catches in a flame while its middle is cold — and a small or
  /// conductive body's is its mean. The surface is what catches fire, goes
  /// out, radiates and meets other bodies.
  double surfaceTemperatureOf(NativeBody body) {
    _check(c.f3d_body_get_surface_temperature(_live, body.raw, _out), body);
    return _out[0];
  }

  /// Sets it, the same all through; the next step decides whether that
  /// lights a fire or puts one out.
  void setTemperature(NativeBody body, double kelvin) =>
      _check(c.f3d_body_set_temperature(_live, body.raw, kelvin), body, kelvin);

  /// Joules into [body] over the next step, or out of it.
  void addHeat(NativeBody body, double joules) =>
      _check(c.f3d_body_add_heat(_live, body.raw, joules), body, joules);

  /// Joules into [body] where [point] is: into the part of a compound
  /// whose centre is nearest it, into any other body whole. A torch held to
  /// one end of a beam.
  void addHeatAt(NativeBody body, Vector3 point, double joules) => _check(
    c.f3d_body_add_heat_at(_live, body.raw, point.x, point.y, point.z, joules),
    body,
    joules,
  );

  /// A compound's part [part]'s temperature, K. Each part of a compound
  /// has its own heat, water, fuel and fire, so a post burns upwards a part
  /// at a time; [temperatureOf] is theirs weighted by what each holds. Part
  /// nought of any other body is the body.
  double partTemperatureOf(NativeBody body, int part) {
    if (c.f3d_body_get_part_temperature(_live, body.raw, part, _out) == 0) {
      throw ArgumentError.value(part, 'part', 'not a part of $body');
    }
    return _out[0];
  }

  void setPartTemperature(NativeBody body, int part, double kelvin) {
    if (c.f3d_body_set_part_temperature(_live, body.raw, part, kelvin) == 0) {
      throw ArgumentError('part $part of $body at $kelvin K');
    }
  }

  /// Whether a compound's part [part] is alight; part nought of any other
  /// body is the body.
  bool isPartBurning(NativeBody body, int part) {
    if (c.f3d_body_is_part_burning(_live, body.raw, part, _outInt) == 0) {
      throw ArgumentError.value(part, 'part', 'not a part of $body');
    }
    return _outInt[0] == 1;
  }

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
