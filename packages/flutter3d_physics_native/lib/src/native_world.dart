/// A physics world stepped by the C core — P9.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show WorldPosition;
import 'package:flutter3d_matter/flutter3d_matter.dart';
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
/// A class of constants rather than an enum: a value added to an enum
/// breaks every switch written against it.
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

  /// Moves at the velocity and spin it is given and nothing else — no
  /// gravity, force or contact moves it — and pushes what it meets, waking
  /// what sleeps there: a game object the world follows, a wheel through a
  /// ford, a door, a lift. [NativeWorld.moveKinematic] sends it to a pose.
  static const NativeBodyType kinematic = NativeBodyType._(
    c.BodyType.kinematic,
    'kinematic',
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
  const NativeShallowLiquid._(
    this.id,
    this.nx,
    this.nz,
    this.cell,
    this.origin,
  );

  /// Numbered from one; a number is never given out again.
  final int id;
  final int nx, nz;

  /// A cell's side, in metres.
  final double cell;
  final Vector3 origin;

  /// How many cells: the length of what [NativeWorld.readShallowSurface]
  /// and its depths return.
  int get cells => nx * nz;
}

/// One of the four edges of a water's grid: [west] at its origin's x,
/// [east] at its far x, [south] at its origin's z, [north] at its far z.
final class GridSide {
  const GridSide._(this.code, this.name);

  static const GridSide west = GridSide._(0, 'west');
  static const GridSide east = GridSide._(1, 'east');
  static const GridSide south = GridSide._(2, 'south');
  static const GridSide north = GridSide._(3, 'north');

  final int code;
  final String name;

  @override
  String toString() => 'GridSide.$name';
}

/// What an edge of a water's grid is — [NativeWorld.setShallowEdge].
final class NativeEdgeFlow {
  const NativeEdgeFlow._(this.kind, this.value);

  /// Nothing crosses it: a bank, a dam, the side of a tank.
  static const NativeEdgeFlow wall = NativeEdgeFlow._(c.EdgeKind.wall, 0);

  /// What reaches it runs off, and nothing comes in: a stream leaving the
  /// map.
  static const NativeEdgeFlow free = NativeEdgeFlow._(c.EdgeKind.open, 0);

  /// [discharge] m³/s let in over the whole edge — taken out where it is
  /// negative — shared over its wet cells by their conveyance h^(5/3): a
  /// river entering the map.
  const NativeEdgeFlow.inflow({required double discharge})
    : this._(c.EdgeKind.flow, discharge);

  /// Water outside the edge standing at [height] above the water's origin,
  /// flowing in or out as the surface inside is below or above it: the
  /// sea, a lake the map opens onto.
  const NativeEdgeFlow.level(double height) : this._(c.EdgeKind.level, height);

  final int kind;

  /// The [kind]'s number: an inflow's discharge in cubic metres per second,
  /// a level's height in metres, nought for a wall or a free edge.
  final double value;
}

/// A way water leaves a pool — [NativeWorld.setShallowOutlet].
final class NativeOutlet {
  const NativeOutlet._(
    this.x,
    this.z,
    this.crest,
    this.width,
    this.coefficient, {
    this.drain = false,
  });

  /// A sharp-crested weir [width] m long at ([x], [z]), its crest [crest]
  /// above the water's origin: where the pool stands a head H over the
  /// crest it lets out Q = ⅔·C_d·√(2g)·width·H^1.5 (Poleni), C_d Rehbock's
  /// 0.611 + 0.075·H/P with P the crest's height over the bed, or
  /// [coefficient] where one is given; never more than would bring the pool
  /// below its crest.
  const NativeOutlet.weir({
    required double x,
    required double z,
    required double crest,
    required double width,
    double coefficient = 0,
  }) : this._(x, z, crest, width, coefficient);

  /// A drain [area] m² at ([x], [z]), its invert [invert] above the
  /// water's origin — a culvert's mouth, a grate, a sluice: where the pool
  /// stands a head H over the invert it lets out Q = C_d·A·√(2gH)
  /// (Torricelli), C_d a sharp-edged orifice's 0.61 or [coefficient] where
  /// one is given; never more than would bring the pool below its invert.
  const NativeOutlet.drain({
    required double x,
    required double z,
    required double invert,
    required double area,
    double coefficient = 0,
  }) : this._(x, z, invert, area, coefficient, drain: true);

  /// Where it is; a weir's crest, or a drain's invert; a weir's width, m,
  /// or a drain's area, m²; and its coefficient, nought for the one given.
  final double x, z, crest, width, coefficient;

  /// Whether it is a drain rather than a weir.
  final bool drain;
}

/// What a water's last step was — [NativeWorld.shallowInfoOf].
typedef NativeShallowInfo = ({
  /// The substeps the step was cut into.
  int substeps,

  /// Steps since the water was made that wanted more substeps than
  /// [c.shallowMostSubsteps], and so held the flow to what that allows.
  int overruns,

  /// Whether it rests, unstepped until something stirs it.
  bool resting,

  /// The most energy any cell held at the step's end, J/m².
  double energy,
});

/// What a liquid is: its density, kg/m³, its viscosity, Pa·s, and its
/// surface tension, N/m — [NativeWorld.setShallowProperties].
///
/// The density is what a body in it is held up by and pushes against. The
/// viscosity is what a body's drag answers to at its Reynolds number — a
/// ball sinks through honey at Stokes's speed and through water as Newton's
/// drag allows — what mixes the flow, and the ground's laminar hold where it
/// runs thin and slow, so honey and molten rock creep down a slope as a film. With
/// the tension, it is what spray and falling sheets break up by.
///
/// **A view of a material in the catalogue** ([NativeLiquidProperties.of]):
/// the presets are the built-ins' entries ([Materials]), and a plugin's
/// liquid reaches the core the same way — its numbers are passed when the
/// water is given them, so the core needs no table of its own beyond the
/// built-ins' header.
final class NativeLiquidProperties {
  const NativeLiquidProperties({
    required this.density,
    required this.viscosity,
    required this.tension,
  });

  /// [material]'s density, viscosity and surface tension. Throws an
  /// [ArgumentError] for a material that does not say all three.
  factory NativeLiquidProperties.of(PhysicalMaterial material) {
    final density = material.density;
    final viscosity = material.fluid?.viscosity;
    final tension = material.fluid?.surfaceTension;
    if (density == null || viscosity == null || tension == null) {
      throw ArgumentError.value(
        material.id,
        'material',
        'says no density, viscosity or surface tension',
      );
    }
    return NativeLiquidProperties(
      density: density,
      viscosity: viscosity,
      tension: tension,
    );
  }

  /// Fresh water at 20 °C ([Materials.water]): what a shallow liquid starts
  /// as.
  static final NativeLiquidProperties water = NativeLiquidProperties.of(
    Materials.water,
  );

  /// The sea ([Materials.seawater]): salt makes it heavier and a little
  /// thicker. For a game set in the sea — a harbour, a reef a diver swims
  /// over.
  static final NativeLiquidProperties seawater = NativeLiquidProperties.of(
    Materials.seawater,
  );

  /// Olive oil ([Materials.oliveOil]): lighter than water, eighty times as
  /// thick.
  static final NativeLiquidProperties oliveOil = NativeLiquidProperties.of(
    Materials.oliveOil,
  );

  /// [oliveOil], by the name it had.
  @Deprecated(
    'Use NativeLiquidProperties.oliveOil, the catalogue\'s f3d.oliveOil. '
    'Deprecated in 1.0.0, removed in 2.0.0.',
  )
  static NativeLiquidProperties get oil => oliveOil;

  /// Honey ([Materials.honey]): ten thousand times as thick as water.
  static final NativeLiquidProperties honey = NativeLiquidProperties.of(
    Materials.honey,
  );

  /// Molten basalt ([Materials.basaltMelt]), a hundred pascal-seconds as it
  /// flows from a vent: a stone floats on it, and it creeps. For a game with
  /// a volcano whose flow runs downhill — the stone-age valley's.
  static final NativeLiquidProperties moltenBasalt = NativeLiquidProperties.of(
    Materials.basaltMelt,
  );

  /// Kilograms per cubic metre.
  final double density;

  /// Dynamic viscosity, Pa·s.
  final double viscosity;

  /// Surface tension, N/m.
  final double tension;

