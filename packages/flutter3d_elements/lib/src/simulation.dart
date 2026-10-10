/// Water, fire and bodies in a world of the physics core's, stepped: the
/// game's objects followed into it, the flames held to its bodies, its
/// waters poured and fed, and every element's step — with no device, no
/// renderer and no scene.
///
/// What draws and sounds it is `Elements` in `flutter3d_effects`.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        EventRegistry,
        Flutter3dPlugin,
        LoopContext,
        LoopPhase,
        PluginApiVersion,
        PluginHost,
        PluginManifest,
        Registration,
        SnapshotPart,
        SnapshotRegistry;
import 'package:vector_math/vector_math.dart';

import 'element_events.dart';
import 'element_hook.dart';
import 'smoke_plume.dart';

/// What the elements tell a game as it happens, each callback optional.
///
/// **Called from `Elements.update`, in the order the core said them.** A
/// game that lets these change its run calls `update` from its fixed step
/// with the run's own events, and replays hold; the drawing's callbacks —
/// [budget], [seen], [lost] — are about what is drawn and must not change a
/// run.
///
/// **A thin adapter over the bus, when the game has one.** The engine's way
/// to hear the elements is its event bus: [ElementsListener.toBus] makes
/// the listener that publishes each callback as its typed event
/// ([ElementCaught], [ElementOut], [ElementBurntOut], [ElementWetted],
/// [ElementBurnerOut], [ElementExploded], [ElementsOverBudget],
/// [ElementFireSeen], [ElementFireLost]), and `Elements.listener` stays the
/// one field it is set on. A listener written with callbacks still works,
/// and is what a game without a bus keeps.
final class ElementsListener {
  /// Publishes every callback onto [bus] as its event: on the step channel
  /// when `Elements.update` runs inside a fixed step, on the frame channel
  /// otherwise.
  ///
  /// Declares the events it publishes on [bus] first
  /// ([declareElementEvents]), so the step channel has their codecs.
  factory ElementsListener.toBus(EventRegistry bus) {
    declareElementEvents(bus);
    return ElementsListener._toBus(bus);
  }

  factory ElementsListener._toBus(EventRegistry bus) => ElementsListener(
    caught: (body, made) => bus.publish(ElementCaught(body, made)),
    out: (body, made) => bus.publish(ElementOut(body, made)),
    burntOut: (body, made) => bus.publish(ElementBurntOut(body, made)),
    wetted: (body, made) => bus.publish(ElementWetted(body, made)),
    burnerOut: (body, made) => bus.publish(ElementBurnerOut(body, made)),
    exploded: (at, pushed) => bus.publish(ElementExploded(at, pushed)),
    budget: (step, wanted, holds) =>
        bus.publish(ElementsOverBudget(step, wanted, holds)),
    seen: (fire) => bus.publish(ElementFireSeen(fire)),
    lost: (body) => bus.publish(ElementFireLost(body)),
  );

  const ElementsListener({
    this.caught,
    this.out,
    this.burntOut,
    this.wetted,
    this.burnerOut,
    this.exploded,
    this.budget,
    this.seen,
    this.lost,
  });

  /// A body caught fire; its [TrackedBody] when the elements made it.
  final void Function(NativeBody body, TrackedBody? made)? caught;

  /// A body's fire went out with fuel left: drowned, doused, or burnt down
  /// below its firepoint.
  final void Function(NativeBody body, TrackedBody? made)? out;

  /// A body burnt all its fuel.
  final void Function(NativeBody body, TrackedBody? made)? burntOut;

  /// A body went into a liquid: a splash.
  final void Function(NativeBody body, TrackedBody? made)? wetted;

  /// A burner went out, under a liquid.
  final void Function(NativeBody body, TrackedBody? made)? burnerOut;

  /// A charge went off at a point, pushing as many bodies.
  final void Function(Vector3 at, int pushed)? exploded;

  /// A step of the drawing wanted more than it can hold this frame, and
  /// drew less: which ('flames', 'smoke', 'embers', 'drops', 'bubbles'),
  /// how many it wanted, and how many it holds.
  final void Function(String step, int wanted, int holds)? budget;

  /// A fire came into the camera's picture, or left it — when
  /// `Elements.update` is given the camera.
  final void Function(NativeFire fire)? seen;
  final void Function(NativeBody body)? lost;
}

/// The ground under a water: [nx] × [nz] cells [cell] m square, the first
/// cell's corner at [origin], and each cell's ground over the origin's
/// height, x fastest.
final class ElementHeightfield {
  ElementHeightfield.list({
    required this.origin,
    required this.cell,
    required this.nx,
    required this.nz,
    required List<double> heights,
  }) : heights = List<double>.unmodifiable(heights) {
    if (heights.length != nx * nz) {
      throw ArgumentError.value(heights.length, 'heights', 'not $nx × $nz');
    }
  }