  NativeLiquidProperties copyWith({
    double? density,
    double? viscosity,
    double? tension,
  }) => NativeLiquidProperties(
    density: density ?? this.density,
    viscosity: viscosity ?? this.viscosity,
    tension: tension ?? this.tension,
  );

  @override
  String toString() =>
      'NativeLiquidProperties($density kg/m³, $viscosity Pa·s, $tension N/m)';
}

/// What heat sees of a liquid — [NativeWorld.setShallowHeat]: how hot it
/// is and how it takes heat from what stands in it.
///
/// The share of a body under the surface gives the liquid heat by forced
/// and free convection with these and the liquid's density and viscosity
/// ([NativeLiquidProperties]); in a liquid that [boils], a body hotter than
/// water boils at gives it heat by boiling — nucleate up to the critical
/// flux, film past Leidenfrost's point — when that carries more. What is
/// under does not burn, and a fire wholly under goes out. The liquid is a
/// reservoir: what it takes neither warms it nor boils it away.
///
/// **A view of a material in the catalogue** ([NativeLiquidHeat.of]), as
/// [NativeLiquidProperties] is.
final class NativeLiquidHeat {
  const NativeLiquidHeat({
    required this.temperature,
    required this.specificHeat,
    required this.conductivity,
    required this.expansion,
    this.boils = false,
  });

  /// [material]'s specific heat, conductivity and volumetric expansion, at
  /// [temperature], K. It [boils] as water does when it is water
  /// ([Materials.water]) unless told otherwise: the core's boiling is
  /// water's, at one atmosphere. Throws an [ArgumentError] for a material
  /// that does not say all three.
  factory NativeLiquidHeat.of(
    PhysicalMaterial material, {
    double temperature = standardAirTemperature,
    bool? boils,
  }) {
    final heat = material.thermal;
    final specificHeat = heat?.specificHeat;
    final conductivity = heat?.conductivity;
    final expansion = heat?.volumetricExpansion;
    if (specificHeat == null || conductivity == null || expansion == null) {
      throw ArgumentError.value(
        material.id,
        'material',
        'says no specific heat, conductivity or volumetric expansion',
      );
    }
    return NativeLiquidHeat(
      temperature: temperature,
      specificHeat: specificHeat,
      conductivity: conductivity,
      expansion: expansion,
      boils: boils ?? material.id == Materials.water.id,
    );
  }

  /// Fresh water at [temperature], K: its specific heat, conductivity and
  /// expansion at 20 °C ([Materials.water]), boiling as water does at one
  /// atmosphere. What a shallow liquid starts as, at the air's temperature:
  /// a game filling a pool in a world passes that world's
  /// [NativeWorld.airTemperature]; [standardAirTemperature] otherwise.
  factory NativeLiquidHeat.water({
    double temperature = standardAirTemperature,
  }) => NativeLiquidHeat.of(Materials.water, temperature: temperature);

  /// The same liquid at [temperature], K — for a game pouring it into a
  /// world at that world's [NativeWorld.airTemperature].
  NativeLiquidHeat at(double temperature) => NativeLiquidHeat(
    temperature: temperature,
    specificHeat: specificHeat,
    conductivity: conductivity,
    expansion: expansion,
    boils: boils,
  );

  /// In kelvin (K), the SI unit.
  final double temperature;

  /// J / (kg K).
  final double specificHeat;

  /// W / (m K): watts per metre kelvin.
  final double conductivity;

  /// Its volumetric expansion, 1/K: the fraction its volume grows by per
  /// kelvin, what makes it rise where a body warms it.
  final double expansion;

  /// Whether it boils as water does at one atmosphere, at water's boiling
  /// point ([Materials.water]'s, 373.15 K).
  final bool boils;

  NativeLiquidHeat copyWith({
    double? temperature,
    double? specificHeat,
    double? conductivity,
    double? expansion,
    bool? boils,
  }) => NativeLiquidHeat(
    temperature: temperature ?? this.temperature,
    specificHeat: specificHeat ?? this.specificHeat,
    conductivity: conductivity ?? this.conductivity,
    expansion: expansion ?? this.expansion,
    boils: boils ?? this.boils,
  );
}

/// Reals one piece of falling water takes in [NativeWorld.readSpray]: where
/// it is xyz, its velocity xyz, the water it carries, m³; then for a sheet
/// its width and its thickness — the flow it left with over its speed now,
/// so it thins as it falls — and for drops their diameter, twice; its kind,
/// [nativeSpraySheet] or [nativeSprayDrops]; and the face of the lip it
/// left, one past its index, nought for drops, so a sheet's pieces join into
/// one ribbon in the order they left.
const int nativeSprayFloats = c.sprayFloats;

/// Reals one fire takes in [NativeWorld.readFires], in the order
/// [NativeFire]'s fields are given.
const int nativeFireFloats = c.fireFloats;

/// One fire as the last step left it — [NativeWorld.fires].
final class NativeFire {
  const NativeFire._({
    required this.body,
    required this.at,
    required this.power,
    required this.reach,
    required this.axis,
    required this.base,
    required this.alight,
    required this.sootTemperature,
    required this.radiantShare,
    required this.sootYield,
  });

  /// What burns: a body, or for a compound one of its parts.
  final NativeBody body;

  /// Its middle: the body's, or the part's.
  final Vector3 at;

  /// W it gives off past what its flame gives back to the body:
  /// [radiantShare] of it as light, the rest as the hot gas of its plume.
  /// In watts.
  final double power;

  /// How far its flame reaches from [at], in metres: Heskestad's length
  /// over its [base], from the body's middle.
  final double reach;

  /// The unit axis its flame stands along: up, leaning with the wind by the
  /// speed of its own buoyancy.
  final Vector3 axis;

  /// The width of the patch alight, m, as the diameter of a ball of its
  /// area: the flame's base.
  final double base;

  /// The share of the body's surface (or the part's) alight, nought to one.
  final double alight;

  /// The temperature of the soot glowing in its flame, K — what its light
  /// is a blackbody of — and the share of [power] that leaves as
  /// radiation: the material's, or a burner's fuel's.
  final double sootTemperature, radiantShare;

  /// kg of soot it makes for every joule of [power]: its fuel's
  /// [NativeMaterial.sootYield] over its heat of combustion, so [power]
  /// times it is the kg/s of soot its smoke carries.
  final double sootYield;
}

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

/// A wheel as it is made — [NativeWorld.addWheel].
final class NativeWheelSettings {
  const NativeWheelSettings({
    required this.attach,
    required this.rest,
    required this.radius,
    required this.stiffness,
    required this.damping,
    required this.grip,
    this.width,
    this.rollingResistance = 0.015,
  });

  /// Where its suspension is fixed to the chassis, in the chassis's own
  /// frame.
  final Vector3 attach;

  /// The suspension's length at rest and the wheel's radius, m.
  final double rest, radius;

  /// The spring's stiffness, N/m, and its damping, N s/m.
  final double stiffness, damping;

  /// The tyre's grip: the friction coefficient of the road under it.
  final double grip;

  /// The tyre's width, in metres: what its rim meets a kerb or a plank across;
  /// null for 0.6 of its radius, a road car's tyre's shape.
  final double? width;

  /// The share of the load on it the tyre takes from its roll and holds it
  /// with, as a brake of that much would: a car with nothing on its drive
  /// or brake stays on a slope gentler than it and rolls down a steeper
  /// one, and coasts down at it times g. 0.010 to 0.015 is a car's tyre on
  /// asphalt (Gillespie, Fundamentals of Vehicle Dynamics, ch. 4).
  final double rollingResistance;

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  NativeWheelSettings copyWith({
    Vector3? attach,
    double? rest,
    double? radius,
    double? stiffness,
    double? damping,
    double? grip,
    double? width,
    double? rollingResistance,
    bool clearWidth = false,
  }) => NativeWheelSettings(
    attach: attach ?? this.attach,
    rest: rest ?? this.rest,
    radius: radius ?? this.radius,
    stiffness: stiffness ?? this.stiffness,
    damping: damping ?? this.damping,
    grip: grip ?? this.grip,
    width: clearWidth ? null : (width ?? this.width),
    rollingResistance: rollingResistance ?? this.rollingResistance,
  );
}

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
  Vector3 center,
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

  /// How far the part's shape is grown by a ball, rounding its edges and
  /// corners, in metres.
  final double rounding;
}

/// A joint in a [NativeWorld], named as a body is.
extension type const NativeJoint(int raw) {}