  /// Each cell's ground where [heightAt] says it is at the cell's middle, in
  /// the world: what a game's terrain gives, sampled.
  factory ElementHeightfield.sampled({
    required Vector3 origin,
    required double cell,
    required int nx,
    required int nz,
    required double Function(double x, double z) heightAt,
  }) => ElementHeightfield.list(
    origin: origin,
    cell: cell,
    nx: nx,
    nz: nz,
    heights: <double>[
      for (var j = 0; j < nz; j++)
        for (var i = 0; i < nx; i++)
          heightAt(origin.x + (i + 0.5) * cell, origin.z + (j + 0.5) * cell) -
              origin.y,
    ],
  );

  /// Level ground at the origin's height: a tank, a flooded floor.
  factory ElementHeightfield.flat({
    required Vector3 origin,
    required double cell,
    required int nx,
    required int nz,
  }) => ElementHeightfield.list(
    origin: origin,
    cell: cell,
    nx: nx,
    nz: nz,
    heights: List<double>.filled(nx * nz, 0.0),
  );

  final Vector3 origin;

  /// The side of a cell, in metres.
  final double cell;
  final int nx, nz;
  final List<double> heights;
}

/// What a water's bed holds it back with: Manning's roughness [roughness],
/// s/m^(1/3).
final class Bed {
  const Bed({required this.roughness});

  /// Normal values of Manning's n (Chow, Open-Channel Hydraulics, 1959,
  /// table 5-6): a clean straight natural stream, a mountain stream over
  /// gravel and cobbles, a straight clean earth channel, troweled concrete.
  /// Each in seconds per cube root of a metre, s/m^(1/3).
  ///
  /// A clean straight natural stream, in seconds per cube root of a metre.
  static const double naturalStream = 0.030;

  /// A mountain stream over gravel and cobbles, in seconds per cube root of
  /// a metre.
  static const double mountainStream = 0.040;

  /// A straight clean earth channel, in seconds per cube root of a metre.
  static const double earthChannel = 0.018;

  /// Troweled concrete, in seconds per cube root of a metre.
  static const double concrete = 0.013;

  /// Manning's n, in seconds per cube root of a metre.
  final double roughness;
}

/// A solid a game puts in the world: what it is shaped as, what it is made
/// of, and how dense it is, kg/m³ — its mass is that over its volume.
final class Solid {
  const Solid._(
    this.shape,
    this.volume,
    this.material,
    this.density, {
    this.parts,
    this.rounding = 0.0,
  });

  /// Several shapes as one body — a raft of logs, a cart, a beam cut in
  /// parts that each burn: its volume theirs summed. Parts that are hulls
  /// are not measured here; give their shapes instead.
  factory Solid.compound(
    List<NativeCompoundPart> parts, {
    required NativeMaterial material,
    required double density,
  }) {
    var volume = 0.0;
    for (final part in parts) {
      final shape = part.shape;
      if (shape == null) {
        throw ArgumentError.value(part, 'parts', 'a hull, not measured');
      }
      volume += _volumeOf(shape);
    }
    return Solid._(
      NativeShape.point,
      volume,
      material,
      density,
      parts: List<NativeCompoundPart>.unmodifiable(parts),
    );
  }

  /// m³ of [shape], as each constructor below measures its own.
  static double _volumeOf(NativeShape shape) {
    final a = shape.first, b = shape.second, c = shape.third;
    final box = NativeShape.box(Vector3(1, 1, 1)).kind;
    return switch (shape.kind) {
      _ when shape.kind == box => 8.0 * a * b * c,
      _ when shape.kind == const NativeShape.sphere(1).kind =>
        4.0 / 3.0 * math.pi * a * a * a,
      _ when shape.kind == const NativeShape.cylinder(1, 1).kind =>
        math.pi * a * a * 2.0 * b,
      _ when shape.kind == const NativeShape.capsule(1, 1).kind =>
        math.pi * a * a * (2.0 * b + 4.0 / 3.0 * a),
      _ when shape.kind == const NativeShape.cone(1, 1).kind =>
        math.pi * a * a * b / 3.0,
      _ => 0.0,
    };
  }

  Solid.box(
    Vector3 half, {
    required NativeMaterial material,
    required double density,
  }) : this._(
         NativeShape.box(half),
         8.0 * half.x * half.y * half.z,
         material,
         density,
       );

  Solid.sphere(
    double radius, {
    required NativeMaterial material,
    required double density,
  }) : this._(
         NativeShape.sphere(radius),
         4.0 / 3.0 * math.pi * radius * radius * radius,
         material,
         density,
       );

  /// Upright along its y, [halfHeight] each way from its middle.
  Solid.cylinder(
    double radius,
    double halfHeight, {
    required NativeMaterial material,
    required double density,
  }) : this._(
         NativeShape.cylinder(radius, halfHeight),
         math.pi * radius * radius * 2.0 * halfHeight,
         material,
         density,
       );

  /// Upright along its y: a cylinder [halfLength] each way, capped by
  /// hemispheres of [radius].
  Solid.capsule(
    double radius,
    double halfLength, {
    required NativeMaterial material,
    required double density,
  }) : this._(
         NativeShape.capsule(radius, halfLength),
         math.pi * radius * radius * (2.0 * halfLength + 4.0 / 3.0 * radius),
         material,
         density,
       );

  final NativeShape shape;

  /// A compound's parts; null for one shape.
  final List<NativeCompoundPart>? parts;

  /// How far its shape is rounded out, in metres: a crate's worn edges. Its volume
  /// counts the rounding.
  final double rounding;

  /// This solid with its shape rounded out by [radius].
  ///
  /// The shape grown by a ball of [radius] holds, by Steiner's formula,
  /// V + S·r + M·r² + (4/3)πr³, M the integral of its mean curvature: a
  /// box's π times its three edges summed, a cylinder's π(H + πR); a ball
  /// or a capsule grows by r all round. A compound's parts are rounded
  /// each; its volume is theirs grown so.
  Solid rounded(double radius) {
    if (!(radius >= 0)) throw ArgumentError.value(radius, 'radius');
    final parts = this.parts;
    final grown = parts == null
        ? _grown(shape, radius)
        : parts.fold(0.0, (sum, p) => sum + _grown(p.shape!, radius));
    return Solid._(
      shape,
      grown,
      material,
      density,
      parts: parts,
      rounding: radius,
    );
  }

  /// m³ of [shape] grown by a ball of [r].
  static double _grown(NativeShape shape, double r) {
    final a = shape.first, b = shape.second, c = shape.third;
    const ball = 4.0 / 3.0 * math.pi;
    if (shape.kind == const NativeShape.sphere(1).kind) {
      return ball * (a + r) * (a + r) * (a + r);
    }
    if (shape.kind == const NativeShape.capsule(1, 1).kind) {
      return math.pi * (a + r) * (a + r) * (2.0 * b + 4.0 / 3.0 * (a + r));
    }
    if (shape.kind == NativeShape.box(Vector3(1, 1, 1)).kind) {
      final (x, y, z) = (2 * a, 2 * b, 2 * c);
      return x * y * z +
          2.0 * (x * y + y * z + x * z) * r +
          math.pi * (x + y + z) * r * r +
          ball * r * r * r;
    }
    if (shape.kind == const NativeShape.cylinder(1, 1).kind) {
      final h = 2 * b;
      return math.pi * a * a * h +
          (2.0 * math.pi * a * h + 2.0 * math.pi * a * a) * r +
          math.pi * (h + math.pi * a) * r * r +
          ball * r * r * r;
    }
    throw ArgumentError.value(shape, 'shape', 'not measured when rounded');
  }

  /// Its volume, in cubic metres.
  final double volume;
  final NativeMaterial material;

  /// kg/m³.
  final double density;

  /// Its mass, in kilograms.
  double get mass => volume * density;
}

/// Where something is and how it is turned.
///
/// **[position] is origin-local**: single precision, relative to the
/// elements' world origin (the physics world's `origin`), as every `Vector3`
/// position in this library is. A place held in double precision is a
/// `WorldPosition`, narrowed against that origin before it comes here.
typedef ElementPose = ({Vector3 position, Quaternion orientation});

/// A body in the elements' world, taken in: what the [ElementsListener]'s
/// callbacks name.
///
/// **It holds nothing that draws it.** The look a view keeps on it is the
/// view's (`Elements.lookOf` in `flutter3d_effects`), so a server that
/// steps the elements holds no scene node.
final class TrackedBody {
  TrackedBody._(this.native);

  /// The core's body: for what `Elements` does not say.
  final NativeBody native;
}

/// A game object the elements' world follows: a body the world is told
/// where to be, which pushes water and what it meets there, and which
/// nothing in the world ever moves back — so a replay of the game is the
/// game's alone.
final class Follower {
  Follower._(this.native, this._pose);

  /// The core's kinematic body.
  final NativeBody native;
  final ElementPose Function() _pose;
  bool _jumps = false;

  /// At the next `Elements.update` it is put where the game has it rather
  /// than carried there: a respawn, a level change, a teleport, which would
  /// otherwise sweep through everything between at a great speed.
  void jump() => _jumps = true;
}

/// A flame held to a body to light it: [flux], W/m², over [area], m², from
/// gas at [temperature], K, for [seconds].
///
/// The presets are flames that were measured; where a number was not,
/// `doc/igniters.md` says how it was had.
final class Igniter {
  const Igniter({
    required this.flux,
    required this.area,
    required this.temperature,
    required this.seconds,
  });