/// What kind of joint — `F3dJointType`.
///
/// **Closed, and it stays closed.** These four are solved inside the core's
/// step, and a fifth would be a change to the C core and its ABI. A joint or
/// a force of a game's own — a spring, a rope's pull, a magnet — is a
/// `NativeForceField`, computed in Dart each step before the core steps
/// (`NativeForceFields`, and `NativeDynamics.forceFields`); laws too heavy
/// for that go to a Wasm module.
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
    this.heatOfGasification = 0.0,
    this.criticalMassFlux = 0.0,
    this.flameSpread = 0.0,
    this.modulus = 0.0,
    this.poissonRatio = 0.0,
    this.sootTemperature = 0.0,
    this.charYield = 0.0,
    this.spreadMinimum = 0.0,
    this.ignitionInertia = 0.0,
    this.elementSurface = 0.0,
    this.elementDensity = 0.0,
    this.sootYield = 0.0,
  });

  /// The core's typical values for a material: one place they live, so the
  /// browser's module and the native library agree on them too.
  static NativeMaterial inert() => _preset(c.MaterialKind.inert);
  static NativeMaterial wood() => _preset(c.MaterialKind.wood);
  static NativeMaterial paper() => _preset(c.MaterialKind.paper);
  static NativeMaterial rubber() => _preset(c.MaterialKind.rubber);
  static NativeMaterial steel() => _preset(c.MaterialKind.steel);
  static NativeMaterial stone() => _preset(c.MaterialKind.stone);

  /// Red oak, as boards or beams, dry.
  static NativeMaterial oak() => _preset(c.MaterialKind.oak);

  /// Southern pine boards, dry.
  static NativeMaterial pine() => _preset(c.MaterialKind.pine);

  /// Corrugated board, as boxes are made of.
  static NativeMaterial cardboard() => _preset(c.MaterialKind.cardboard);

  /// A porous bed of dry straw — a thatched roof, a stack, a bale: give its
  /// body a density below 285 kg/m³, its stalks' own.
  static NativeMaterial thatch() => _preset(c.MaterialKind.thatch);

  /// Wood charcoal, which glows rather than flames: it burns on while it
  /// is heated as hard as glowing coals heat one another, and goes out
  /// short of that — [NativeBurner.charcoal] for a brazier of it.
  static NativeMaterial charcoal() => _preset(c.MaterialKind.charcoal);

  /// Paraffin wax, a burner's fuel ([NativeBurner.candle]); a body of it
  /// holds no fuel of its own, as wax melts and runs off.
  static NativeMaterial paraffin() => _preset(c.MaterialKind.paraffin);

  /// [material] as heat and fire see it: the core's preset its id names —
  /// `f3d.wood`, `f3d.oak`, `f3d.pine`, `f3d.paper`, `f3d.cardboard`,
  /// `f3d.thatch`, `f3d.charcoal`, `f3d.paraffin`, `f3d.rubber`,
  /// `f3d.steel`, `f3d.granite` (the core's stone) — or [inert] for any
  /// other, with what [material]'s thermal and mechanical groups say written
  /// over it: specific heat, conductivity, emissivity, where it catches, its
  /// heat of combustion, its flame's radiant share, its modulus and its
  /// Poisson's ratio.
  ///
  /// **How a plugin's material reaches the core.** The core holds the
  /// built-ins' numbers in its generated header; a plugin's are passed here,
  /// when the body made of it is given this material
  /// ([NativeWorld.setMaterial]), so no table in the core needs to learn
  /// it. For a built-in this is its preset to the bit. What only the fire
  /// model reads — how a flame creeps, how a char grows — is the preset's,
  /// and a plugin sets it with [copyWith].
  static NativeMaterial of(PhysicalMaterial material) {
    final base = switch (material.id) {
      'f3d.wood' => wood(),
      'f3d.oak' => oak(),
      'f3d.pine' => pine(),
      'f3d.paper' => paper(),
      'f3d.cardboard' => cardboard(),
      'f3d.thatch' => thatch(),
      'f3d.charcoal' => charcoal(),
      'f3d.paraffin' => paraffin(),
      'f3d.rubber' => rubber(),
      'f3d.steel' => steel(),
      'f3d.granite' => stone(),
      _ => inert(),
    };
    final heat = material.thermal;
    final stiffness = material.mechanical;
    // Through f32, as the core holds them: a built-in's view is its preset
    // to the bit.
    double? f32(double? value) =>
        value == null ? null : (Float32List(1)..[0] = value)[0];
    return base.copyWith(
      specificHeat: f32(heat?.specificHeat),
      conductivity: f32(heat?.conductivity),
      emissivity: f32(heat?.emissivity),
      ignitionTemperature: f32(heat?.ignitionTemperature),
      heatOfCombustion: f32(heat?.heatOfCombustion),
      flameRadiant: f32(heat?.radiantFraction),
      modulus: f32(stiffness?.youngsModulus),
      poissonRatio: f32(stiffness?.poissonRatio),
    );
  }

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
        heatOfGasification: at(c.F3dMaterialLayout.heatOfGasification),
        criticalMassFlux: at(c.F3dMaterialLayout.criticalMassFlux),
        flameSpread: at(c.F3dMaterialLayout.flameSpread),
        modulus: at(c.F3dMaterialLayout.modulus),
        poissonRatio: at(c.F3dMaterialLayout.poissonRatio),
        sootTemperature: at(c.F3dMaterialLayout.sootTemperature),
        charYield: at(c.F3dMaterialLayout.charYield),
        spreadMinimum: at(c.F3dMaterialLayout.spreadMinimum),
        ignitionInertia: at(c.F3dMaterialLayout.ignitionInertia),
        elementSurface: at(c.F3dMaterialLayout.elementSurface),
        elementDensity: at(c.F3dMaterialLayout.elementDensity),
        sootYield: at(c.F3dMaterialLayout.sootYield),
      );
    } finally {
      c.coreFree(out);
    }
  }

  /// This material with the values given changed: a preset's pine as
  /// boards, say, or with its own flame spread.
  NativeMaterial copyWith({
    double? specificHeat,
    double? emissivity,
    double? ignitionTemperature,
    double? heatOfCombustion,
    double? burnRate,
    double? fuelFraction,
    double? flameFeedback,
    double? conductivity,
    double? flameTemperature,
    double? flameConvection,
    double? flameRadiant,
    double? flameAbsorption,
    double? heatOfGasification,
    double? criticalMassFlux,
    double? flameSpread,
    double? modulus,
    double? poissonRatio,
    double? sootTemperature,
    double? charYield,
    double? spreadMinimum,
    double? ignitionInertia,
    double? elementSurface,
    double? elementDensity,
    double? sootYield,
  }) => NativeMaterial(
    specificHeat: specificHeat ?? this.specificHeat,
    emissivity: emissivity ?? this.emissivity,
    ignitionTemperature: ignitionTemperature ?? this.ignitionTemperature,
    heatOfCombustion: heatOfCombustion ?? this.heatOfCombustion,
    burnRate: burnRate ?? this.burnRate,
    fuelFraction: fuelFraction ?? this.fuelFraction,
    flameFeedback: flameFeedback ?? this.flameFeedback,
    conductivity: conductivity ?? this.conductivity,
    flameTemperature: flameTemperature ?? this.flameTemperature,
    flameConvection: flameConvection ?? this.flameConvection,
    flameRadiant: flameRadiant ?? this.flameRadiant,
    flameAbsorption: flameAbsorption ?? this.flameAbsorption,
    heatOfGasification: heatOfGasification ?? this.heatOfGasification,
    criticalMassFlux: criticalMassFlux ?? this.criticalMassFlux,
    flameSpread: flameSpread ?? this.flameSpread,
    modulus: modulus ?? this.modulus,
    poissonRatio: poissonRatio ?? this.poissonRatio,
    sootTemperature: sootTemperature ?? this.sootTemperature,
    charYield: charYield ?? this.charYield,
    spreadMinimum: spreadMinimum ?? this.spreadMinimum,
    ignitionInertia: ignitionInertia ?? this.ignitionInertia,
    elementSurface: elementSurface ?? this.elementSurface,
    elementDensity: elementDensity ?? this.elementDensity,
    sootYield: sootYield ?? this.sootYield,
  );

  /// Written into the core's `F3dMaterial` at [to].
  void _write(int to) {
    void put(int offset, double value) => c.writeF32(to + offset, value);
    put(c.F3dMaterialLayout.specificHeat, specificHeat);
    put(c.F3dMaterialLayout.emissivity, emissivity);
    put(c.F3dMaterialLayout.ignitionTemperature, ignitionTemperature);
    put(c.F3dMaterialLayout.heatOfCombustion, heatOfCombustion);
    put(c.F3dMaterialLayout.burnRate, burnRate);
    put(c.F3dMaterialLayout.fuelFraction, fuelFraction);
    put(c.F3dMaterialLayout.flameFeedback, flameFeedback);
    put(c.F3dMaterialLayout.conductivity, conductivity);
    put(c.F3dMaterialLayout.flameTemperature, flameTemperature);
    put(c.F3dMaterialLayout.flameConvection, flameConvection);
    put(c.F3dMaterialLayout.flameRadiant, flameRadiant);
    put(c.F3dMaterialLayout.flameAbsorption, flameAbsorption);
    put(c.F3dMaterialLayout.heatOfGasification, heatOfGasification);
    put(c.F3dMaterialLayout.criticalMassFlux, criticalMassFlux);
    put(c.F3dMaterialLayout.flameSpread, flameSpread);
    put(c.F3dMaterialLayout.modulus, modulus);
    put(c.F3dMaterialLayout.poissonRatio, poissonRatio);
    put(c.F3dMaterialLayout.sootTemperature, sootTemperature);
    put(c.F3dMaterialLayout.charYield, charYield);
    put(c.F3dMaterialLayout.spreadMinimum, spreadMinimum);
    put(c.F3dMaterialLayout.ignitionInertia, ignitionInertia);
    put(c.F3dMaterialLayout.elementSurface, elementSurface);
    put(c.F3dMaterialLayout.elementDensity, elementDensity);
    put(c.F3dMaterialLayout.sootYield, sootYield);
  }

  /// J / (kg K).
  final double specificHeat;

  /// Of the surface, nought to one.
  final double emissivity;

  /// K at which it catches and below which it goes out; nought for a
  /// material that never burns. In kelvin, the SI unit.
  final double ignitionTemperature;

  /// J released per kilogram burnt.
  final double heatOfCombustion;

  /// kg burnt per second per square metre of surface while alight, as
  /// measured for the material. Checked, no longer read: a fire burns at
  /// the rate its heat balance gives, ṁ'' = q''_net / [heatOfGasification].
  final double burnRate;

  /// The share of the mass that can burn, nought up to but not one.
  final double fuelFraction;

  /// Checked, no longer read: what a flame gives back to its own surface
  /// follows from the flame ([flameTemperature], [flameConvection],
  /// [flameAbsorption]) and the size of what burns. A fraction, checked to
  /// lie in 0..1.
  final double flameFeedback;

  /// W / (m K), watts per metre kelvin: how readily heat crosses into what
  /// it touches.
  final double conductivity;

  /// The gas of its fire's flame, in kelvin (K, the SI unit): above
  /// [ignitionTemperature] for a material that burns, and what heats a body
  /// standing in the flame.
  final double flameTemperature;

  /// W / (m² K), watts per square metre kelvin: what the flame's gas passes
  /// to a surface standing in it.
  final double flameConvection;

  /// The share of the heat its fire gives off that leaves as radiation
  /// rather than in the gas, nought to one: about a third for wood, nearly
  /// half for a sooty rubber fire.
  final double flameRadiant;

  /// Per metre of flame seen through: its emissivity is 1 − e^(−κL).
  final double flameAbsorption;

  /// J/kg a burning surface spends turning a kilogram of itself to fuel
  /// gas, so it burns at ṁ'' = q''_net / L (Tewarson). Nought takes
  /// 1.81 MJ/kg, Douglas fir's.
  final double heatOfGasification;

  /// kg / (m² s): the least a surface must give off for a flame to stand
  /// on it (Rasbash's firepoint); a patch that gives less goes out. Nought
  /// takes 2.5 g / (m² s), wood's.
  final double criticalMassFlux;

  /// Φ, W²/m³: the flame spread parameter of the LIFT test, so a flame's
  /// edge creeps over a surface at Φ / (kρc (T_ig − T_s)²) (Quintiere and
  /// Harkleroad). Nought takes 12.9 kW²/m³, plywood's.
  final double flameSpread;

  /// Young's modulus, Pa: how two curved bodies pressed together flatten
  /// into a contact (Hertz), and so how much heat crosses it. Nought takes
  /// 0.91 GPa, pine across its grain.
  final double modulus;

  /// Poisson's ratio, with [modulus].
  final double poissonRatio;

  /// K: the soot that glows in its flame, which gives the flame its light —
  /// hotter than the mean gas, [flameTemperature], that heats what stands
  /// in it. Nought takes [flameTemperature]. In kelvin, the SI unit.
  final double sootTemperature;

  /// The share of what burns left as char, nought to below one: under its
  /// fire a char layer grows that insulates the wood beneath and glows
  /// hotter than the wood catches at, and the wood under it gives off gas in
  /// depth as well as at the front. Nought for a material that does not
  /// char.
  final double charYield;

  /// K: the coolest surface a flame's edge creeps over sideways (the LIFT
  /// test's minimum); colder, the edge stands. Nought for none. In kelvin,
  /// the SI unit.
  final double spreadMinimum;

  /// kρc, J² / (m⁴ K² s) — joules squared per metre⁴ kelvin² second — as
  /// the LIFT test measures it with the ignition temperature and the spread
  /// parameter: what how soon a surface catches and how fast a flame's edge
  /// creeps answer to. Nought takes
  /// [conductivity] × density × [specificHeat].
  final double ignitionInertia;

  /// σ, 1/m: for a porous bed of fine fuel — straw, grass, needles — its
  /// elements' surface over their volume; nought for a solid. A body made
  /// of it is a bed packed at its density over [elementDensity]; heat
  /// reaches in as far as radiation passes between the elements, 4/(βσ),
  /// and heats them through there, so a hot stone on thatch sets it
  /// burning on where a slab of the same stuff would go out. Tall grass,
  /// Anderson's fuel model 3, is 4921 (USDA INT-122, 1982).
  final double elementSurface;

  /// ρ_p, kg/m³: a porous bed's elements' own density; Rothermel's 513 for
  /// every fine fuel (USDA INT-115, 1972). Needed with [elementSurface].
  final double elementDensity;

  /// kg of soot its fire makes per kg of it burnt, nought to one: what
  /// darkens its smoke. 0.015 for wood in small fires (Tewarson, SFPE
  /// Handbook), 0.002 for a pine crib burning freely (NIST TN 2102), 0.13
  /// to 0.16 for crude oil in a pool metres across (Evans and colleagues,
  /// J. Res. NIST 106, 2001); nought for none.
  final double sootYield;
}