  /// A wooden match laid against it: 18 to 20 kW/m² from its flame of
  /// 80 W, over about 10 by 30 mm (Babrauskas and Krasny, NBS Monograph
  /// 173, 1985, table 6A and §4.2.1); for 20 s, the least it burns and how
  /// long BS 5852 holds the butane flame that stands in for it (idem,
  /// tables 3 and 6A). Its gas is that butane diffusion flame's, 1930 K at
  /// its hottest (Williamson, University of Maryland, 2003, table 2).
  static const Igniter match = Igniter(
    flux: 19e3,
    area: 3.0e-4,
    temperature: 1930.0,
    seconds: 20.0,
  );

  /// A cigarette lighter's flame: 63 kW/m² at its tip, falling to half
  /// within 10.5 mm of its axis, from gas at 1930 K (Williamson, table 2
  /// and figure 20); held as long as a match.
  static const Igniter lighter = Igniter(
    flux: 63e3,
    area: 3.5e-4,
    temperature: 1930.0,
    seconds: 20.0,
  );

  /// A propane torch as aircraft parts are fire-tested with: 2000 °F at the
  /// part, at least 9.3 Btu/(ft² s), 105.6 kW/m², over about 5 by 5
  /// inches, for the 5 minutes "fire resistant" asks (FAA AC 20-135, §4 and
  /// §6).
  static const Igniter propaneTorch = Igniter(
    flux: 105.6e3,
    area: 0.0161,
    temperature: 1366.5,
    seconds: 300.0,
  );

  /// A pilot flame, as the OSU heat release apparatus keeps lit through
  /// its 5 minute test: 120 cm³/min of methane premixed with air, 72 W,
  /// about a match's (FAA DOT/FAA/AR-00/12, §5.3.8.1 and §5.7.8). Its flux
  /// a match's and its area a match's in proportion to its heat, as small
  /// flames differ in the area they heat, not the flux (NBS Monograph 173,
  /// §4.2.1); its gas no cooler than the FAA asks a premixed burner's flame
  /// to be, 1550 °F (DOT/FAA/AR-00/12, chapter 1).
  static const Igniter pilot = Igniter(
    flux: 19e3,
    area: 2.7e-4,
    temperature: 1116.5,
    seconds: 300.0,
  );

  final double flux, area, temperature, seconds;

  /// This flame with the values given changed: a torch held for half a
  /// minute, say.
  Igniter copyWith({
    double? flux,
    double? area,
    double? temperature,
    double? seconds,
  }) => Igniter(
    flux: flux ?? this.flux,
    area: area ?? this.area,
    temperature: temperature ?? this.temperature,
    seconds: seconds ?? this.seconds,
  );
}

/// A water in the elements' world: the core's liquid, the ground under it,
/// and what pours into it and drains out.
///
/// **It holds nothing that draws it.** Its view and the look its surface is
/// drawn with are the view's (`Elements.viewOf` and `Elements.waterLookOf`
/// in `flutter3d_effects`), which reads [ground] again when it changes.
final class WaterBody {
  WaterBody._(this._world, this.native, this._ground);

  final NativeWorld _world;

  /// The core's liquid: for what this does not say.
  final NativeShallowLiquid native;

  /// The ground it stands on.
  ElementHeightfield get ground => _ground;
  ElementHeightfield _ground;

  /// The ground dug or built up under it: the water over each cell stays as
  /// deep, and a view draws the new bed from [ground].
  void setGround(List<double> heights) {
    _ground = ElementHeightfield.list(
      origin: _ground.origin,
      cell: _ground.cell,
      nx: _ground.nx,
      nz: _ground.nz,
      heights: heights,
    );
    _world.setShallowGround(native, heights);
  }

  /// [volume] m³ poured in at [at], over a disc of [radius]: a bucket, a
  /// burst pipe; taken out where it is negative, as far as there is water.
  void pour(Vector3 at, {required double volume, double radius = 0.0}) => _world
      .pourShallowLiquid(native, at.x, at.z, radius: radius, volume: volume);

  int _springs = 0, _outlets = 0;
  final Map<int, ({Vector3 at, double radius})> _springsAt =
      <int, ({Vector3 at, double radius})>{};

  /// Every cell between [from] and [to], seen from above, filled or drained
  /// to [level], a height in the world: a tank, a flooded hall.
  void fill({
    required Vector3 from,
    required Vector3 to,
    required double level,
  }) => _world.fillShallowLiquid(
    native,
    x0: from.x,
    z0: from.z,
    x1: to.x,
    z1: to.z,
    level: level - _ground.origin.y,
  );

  /// The basin [from] is in filled to [level], a height in the world: a
  /// lagoon to its rim, not the sea past the ridge. How many cells filled.
  int fillBasin({required Vector3 from, required double level}) =>
      _world.fillShallowBasin(
        native,
        x: from.x,
        z: from.z,
        level: level - _ground.origin.y,
      );

  /// A spring welling up [discharge] m³/s at [at], over a disc of [radius];
  /// its index.
  int addSpring({
    required Vector3 at,
    required double discharge,
    double radius = 0.0,
  }) {
    final index = _springs++;
    _springsAt[index] = (at: at, radius: radius);
    _world.setShallowSource(
      native,
      index,
      x: at.x,
      z: at.z,
      radius: radius,
      rate: discharge,
    );
    return index;
  }

  /// Spring [index] welling up [discharge] m³/s from now on — a volcano
  /// waking, a sluice opened upstream; nought stops it.
  void setSpring(int index, {required double discharge}) {
    final s = _springsAt[index];
    if (s == null) throw ArgumentError.value(index, 'index', 'no such spring');
    _world.setShallowSource(
      native,
      index,
      x: s.at.x,
      z: s.at.z,
      radius: s.radius,
      rate: discharge,
    );
  }

  /// [outlet] letting water out, its crest or invert a height over the
  /// water's origin; its index. For a game whose water is only drawn and
  /// heard, which holds a pond at a weir or empties it down a drain here;
  /// the games whose runs depend on their water set outlets on the world
  /// they step themselves.
  int addOutlet(NativeOutlet outlet) {
    final index = _outlets++;
    _world.setShallowOutlet(native, index, outlet);
    return index;
  }

  /// What [side] of its grid is.
  void setEdge(GridSide side, NativeEdgeFlow edge) =>
      _world.setShallowEdge(native, side, edge);

  /// Which cells are walls, x fastest.
  void setWalls(List<bool> walls) => _world.setShallowWalls(native, walls);

  /// Each cell's own Manning roughness, x fastest: for a game that paints
  /// its bed from its terrain's materials, a stony reach in a sandy river or
  /// weed along a bank, where one [Bed] for the whole water is too coarse.
  void setRoughness(List<double> roughness) =>
      _world.setShallowRoughness(native, roughness);

  /// The water at [at], or null off its grid.
  NativeShallowSample? sample(Vector3 at) =>
      _world.sampleShallow(native, at.x, at.z);
}

/// The fires of the elements' world.
final class Fires {
  Fires._(this._elements);

  final ElementsSimulation _elements;
  final List<({NativeBody body, Vector3 at, Igniter by, double left})> _held =
      <({NativeBody body, Vector3 at, Igniter by, double left})>[];

  /// [by] held to [body] at [at] — its middle when not given — until it has
  /// been held its time: the body catches when the flux has brought its
  /// surface there, or not at all.
  void ignite(TrackedBody body, {required Igniter by, Vector3? at}) =>
      _held.add((
        body: body.native,
        at: at ?? _elements.world.localPositionOf(body.native),
        by: by,
        left: by.seconds,
      ));

  /// [burner] burning on [body]; null puts it out.
  void setBurner(TrackedBody body, NativeBurner? burner) =>
      _elements.world.setBurner(body.native, burner);

  /// A charge going off at [at]; how many bodies it reached.
  int explode(Vector3 at, NativeExplosion explosion) {
    final pushed = _elements.world.explode(at, explosion);
    _elements.listener?.exploded?.call(at.clone(), pushed);
    return pushed;
  }

  /// [kilograms] of water thrown on [body].
  void douse(TrackedBody body, double kilograms) =>
      _elements.world.addWater(body.native, kilograms);

  /// The flames held this step, and their time run down.
  void _hold(double dt) {
    final world = _elements.world;
    for (var k = _held.length - 1; k >= 0; k--) {
      final h = _held[k];
      if (h.left <= 0 || !world.contains(h.body)) {
        _held.removeAt(k);
        continue;
      }
      world.holdFlame(
        h.body,
        h.at,
        flux: h.by.flux,
        area: h.by.area,
        temperature: h.by.temperature,
      );
      _held[k] = (body: h.body, at: h.at, by: h.by, left: h.left - dt);
    }
  }

  /// The flames still held, as a value JSON can hold: the fire element's
  /// part of a snapshot. Null when none is.
  Object? _save() => _held.isEmpty
      ? null
      : <Object?>[
          for (final h in _held)
            <String, Object?>{
              'body': h.body.raw,
              'at': <double>[h.at.x, h.at.y, h.at.z],
              'flux': h.by.flux,
              'area': h.by.area,
              'temperature': h.by.temperature,
              'seconds': h.by.seconds,
              'left': h.left,
            },
        ];

  /// The flames [_save] gave held again; anything else holds none.
  void _restore(Object? saved) {
    _held.clear();
    if (saved is! List<Object?>) return;
    for (final h in saved) {
      if (h case {
        'body': final int body,
        'at': [final num x, final num y, final num z],
        'flux': final num flux,
        'area': final num area,
        'temperature': final num temperature,
        'seconds': final num seconds,
        'left': final num left,
      }) {
        _held.add((
          body: NativeBody(body),
          at: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
          by: Igniter(
            flux: flux.toDouble(),
            area: area.toDouble(),
            temperature: temperature.toDouble(),
            seconds: seconds.toDouble(),
          ),
          left: left.toDouble(),
        ));
      }
    }
  }
}

/// Fire as an element's step: the flames held to bodies, run down a step at
/// a time, and kept in a snapshot. Its view is the fire view of `Elements`.
final class _FireStep extends ElementHook {
  _FireStep(this._simulation);