/// A fire fed rather than caught: [rate] kg/s of [fuel] burnt on a body —
/// a torch's head, a brazier, a fire someone tends — giving off that times
/// the fuel's heat of combustion with its flame, whatever the body is made
/// of and whether or not it has fuel of its own. [NativeWorld.setBurner].
final class NativeBurner {
  const NativeBurner({required this.fuel, required this.rate});

  /// A candle of paraffin wax 21 mm across: 1.75 mg/s, 77 W, its flame
  /// 42 mm tall (Hamins, Bundy and Dillon, J. Fire Protection Eng. 15,
  /// 2005).
  static NativeBurner candle() =>
      NativeBurner(fuel: NativeMaterial.paraffin(), rate: 1.75e-6);

  /// The cross piles of Douglas fir sticks Gross burnt at the NBS, each ten
  /// layers high, at the most they lost a second (J. Res. NBS 66C, 1962,
  /// table 1), burning [NativeMaterial.pine]: kindling — 3 sticks of 0.32
  /// cm a layer, 4.6 g, 0.128 g/s, a flame 0.44 m tall, about 1.8 kW.
  static NativeBurner kindling() =>
      NativeBurner(fuel: NativeMaterial.pine(), rate: 1.28e-4);

  /// A brazier's: 3 sticks of 1.27 cm a layer, 286 g, 1.24 g/s, a flame
  /// 0.77 m tall, about 17 kW.
  static NativeBurner brazier() =>
      NativeBurner(fuel: NativeMaterial.pine(), rate: 1.24e-3);

  /// A campfire's: 5 sticks of 2.54 cm a layer, 4.15 kg, 5.58 g/s, about
  /// 78 kW.
  static NativeBurner campfire() =>
      NativeBurner(fuel: NativeMaterial.pine(), rate: 5.58e-3);

  /// A bonfire's: 7 beams of 9.15 cm a layer, 262 kg, 57.5 g/s, a flame
  /// 4.6 m tall, about 0.8 MW.
  static NativeBurner bonfire() =>
      NativeBurner(fuel: NativeMaterial.pine(), rate: 5.75e-2);

  /// Charcoal glowing over [surface] m² of its coals: as fast as oxygen
  /// reaches a glowing surface, [NativeMaterial.charcoal]'s burn rate, 1.02
  /// g/(m² s) (`doc/derivations/charcoal_glow.md`) — a brazier of coals.
  static NativeBurner charcoal(double surface) {
    final fuel = NativeMaterial.charcoal();
    return NativeBurner(fuel: fuel, rate: fuel.burnRate * surface);
  }

  /// What burns; it must have a heat of combustion and an ignition
  /// temperature.
  final NativeMaterial fuel;

  /// kg/s.
  final double rate;

  /// The heat it gives off, in watts, before its flame hands some to the
  /// body.
  double get power => rate * fuel.heatOfCombustion;

  NativeBurner copyWith({NativeMaterial? fuel, double? rate}) =>
      NativeBurner(fuel: fuel ?? this.fuel, rate: rate ?? this.rate);
}

/// A charge going off — [NativeWorld.explode]: [energy] J from [mass] kg.
final class NativeExplosion {
  const NativeExplosion({required this.energy, required this.mass});

  /// [kilograms] of TNT: 4.184 MJ each, the TNT equivalent's definition.
  const NativeExplosion.tnt(double kilograms)
    : energy = kilograms * 4.184e6,
      mass = kilograms;

  /// The charge's energy, in joules.
  final double energy;

  /// kg of charge, which sets how fast its products carry the energy out:
  /// the momentum √(2·E_G·m) with E_G TNT's Gurney share of [energy].
  final double mass;
}

/// What a step said happened to a body — `F3dEventKind`. Constants rather
/// than an enum, for the reason [NativeBodyType] gives: the solver and the
/// joints will bring kinds of their own.
///
/// **The core's kinds are closed; a plugin's are not.** The core raises
/// only the codes below [firstPluginCode], and a binding learns a new one
/// with a release. A plugin element written in Dart raises its own events —
/// a field of its that froze a body, a gust that toppled one — and names
/// them with [NativeEventKind.plugin], at a code from [firstPluginCode] up
/// that the core never uses. Which plugin holds which code is the engine's
/// to keep, not this class's: `ElementEventKinds` in `flutter3d_effects`
/// refuses two claims on one code or one name.
final class NativeEventKind {
  const NativeEventKind._(this.code, this.name);

  /// A plugin's own kind: [code] at or above [firstPluginCode], [name] the
  /// way a log and a digest's reader call it — `'myplugin.frozen'`.
  const NativeEventKind.plugin(this.code, this.name)
    : assert(
        code >= firstPluginCode,
        'a plugin kind takes a code from firstPluginCode up; the ones below '
        'are the core\'s',
      );

  /// The first code a plugin's kind may take. Everything below it is the
  /// core's, raised by a step and read by [of].
  static const int firstPluginCode = 0x10000;

  /// Whether this is a plugin's kind rather than the core's.
  bool get isPlugin => code >= firstPluginCode;

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

  /// A body came into a liquid: some of it under a surface where the step
  /// before found none.
  static const NativeEventKind wetted = NativeEventKind._(
    c.EventKind.wetted,
    'wetted',
  );