  final ElementsSimulation _simulation;

  @override
  String get id => 'fire';

  @override
  void step(ElementStep step) => _simulation.fires._hold(step.dt);

  @override
  Object? save() => _simulation.fires._save();

  @override
  void restore(Object? saved) => _simulation.fires._restore(saved);
}

/// Water as an element's step: the core's own, in the world's step, so it
/// steps nothing of its own here. Held so the order — water, fire, then a
/// plugin's — is the one the elements always stepped in.
final class _WaterStep extends ElementHook {
  const _WaterStep();

  @override
  String get id => 'water';
}

/// The elements' simulation: a world of the physics core's, the flames held
/// to its bodies, its waters, the game's objects followed into it, and every
/// element's step — **with no device, no renderer and no scene.**
///
/// The half a replay, a server and a headless test hold (item 19 of
/// `tasks/1.0-scope-additions.md`). `Elements` is the other half: it draws
/// and sounds what this stepped, over an [ElementsSimulation] of its own or
/// one handed to it (`Elements.over`). In a loop, [ElementsSimulationPlugin]
/// steps this in the `elements` phase and `ElementsViewPlugin` draws it in
/// the frame.
///
/// Elements step over [fields], the backend-neutral [ElementFields]; this
/// world's are the core's ([NativeElementFields]).
final class ElementsSimulation {
  ElementsSimulation._(this.world, {required this.steps}) {
    fires = Fires._(this);
    _hooks
      ..add(const _WaterStep())
      ..add(_FireStep(this));
  }

  /// A world of its own, which [step] steps.
  factory ElementsSimulation.open() =>
      ElementsSimulation._(NativeWorld(), steps: true);

  /// [world], which the game steps itself: followed and its elements
  /// stepped, the world itself not.
  factory ElementsSimulation.adopt(NativeWorld world) =>
      ElementsSimulation._(world, steps: false);

  /// The core's world: what this does not say, the game reaches through.
  final NativeWorld world;

  /// Whether [step] steps [world]; not for one adopted.
  final bool steps;

  /// The fires, and what lights and puts them out.
  late final Fires fires;

  /// What the elements tell the game ([ElementsListener]); null for none.
  ElementsListener? listener;

  /// The fields every element steps over.
  late final ElementFields fields = NativeElementFields(world);

  final List<ElementHook> _hooks = <ElementHook>[];
  final List<TrackedBody> _bodies = <TrackedBody>[];
  final List<Follower> _followers = <Follower>[];
  final List<WaterBody> _waters = <WaterBody>[];

  /// Every element stepped, water and fire first, in the order they step.
  List<ElementHook> get elements => List<ElementHook>.unmodifiable(_hooks);

  /// The events of the last [step].
  List<NativeEvent> events = const <NativeEvent>[];

  /// Seconds stepped, summed.
  double get clock => _clock;
  double _clock = 0.0;

  /// Adds a plugin element, stepped after fire and water, before the world.
  /// Throws an [ArgumentError] for an id already held.
  Registration addElement(ElementHook hook) {
    for (final h in _hooks) {
      if (h.id == hook.id) {
        throw ArgumentError.value(
          hook.id,
          'hook',
          'the elements already hold an element "${hook.id}"',
        );
      }
    }
    _hooks.add(hook);
    return Registration(() => _hooks.remove(hook));
  }

  /// Every element's own state, by id, as a value JSON can hold: what the
  /// world's snapshot does not carry — the flames still held, a plugin
  /// element's fields. Saved beside `world.snapshot()`.
  Map<String, Object?> saveElements() => <String, Object?>{
    for (final h in _hooks)
      if (h.save() case final Object saved) h.id: saved,
  };

  /// Each element back to what [saveElements] gave; an element not in it
  /// is restored from nothing.
  void restoreElements(Map<String, Object?> saved) {
    for (final h in _hooks) {
      h.restore(saved[h.id]);
    }
  }

  /// The elements' own state as a [SnapshotPart], under [id]: what an
  /// `EngineLoop`'s snapshots capture beside the world, so a rewind and the
  /// double-step check cover the flames held and a plugin element's fields.
  SnapshotPart snapshotPart({String id = 'elements'}) => SnapshotPart.of(
    id: id,
    capture: saveElements,
    restore: (data, _) => restoreElements(switch (data) {
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => const <String, Object?>{},
    }),
  );

  EventRegistry? _bus;

  /// Publishes the world's events onto [bus] from now on, as
  /// [ElementEvent]s, each [step] after the step that raised them, with the
  /// events the elements' steps publish themselves. Cancelled by the
  /// registration.
  Registration publishTo(EventRegistry bus) {
    declareElementEvents(bus);
    _bus = bus;
    return Registration(() {
      if (identical(_bus, bus)) _bus = null;
    });
  }

  void _publish(ElementEvent event) => _bus?.publish(event);