  /// A burner went out: the body it burns on went wholly under a liquid,
  /// and its feed is off.
  static const NativeEventKind burnerOut = NativeEventKind._(
    c.EventKind.burnerOut,
    'burnerOut',
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
    wetted,
    burnerOut,
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

/// A world of bodies owned and stepped by the C core.
///
/// **Numbers cross as f32.** The core is single precision throughout, which
/// is what makes its deterministic mode the same bits on every platform, so a
/// value set here is rounded to the nearest float on the way in. Positions
/// are relative to the world's [origin], held in doubles; a world far
/// larger than f32 can hold to a millimetre moves its origin to the play
/// with [moveOriginTo].
///
/// **Two kinds of position, and the type says which.** A [WorldPosition]
/// ([positionOf], [moveOriginTo]) is a place in the world in doubles; every
/// `Vector3` position this world takes or gives — a body's start, a
/// kinematic target, an impulse's point, where the wind is sampled — is
/// origin-local, single precision, relative to [origin].
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
    if (_pieceRoom > 0) {
      _pieces.free();
      _pieceWaters.free();
      _pieceRoom = 0;
    }
    _world = 0;
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _world == 0;

  Vector3 _read3() => Vector3(_out[0], _out[1], _out[2]);

  // ---------------------------------------------------------------- world

  /// Metres per second squared; [standardGravityVector] for a new world.
  ///
  /// **The world's, and everything in it reads it here** — a cloth or a
  /// spray handed this world falls by it, a fire's embers drop by it, a
  /// weir pours and a depth presses by [gravityMagnitude]. A world set on
  /// the Moon is this one assignment.
  Vector3 get gravity {
    c.f3d_world_get_gravity(_live, _out);
    return _read3();
  }

  set gravity(Vector3 value) =>
      c.f3d_world_set_gravity(_live, value.x, value.y, value.z);

  /// How strong [gravity] is, m/s² — what a consumer that wants a number
  /// rather than a direction reads: a depth's pressure, a weir's flow, a
  /// stream's fall, an ember's drop.
  ///
  /// **[standardGravity] to the bit for a world whose gravity is the one it
  /// was made with.** The core keeps gravity in f32, and 9.81 read back
  /// through f32 is 9.8100004196…: a consumer that wrote 9.81 before it read
  /// its world would otherwise move every number it makes by four parts in
  /// a hundred million, and every tape, digest and golden made under 9.81
  /// with it. Any other gravity is its length, from the f32 the core holds.
  double get gravityMagnitude {
    c.f3d_world_get_gravity(_live, _out);
    final x = _out[0], y = _out[1], z = _out[2];
    if (x == 0.0 && z == 0.0 && y == _standardDown) return standardGravity;
    return math.sqrt(x * x + y * y + z * z);
  }

  /// [standardGravity] downward, as the core's f32 holds it.
  static final double _standardDown = standardGravityVector.y;

  /// The air's temperature, K; [standardAirTemperature] for a new world.
  ///
  /// Read by whatever sets something at the temperature of the air it is
  /// in: a pool filled in this world, a car's tyres before they warm.
  double get airTemperature {
    c.f3d_world_get_air(_live, _out);
    return _out[0];
  }

  /// The air's density, kg/m³; [standardAirDensity] for a new world.
  double get airDensity {
    c.f3d_world_get_air(_live, _out);
    return _out[1];
  }

  /// The air's pressure at the world's datum — the surface of its sea, the
  /// floor of its valley — Pa; [standardAtmosphere] for a new world.
  ///
  /// **Dart's, not the core's.** Nothing the core steps is pressed by the
  /// air: drag and lift answer to its density, heat to its temperature. The
  /// pressure is read by whoever adds the weight of what is above a point —
  /// a diver's gauge, a lung's volume — and is kept here so that sum starts
  /// from this world's air rather than a number written beside it. In the
  /// [snapshot] all the same, in a section of its own the core passes over,
  /// so a world rewound is rewound to the air it was saved in. Throws an
  /// [ArgumentError] for a value that is not finite and positive.
  double get airPressure => _airPressure;
  double _airPressure = standardAtmosphere;

  set airPressure(double value) {
    if (!(value.isFinite && value > 0.0)) {
      throw ArgumentError('air at $value Pa');
    }
    _airPressure = value;
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

  /// Makes this world [properties]' world: its gravity, its air's
  /// temperature, density and pressure, and its wind. What changed since
  /// [previous] — what was applied last, when the caller kept it — and only
  /// that is written, so a wind that did not change wakes nobody; with no
  /// [previous], everything is.
  ///
  /// **The medium is not the core's.** The core's ambient fluid is always
  /// air, which drags and cools what is in it; a world whose
  /// `WorldProperties.medium` is water fills it with a liquid the core
  /// steps ([addShallowLiquid]) rather than with denser air. Throws an
  /// [ArgumentError] as the setters do.
  void applyProperties(
    WorldProperties properties, {
    WorldProperties? previous,
  }) {
    if (previous == null || previous.gravity != properties.gravity) {
      gravity = properties.gravity;
    }
    if (previous == null ||
        previous.airTemperature != properties.airTemperature ||
        previous.airDensity != properties.airDensity) {
      setAir(
        temperature: properties.airTemperature,
        density: properties.airDensity,
      );
    }
    airPressure = properties.airPressure;
    if (previous == null || previous.wind != properties.wind) {
      wind = properties.wind;
    }
  }

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
  WorldPosition get origin {
    c.f3d_world_get_origin(_live, _outDouble);
    return WorldPosition(_outDouble[0], _outDouble[1], _outDouble[2]);
  }

  /// Moves the origin to [to], and every body and the wind grid the other
  /// way by the difference, taken in doubles, so that nothing moves in the
  /// world and what is near the new origin gets f32's full precision back.
  ///
  /// **The one origin call of a physics world**, the same as
  /// `CollisionWorld.moveOriginTo`: what a game's `OriginShifted` hook calls
  /// with `OriginShifted.to`.
  void moveOriginTo(WorldPosition to) {
    final by = to.relativeTo(origin);
    c.f3d_world_shift_origin(_live, by.x, by.y, by.z);
  }

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

  /// Every burning body, or burning part of a compound, [nativeFireFloats]
  /// floats apiece, as [fires] reads them.
  ({Float32List fires, List<NativeBody> bodies}) readFires() {
    final read = _readPer(bodyCount, nativeFireFloats, c.f3d_world_read_fires);
    return (fires: read.transforms, bodies: read.bodies);
  }

  /// Every burning body, or burning part of a compound, as the last step
  /// left it — the parts of one compound in part order.
  List<NativeFire> fires() {
    final (:fires, :bodies) = readFires();
    const n = nativeFireFloats;
    return <NativeFire>[
      for (var k = 0; k < bodies.length; k++)
        NativeFire._(
          body: bodies[k],
          at: Vector3(fires[n * k], fires[n * k + 1], fires[n * k + 2]),
          power: fires[n * k + 3],
          reach: fires[n * k + 4],
          axis: Vector3(fires[n * k + 5], fires[n * k + 6], fires[n * k + 7]),
          base: fires[n * k + 8],
          alight: fires[n * k + 9],
          sootTemperature: fires[n * k + 10],
          radiantShare: fires[n * k + 11],
          sootYield: fires[n * k + 12],
        ),
    ];
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
  bool get isFast => c.f3d_world_fast(_live) != 0;

  set isFast(bool enabled) => c.f3d_world_set_fast(_live, enabled ? 1 : 0);

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
  ///
  /// The bytes are versioned field by field, little-endian, so a save keeps:
  /// a snapshot taken by 1.0.0 or later is restored by every later 1.x
  /// release, on the native library and in the browser alike. Snapshots
  /// from before 1.0.0 were the core's memory as it lay and are not
  /// migrated.
  ///
  /// **The air's pressure goes in a section of its own**, `PRES`, when it is
  /// not [standardAtmosphere]: the pressure is Dart's ([airPressure]), the
  /// core passes over a section it does not know, and a world in the
  /// standard air writes the bytes it always wrote.
  Uint8List snapshot() {
    final size = c.f3d_world_snapshot_size(_live);
    final buffer = c.U8s.alloc(size);
    final Uint8List core;
    try {
      final written = c.f3d_world_snapshot_write(_live, buffer, size);
      if (written != size) {
        throw StateError('the physics core wrote $written of $size bytes');
      }
      core = buffer.copy(size);
    } finally {
      buffer.free();
    }
    if (_airPressure == standardAtmosphere) return core;
    return _withPressure(core, _airPressure);
  }

  /// The snapshot header's section count, a u32 after the magic, the
  /// format's minor and major, the writer's ABI and its reals' width.
  static const int _sectionCountAt = 16;

  /// `PRES`, little-endian, as the core spells a section's id.
  static const int _pressureSection = 0x53455250;

  /// [core] with a `PRES` section after its last: id, version 1, eight
  /// bytes, the pressure as an f64; the header's count one more.
  static Uint8List _withPressure(Uint8List core, double pressure) {
    final out = Uint8List(core.length + 20)..setAll(0, core);
    final view = ByteData.sublistView(out);
    view
      ..setUint32(
        _sectionCountAt,
        view.getUint32(_sectionCountAt, Endian.little) + 1,
        Endian.little,
      )
      ..setUint32(core.length, _pressureSection, Endian.little)
      ..setUint32(core.length + 4, 1, Endian.little)
      ..setUint32(core.length + 8, 8, Endian.little)
      ..setFloat64(core.length + 12, pressure, Endian.little);
    return out;
  }

  /// The pressure a `PRES` section of [snapshot] holds, or
  /// [standardAtmosphere] for a snapshot without one — every snapshot
  /// taken in the standard air, and every one from before the section.
  static double _pressureIn(Uint8List snapshot) {
    const header = 20;
    if (snapshot.length < header) return standardAtmosphere;
    final view = ByteData.sublistView(snapshot);
    final count = view.getUint32(_sectionCountAt, Endian.little);
    var at = header;
    for (var i = 0; i < count && at + 12 <= snapshot.length; i++) {
      final id = view.getUint32(at, Endian.little);
      final length = view.getUint32(at + 8, Endian.little);
      if (id == _pressureSection && length >= 8 && at + 20 <= snapshot.length) {
        final pressure = view.getFloat64(at + 12, Endian.little);
        return pressure.isFinite && pressure > 0.0
            ? pressure
            : standardAtmosphere;
      }
      at += 12 + length;
    }
    return standardAtmosphere;
  }

  /// Puts the world back as [snapshot] says. Takes a snapshot from any
  /// release since 1.0.0 up to this one's major. Throws an [ArgumentError]
  /// for bytes it cannot read — not a snapshot, damaged, from before 1.0.0
  /// or from a later major — and leaves the world as it was.
  void restore(Uint8List snapshot) {
    final buffer = c.U8s.alloc(snapshot.isEmpty ? 1 : snapshot.length);
    try {
      buffer.setAll(snapshot);
      if (c.f3d_world_restore(_live, buffer, snapshot.length) == 0) {
        throw ArgumentError.value(
          snapshot.length,
          'snapshot',
          'not a snapshot this physics core reads: damaged, from before '
              '1.0.0, or from a later major',
        );
      }
    } finally {
      buffer.free();
    }
    _airPressure = _pressureIn(snapshot);
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

  /// [body]'s position relative to the [origin], in single precision: what
  /// the core holds, for a caller working in the world's local frame (a
  /// force field, a ragdoll's bones). Throws an [ArgumentError] for a body
  /// not in the world. [positionOf] is the same place in the world.
  Vector3 localPositionOf(NativeBody body) {
    _check(c.f3d_body_get_position(_live, body.raw, _out), body);
    return _read3();
  }

  void setPosition(NativeBody body, Vector3 value) => _check(
    c.f3d_body_set_position(_live, body.raw, value.x, value.y, value.z),
    body,
    value,
  );

  /// [body]'s place in the world, the [origin] added, in double precision.
  /// One position, as every world-space position in the engine is a
  /// [WorldPosition]; [localPositionOf] is the single-precision offset from
  /// the origin the core holds. Throws an [ArgumentError] for a body not in
  /// the world.
  WorldPosition positionOf(NativeBody body) {
    _check(c.f3d_body_get_world_position(_live, body.raw, _outDouble), body);
    return WorldPosition(_outDouble[0], _outDouble[1], _outDouble[2]);
  }

  /// [body]'s velocity, metres per second.
  Vector3 velocityOf(NativeBody body) {
    _check(c.f3d_body_get_velocity(_live, body.raw, _out), body);
    return _read3();
  }

  /// A kinematic [body] sent to [position], turned to [orientation], over
  /// the next [dt] seconds: its velocity and spin set to carry it there, so
  /// what it meets on the way is pushed as by anything moving that fast.
  /// The game calls it each frame with where its object is next.
  ///
  /// **[position] is origin-local**, as every `Vector3` position this world
  /// takes is: single precision, relative to [origin]. A caller holding a
  /// [WorldPosition] narrows it against [origin] first.
  void moveKinematic(
    NativeBody body,
    Vector3 position,
    Quaternion orientation,
    double dt,
  ) {
    if (c.f3d_body_move_kinematic(
          _live,
          body.raw,
          position.x,
          position.y,
          position.z,
          orientation.x,
          orientation.y,
          orientation.z,
          orientation.w,
          dt,
        ) ==
        0) {
      throw ArgumentError(
        '$body: not a kinematic body in this world, a pose not finite, or a '
        'step not above nought',
      );
    }
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

  /// The basin the point ([x], [z]) is in filled to [level] above the
  /// water's origin: that cell and every cell reached from it side by side
  /// over ground below [level] and through no wall — a lagoon to its rim,
  /// not the sea past the ridge. How many cells it filled; nought where the
  /// point is off the grid, on ground above [level], or a wall.
  int fillShallowBasin(
    NativeShallowLiquid water, {
    required double x,
    required double z,
    required double level,
  }) {
    if (!(x.isFinite && z.isFinite && level.isFinite)) {
      throw ArgumentError('a basin not finite');
    }
    return c.f3d_shallow_fill_basin(_live, water.id, x, z, level);
  }

  /// Each of [water]'s cells' depth, x fastest, m: the water as a game saved
  /// it. A wall keeps what it holds.
  void setShallowDepth(NativeShallowLiquid water, List<double> depth) {
    if (depth.length != water.cells) {
      throw ArgumentError.value(depth.length, 'depth', 'not ${water.cells}');
    }
    final d = c.F32s.alloc(depth.length);
    try {
      d.setAll(depth);
      if (c.f3d_shallow_set_depth(_live, water.id, d) == 0) {
        throw ArgumentError('a depth below nought or not finite');
      }
    } finally {
      d.free();
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
  /// [radius], or drawn off where [rate] is negative, as far as there is
  /// water; a rate of nought stops it. A spring and a drain of one rate
  /// make a current between them through water that keeps its level. At
  /// most [c.shallowMostSources].
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
        'spring $index: past ${c.shallowMostSources}, a radius below '
        'nought, or a value not finite',
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
  void setShallowProperties(
    NativeShallowLiquid water,
    NativeLiquidProperties fluid,
  ) {
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

  /// What heat sees of [water]: [NativeLiquidHeat.water] at the air's
  /// temperature, as it starts. A hot spring, a pool of molten rock that
  /// sets fire to the wood dropped in it, a quench tank.
  void setShallowHeat(NativeShallowLiquid water, NativeLiquidHeat heat) {
    if (c.f3d_shallow_set_heat(
          _live,
          water.id,
          heat.temperature,
          heat.specificHeat,
          heat.conductivity,
          heat.expansion,
          heat.boils ? 1 : 0,
        ) ==
        0) {
      throw ArgumentError(
        'a liquid at ${heat.temperature} K, ${heat.specificHeat} J/(kg K), '
        '${heat.conductivity} W/(m K) and ${heat.expansion} 1/K',
      );
    }
  }

  /// What [side] of [water]'s grid is. [setShallowBed] sets all four to
  /// [NativeEdgeFlow.wall] or [NativeEdgeFlow.free]. What crosses an edge
  /// counts in [shallowVolume]'s lost, out less in.
  void setShallowEdge(
    NativeShallowLiquid water,
    GridSide side,
    NativeEdgeFlow edge,
  ) {
    if (c.f3d_shallow_set_edge(
          _live,
          water.id,
          side.code,
          edge.kind,
          edge.value,
        ) ==
        0) {
      throw ArgumentError.value(edge.value, '$side', 'not finite');
    }
  }

  /// Outlet [index] of [water], or none there for null. At most
  /// [c.shallowMostOutlets]; what they let out counts in [shallowVolume]'s
  /// lost.
  void setShallowOutlet(
    NativeShallowLiquid water,
    int index,
    NativeOutlet? outlet,
  ) {
    final o = outlet ?? const NativeOutlet.weir(x: 0, z: 0, crest: 0, width: 0);
    if ((o.drain ? c.f3d_shallow_set_drain : c.f3d_shallow_set_outlet)(
          _live,
          water.id,
          index,
          o.x,
          o.z,
          o.crest,
          o.width,
          o.coefficient,
        ) ==
        0) {
      throw ArgumentError(
        'outlet $index: past ${c.shallowMostOutlets}, a width below nought, '
        'or a value not finite',
      );
    }
  }

  /// Which of [water]'s cells are walls, x fastest: no water crosses into
  /// or out of a wall, and nothing lands in it — a quay, a pier's foot, a
  /// building standing in a flood.
  void setShallowWalls(NativeShallowLiquid water, List<bool> walls) {
    if (walls.length != water.cells) {
      throw ArgumentError.value(walls.length, 'walls', 'not ${water.cells}');
    }
    final w = c.U32s.alloc(walls.length);
    try {
      for (var i = 0; i < walls.length; i++) {
        w[i] = walls[i] ? 1 : 0;
      }
      c.f3d_shallow_set_cells(_live, water.id, 0, w);
    } finally {
      w.free();
    }
  }

  /// Each of [water]'s cells' own Manning roughness, x fastest; a negative
  /// one takes the water's own ([setShallowBed]): a stony reach in a sandy
  /// bed, weed along a bank — what a game paints from its terrain's
  /// materials.
  void setShallowRoughness(NativeShallowLiquid water, List<double> roughness) {
    if (roughness.length != water.cells) {
      throw ArgumentError.value(
        roughness.length,
        'roughness',
        'not ${water.cells}',
      );
    }
    final r = c.F32s.alloc(roughness.length);
    try {
      r.setAll(roughness);
      if (c.f3d_shallow_set_cells(_live, water.id, r, 0) == 0) {
        throw ArgumentError('a roughness not finite');
      }
    } finally {
      r.free();
    }
  }

  /// What [water]'s last step was.
  NativeShallowInfo shallowInfoOf(NativeShallowLiquid water) {
    final out = c.F32s.alloc(c.shallowInfoFloats);
    try {
      c.f3d_shallow_info(_live, water.id, out);
      return (
        substeps: out[0].round(),
        overruns: out[1].round(),
        resting: out[2] != 0,
        energy: out[3],
      );
    } finally {
      out.free();
    }
  }

  /// When the world's waters rest — stop being stepped until something
  /// stirs them: once no cell has held more than [energy] J/m² of motion
  /// and of surface standing off its neighbours' for [seconds], with
  /// nothing feeding, draining or moving in it. [seconds] of nought keeps
  /// them always stepped. 5e-4 J/m² — a metre of water moving a millimetre
  /// a second — and a second, at first. A game that films slow ripples, or
  /// one that wants a still pond to cost nothing sooner, sets its own.
  void setWaterRest({double energy = 5e-4, double seconds = 1}) {
    if (c.f3d_world_set_water_rest(_live, energy, seconds) == 0) {
      throw ArgumentError('a rest below nought or not finite');
    }
  }

  /// The water at ([x], [z]), or null outside its grid.
  NativeShallowSample? sampleShallow(
    NativeShallowLiquid water,
    double x,
    double z,
  ) {
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

  /// Every cell's ground as the water stands on it, above its origin, x
  /// fastest: for a game that draws its own bed mesh, or saves a map it has
  /// dug, from the bed the water stands on, so the shore it draws is the one
  /// the water keeps.
  Float32List readShallowGround(NativeShallowLiquid water) {
    final read = readShallowSurface(water);
    return Float32List(water.cells)..setAll(0, <double>[
      for (var i = 0; i < water.cells; i++) read.surface[i] - read.depth[i],
    ]);
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
  Float32List readSpray({
    int capacity = c.shallowMostSpray,
    NativeShallowLiquid? of,
  }) => _readOfWater(capacity, c.sprayFloats, c.f3d_world_read_spray, of);

  /// Up to [capacity] pieces of [floats] reals each read by [read], and of
  /// them, when [of] is given, only the ones in that water.
  ///
  /// Into blocks kept between calls, grown as asked: a game that draws
  /// several waters reads every one of them a frame, and a block as large as
  /// the most the world can hold, made and freed each time, and a list per
  /// piece kept, were most of what drawing them cost.
  Float32List _readOfWater(
    int capacity,
    int floats,
    int Function(int, int, int, int) read,
    NativeShallowLiquid? of,
  ) {
    if (capacity * floats > _pieceRoom) {
      if (_pieceRoom > 0) {
        _pieces.free();
        _pieceWaters.free();
      }
      _pieceRoom = capacity * floats;
      _pieces = c.F32s.alloc(_pieceRoom);
      _pieceWaters = c.U32s.alloc(_pieceRoom);
    }
    final count = read(_live, _pieces, of == null ? 0 : _pieceWaters, capacity);
    final all = _pieces.copy(count * floats);
    if (of == null) return all;
    final waters = c.U8s(_pieceWaters).copy(count * 4).buffer.asUint32List();
    var kept = 0;
    for (var k = 0; k < count; k++) {
      if (waters[k] == of.id) kept++;
    }
    final mine = Float32List(kept * floats);
    var n = 0;
    for (var k = 0; k < count; k++) {
      if (waters[k] != of.id) continue;
      mine.setRange(n * floats, (n + 1) * floats, all, k * floats);
      n++;
    }
    return mine;
  }

  /// The blocks [_readOfWater] reads into, and how many floats they hold.
  c.F32s _pieces = const c.F32s(0);
  c.U32s _pieceWaters = const c.U32s(0);
  int _pieceRoom = 0;

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

  /// A motor on a revolute or prismatic link, driving it at [speed],
  /// rad/s or m/s, through each step with at most [force], N m or N; null
  /// [speed] takes it off. A motor of speed nought strong enough for its
  /// load holds the joint where it is. It knows no place: what pushes the
  /// joint past its force is not taken back. For that, [setLinkServo].
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

  /// A servo on a revolute or prismatic link: a spring of [stiffness],
  /// N m a radian or N/m, pulling the joint to a mark that starts at
  /// [target], radians or m, and moves at the link's motor's speed, with a
  /// damper of [damping] times critical for what the joint moves. The
  /// motor's force bounds it; with no motor it is unbounded. A load held
  /// still bends the joint load / [stiffness] off its mark. Null
  /// [stiffness] takes the servo off and leaves the motor. For a game whose
  /// arm, turret or crane must come back to where it was put after a knock,
  /// and give under a load as a real one does. Provisional.
  void setLinkServo(
    NativeMultibody multibody,
    int link, {
    double? stiffness,
    double target = 0.0,
    double damping = 1.0,
  }) {
    if (c.f3d_multibody_set_servo(
          _live,
          multibody.id,
          link,
          stiffness != null ? 1 : 0,
          target,
          stiffness ?? 1.0,
          damping,
        ) ==
        0) {
      throw ArgumentError(
        'a servo on link $link: not a revolute or prismatic link, a '
        'stiffness not above nought or a damping below nought',
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
  /// chassis up by its spring, along the road by its drive, its brake and
  /// its tyre's rolling resistance, and across it to hold it from sliding,
  /// together no more than its grip times the load allows; and pushes what
  /// it stands on back. The springs and dampers are solved together and
  /// implicitly: the chassis rings on them at the frequency and damping
  /// ratio its own mass gives, however light it is, and a damper far past
  /// critical brings it back slowly rather than throwing it.
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
  int addWheel(NativeVehicle vehicle, NativeWheelSettings wheel) {
    final w = c.F32s.alloc(c.wheelFloatsAll);
    try {
      w[0] = wheel.attach.x;
      w[1] = wheel.attach.y;
      w[2] = wheel.attach.z;
      w[3] = wheel.rest;
      w[4] = wheel.radius;
      w[5] = wheel.stiffness;
      w[6] = wheel.damping;
      w[7] = wheel.grip;
      w[8] = wheel.width ?? 0.0;
      w[9] = wheel.rollingResistance;
      final index = c.f3d_vehicle_add_wheel_with(
        _live,
        vehicle.id,
        w,
        c.wheelFloatsAll,
      );
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
            center: Vector3(
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

  /// The drag coefficient against the wind, no unit; nought takes the
  /// shape's own.
  ///
  /// **A shape's own is a constant, Newton's regime**: the air drags a body
  /// at Reynolds numbers in the thousands and up — a 10 cm ball at a metre a
  /// second is at 6 600 — where a sphere's coefficient has reached its
  /// plateau, and White's correlation (`sphereDrag`, which the liquids use)
  /// gives the same 0.47 there. A sphere 0.47, subcritical; a cube 1.05,
  /// face on; a cylinder 0.82, end on, at about twice its diameter long; a
  /// cone 0.5, point first (Hoerner, Fluid-Dynamic Drag, 1965, chapter 3 and
  /// its summary table); a capsule 0.6, an estimate for one met from any
  /// side — between a cylinder with hemispherical ends end on, about 0.4,
  /// and side on, nearer 0.8 at its usual length (Hoerner, chapter 3); a
  /// hull or a compound 1.0.
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
      material._write(m);
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

  /// Watts the fire gave off over the last step, past what its flame gave
  /// back to the body: the flame's radiant share of it leaves as
  /// radiation, the rest as the hot gas of its plume.
  double heatReleaseOf(NativeBody body) {
    _check(c.f3d_body_get_heat_release(_live, body.raw, _out), body);
    return _out[0];
  }

  /// The char a fire has left on [body]: the [share] of its surface under
  /// char, nought to one; how deep the char has grown at its deepest,
  /// [depth], m; and the char's surface [temperature], K — over its fire
  /// what the burning patch's heat balance gives it, elsewhere its
  /// surface's. Char stays when the fire goes out; wood that never burnt
  /// has none.
  ({double share, double depth, double temperature}) charOf(NativeBody body) {
    _check(
      c.f3d_body_get_char(
        _live,
        body.raw,
        _out,
        c.F32s(_out + 4),
        c.F32s(_out + 8),
      ),
      body,
    );
    return (share: _out[0], depth: _out[1], temperature: _out[2]);
  }

  /// What of [body] stands in a liquid, as the water's last step measured
  /// it: the m³ under its surface, and the id of the water
  /// ([NativeShallowLiquid.id]) it stands in, nought for none. The water
  /// holds it up by that volume times its density and gravity.
  ({double volume, int water}) submergedOf(NativeBody body) {
    final water = c.U32s.alloc(1);
    try {
      _check(c.f3d_body_get_submerged(_live, body.raw, _out, water), body);
      return (volume: _out[0], water: water[0]);
    } finally {
      water.free();
    }
  }

  /// A flame held to [body] at [at] through the next step: [flux], W/m²,
  /// over [area], m², from gas at [temperature], K — a match, a pilot
  /// flame, a blowtorch held to a crate. It heats the part nearest [at],
  /// and that spot catches in the time a thick solid takes to reach its
  /// ignition temperature under the flux, never if the flux is below what
  /// its surface loses there or the gas is cooler than it catches at. Held
  /// again each step while it is held.
  void holdFlame(
    NativeBody body,
    Vector3 at, {
    required double flux,
    required double area,
    required double temperature,
  }) {
    if (c.f3d_body_hold_flame(
          _live,
          body.raw,
          at.x,
          at.y,
          at.z,
          flux,
          area,
          temperature,
        ) ==
        0) {
      throw ArgumentError(
        'a flame of $flux W/m² over $area m² at $temperature K on $body',
      );
    }
  }

  /// [burner] burning on [body] from the next step, its flame standing over
  /// the whole body (a compound's first part) and heating it as its own
  /// fire would; null puts it out.
  void setBurner(NativeBody body, NativeBurner? burner) {
    if (burner == null) {
      _check(c.f3d_body_set_burner(_live, body.raw, 0, 0), body);
      return;
    }
    final m = c.coreAlloc(c.F3dMaterialLayout.size);
    try {
      burner.fuel._write(m);
      _check(
        c.f3d_body_set_burner(_live, body.raw, burner.rate, m),
        body,
        burner.rate,
      );
    } finally {
      c.coreFree(m);
    }
  }

  /// [explosion] going off at [at]: its products push each body in their
  /// way outwards by the share of their momentum its solid angle is, and
  /// warm it by the same share of the rest of the energy, as much as its
  /// emissivity takes; neither passes what stands between. How many bodies
  /// it reached.
  int explode(Vector3 at, NativeExplosion explosion) {
    if (!(explosion.energy > 0) || !(explosion.mass >= 0)) {
      throw ArgumentError.value(explosion.energy, 'energy', 'not above nought');
    }
    return c.f3d_world_explode(
      _live,
      at.x,
      at.y,
      at.z,
      explosion.energy,
      explosion.mass,
    );
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