  /// [solid] at [at], turned [turn], moving at [velocity] and spinning at
  /// [spin]: dynamic, or [type]. [friction] and [restitution] as the core
  /// takes them, and what it collides with by [layer] and [mask]. The core's
  /// body; [track] it to be told about it by [listener].
  NativeBody addBody(
    Solid solid, {
    required Vector3 at,
    Quaternion? turn,
    Vector3? velocity,
    Vector3? spin,
    NativeBodyType type = NativeBodyType.dynamic,
    double? friction,
    double? restitution,
    ({int layer, int mask})? collides,
  }) {
    final native = world.addBody(position: at, type: type, mass: solid.mass);
    final parts = solid.parts;
    if (parts != null) {
      world.setCompound(native, world.createCompound(parts));
    } else {
      world.setShape(native, solid.shape);
    }
    world.setMaterial(native, solid.material);
    if (solid.rounding > 0) world.setRounding(native, solid.rounding);
    if (turn != null) world.setOrientation(native, turn);
    if (velocity != null) world.setVelocity(native, velocity);
    if (spin != null) world.setAngularVelocity(native, spin);
    if (friction != null) world.setFriction(native, friction);
    if (restitution != null) world.setRestitution(native, restitution);
    if (collides != null) {
      world.setCollisionFilter(
        native,
        layer: collides.layer,
        mask: collides.mask,
      );
    }
    return native;
  }

  /// A body made through [world] taken in: what the [listener]'s callbacks
  /// name. A view that draws it keeps its look itself
  /// (`Elements.track` in `flutter3d_effects`).
  TrackedBody track(NativeBody native) {
    final body = TrackedBody._(native);
    _bodies.add(body);
    return body;
  }

  /// The bodies taken in, in the order they were.
  List<TrackedBody> get bodies => List<TrackedBody>.unmodifiable(_bodies);

  /// A water of [properties] at [heat] over [ground], held back by [bed]:
  /// the core's shallow liquid, which the world steps. `Elements.addWater`
  /// in `flutter3d_effects` pours one through here and draws it.
  WaterBody addWater({
    required ElementHeightfield ground,
    required NativeLiquidProperties properties,
    required NativeLiquidHeat heat,
    required Bed bed,
  }) {
    final native = world.createShallowLiquid(
      nx: ground.nx,
      nz: ground.nz,
      cell: ground.cell,
      origin: ground.origin,
      ground: ground.heights,
    );
    world
      ..setShallowProperties(native, properties)
      ..setShallowHeat(native, heat)
      ..setShallowBed(native, roughness: bed.roughness);
    final water = WaterBody._(world, native, ground);
    _waters.add(water);
    return water;
  }

  /// The waters poured, in the order they were.
  List<WaterBody> get waters => List<WaterBody>.unmodifiable(_waters);

  /// What water stands at [at], and which: its surface, depth and flow
  /// there, from the first water that holds it; null over none.
  ({WaterBody water, NativeShallowSample sample})? waterAt(Vector3 at) {
    for (final w in _waters) {
      final s = w.sample(at);
      if (s != null && s.depth > 0.0) return (water: w, sample: s);
    }
    return null;
  }

  /// A game object followed into the world as [shape]: where [pose] says,
  /// each [step], it is carried to over the step, and pushes what it meets
  /// there; nothing there moves it back.
  Follower follow(
    ElementPose Function() pose, {
    required NativeShape shape,
    ({int layer, int mask})? collides,
  }) {
    final p = pose();
    final native = world.addBody(
      position: p.position,
      type: NativeBodyType.kinematic,
    );
    world
      ..setShape(native, shape)
      ..setOrientation(native, p.orientation);
    if (collides != null) {
      world.setCollisionFilter(
        native,
        layer: collides.layer,
        mask: collides.mask,
      );
    }
    final follower = Follower._(native, pose);
    _followers.add(follower);
    return follower;
  }

  /// A [TrackedBody], a [Follower] or a [WaterBody] taken out; anything
  /// else is not this half's.
  void remove(Object thing) {
    switch (thing) {
      case TrackedBody(:final native):
        _bodies.remove(thing);
        if (world.contains(native)) world.removeBody(native);
      case Follower(:final native):
        _followers.remove(thing);
        world.removeBody(native);
      case WaterBody(:final native):
        _waters.remove(thing);
        world.removeShallowLiquid(native);
    }
  }

  /// [dt] seconds on: the followers carried to where the game has them, every
  /// element's step — water, fire, then a plugin's — the world stepped
  /// (unless it was adopted), and its events read, published and told. A
  /// game stepping a world it adopted, which reads the world's events itself,
  /// hands them in as [events].
  ///
  /// [step] and [resimulated] are what an element's step is told; a loop
  /// passes its own.
  void step(
    double dt, {
    List<NativeEvent>? events,
    int step = 0,
    bool resimulated = false,
  }) {
    if (dt <= 0) return;
    _clock += dt;
    for (final f in _followers) {
      final p = f._pose();
      if (f._jumps) {
        f._jumps = false;
        world
          ..setPosition(f.native, p.position)
          ..setOrientation(f.native, p.orientation)
          ..setVelocity(f.native, Vector3.zero())
          ..setAngularVelocity(f.native, Vector3.zero());
      } else {
        world.moveKinematic(f.native, p.position, p.orientation, dt);
      }
    }
    final told = ElementStep(
      fields: fields,
      dt: dt,
      step: step,
      resimulated: resimulated,
      publish: _publish,
    );
    for (final h in List.of(_hooks)) {
      h.step(told);
    }
    if (steps) world.step(dt);
    this.events = events ?? world.readEvents();
    final bus = _bus;
    if (bus != null) {
      for (final e in this.events) {
        bus.publish(ElementEvent(kind: e.kind, body: e.body, other: e.other));
      }
    }
    _tell(this.events);
  }

  void _tell(List<NativeEvent> events) {
    final l = listener;
    if (l == null) return;
    for (final e in events) {
      final made = _madeOf(e.body);
      final call = switch (e.kind) {
        NativeEventKind.ignited => l.caught,
        NativeEventKind.extinguished => l.out,
        NativeEventKind.burntOut => l.burntOut,
        NativeEventKind.wetted => l.wetted,
        NativeEventKind.burnerOut => l.burnerOut,
        _ => null,
      };
      call?.call(e.body, made);
    }
  }

  TrackedBody? _madeOf(NativeBody body) {
    for (final b in _bodies) {
      if (b.native == body) return b;
    }
    return null;
  }

  /// W/m² of radiant heat at [at] from every fire: each one Modak's point
  /// source at the middle of its flame, its radiant share of its heat
  /// spread over a sphere, χ_r·Q / (4πR²) (Combustion and Flame 29, 1977),
  /// and never more than its soot gives off, σT⁴, however close. What a
  /// game's character standing at [at] is heated by: [FireExposure.fluxAt]
  /// over the world's fires.
  double heatFluxAt(Vector3 at) => FireExposure.fluxAt(world.fires(), at);

  /// The share of light that gets from [from] to [to] through the fires'
  /// smoke: e^(−Στ), each plume crossed a cylinder about its axis as wide
  /// as it is at the height the line passes it, its optical depth across
  /// (`doc/smoke_plume.md`, [SmokePlume.depth]) taken in proportion to
  /// the chord the line cuts through it. What a game's watcher asks before
  /// it sees through smoke.
  double seenThroughSmoke(Vector3 from, Vector3 to) {
    var tau = 0.0;
    for (final f in world.fires()) {
      final kw = f.power / 1000.0;
      if (!(kw > 0.0)) continue;
      final base = math.max(f.base, 0.01);
      final tip = math.max(f.reach, base);
      // The line's nearest approach to the plume's axis, over the flame.
      final d = to - from;
      final flat = Vector2(d.x, d.z);
      final off = Vector2(f.at.x - from.x, f.at.z - from.z);
      final along = flat.length2 > 0.0
          ? (off.dot(flat) / flat.length2).clamp(0.0, 1.0)
          : 0.0;
      final p = from + d * along;
      final z = p.y - f.at.y;
      if (z < tip) continue;
      final b = math.max(
        0.12 * (z - (0.083 * Portable.pow(kw, 0.4) - 1.02 * base)),
        0.5 * base,
      );
      final miss = math.sqrt(
        (p.x - f.at.x) * (p.x - f.at.x) + (p.z - f.at.z) * (p.z - f.at.z),
      );
      if (miss >= b) continue;
      final chord = 2.0 * math.sqrt(b * b - miss * miss);
      tau +=
          SmokePlume.depth(kw, base, z, sootYield: f.sootYield) *
          chord /
          (2.0 * b);
    }
    return Portable.exp(-tau);
  }

  /// Everything taken out, and a world of its own let go.
  void dispose() {
    if (steps) world.dispose();
  }
}

/// An [ElementsSimulation] as a plugin: stepped in the engine's `elements`
/// phase, its own state a part of the loop's snapshots.
///
/// The simulation half of the elements in a loop; `ElementsViewPlugin` draws
/// it. A server replaying a run installs this one alone.
final class ElementsSimulationPlugin extends Flutter3dPlugin {
  ElementsSimulationPlugin(this.simulation, {this.id = 'elements'});

  final ElementsSimulation simulation;
  final String id;

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: PluginApiVersion.current,
    description: 'water, fire and bodies, stepped in the elements phase',
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem(
      '$id.step',
      LoopPhase.fields,
      (LoopContext context) => simulation.step(
        context.dt,
        step: context.step,
        resimulated: context.isResimulated,
      ),
    );
    host.maybeRegistry<SnapshotRegistry>()?.add(
      simulation.snapshotPart(id: id),
    );
    simulation.publishTo(host.events);
  }
}
