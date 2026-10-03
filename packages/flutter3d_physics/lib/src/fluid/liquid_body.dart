import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'capillary.dart';
import 'fluid_medium.dart';
import 'free_surface.dart';
import 'jet.dart';
import 'liquid_layer.dart';
import 'outflow.dart';
import 'vessel_shape.dart';

/// What ran over a vessel's lip in one step, in the world.
final class Spill {
  const Spill({
    required this.flow,
    required this.point,
    required this.velocity,
    required this.width,
    required this.medium,
    this.concentrations = const {},
  });

  /// No spill.
  static final Spill none = Spill(
    flow: 0.0,
    point: Vector3.zero(),
    velocity: Vector3.zero(),
    width: 0.0,
    medium: FluidMedium.water,
  );

  /// Which liquid ran out — the top layer's — and what was dissolved in it.
  final FluidMedium medium;
  final Map<String, double> concentrations;

  /// Cubic metres a second.
  final double flow;

  /// Where along the lip it left, weighed by how much left each part.
  final Vector3 point;

  /// How it left: at the crest's speed, along the glass and outwards.
  final Vector3 velocity;

  /// How wide the sheet over the lip is.
  final double width;
}

/// A liquid in a vessel: its volume, the plane its surface settles to, the
/// waves on it, and what runs over the lip.
///
/// **The surface settles square to the gravity the liquid feels**, which is
/// the world's gravity less the vessel's own acceleration: a glass carried
/// forward and braked tips its liquid as much as one turned. The vessel's
/// acceleration is taken from where it was put on the last three steps.
/// Where the plane stands follows from the volume ([VesselVolumes]); the
/// waves are the vessel's own modes ([FreeSurface]); and liquid leaves over
/// the lip at the weir's rate wherever the surface, waves and all, stands
/// above the rim. Nothing else changes the volume: [step] returns what left,
/// and [pour] is how liquid comes in.
///
/// **Liquids that do not mix lie in [layers]**, densest at the bottom, each
/// boundary a plane square to the same gravity at the height that holds the
/// volume below it. The waves and the meniscus are the top liquid's, what
/// runs over the lip is the top layer, and a pipe draws on the layer at its
/// opening.
final class LiquidBody implements JetReceiver {
  LiquidBody({
    required this.shape,
    required FluidMedium medium,
    required double volume,
    Map<String, double> concentrations = const {},
    int surfaceCells = 40,
    int modes = 12,
    this.wallThickness = 0.0,
  }) : surface = FreeSurface(
         medium: medium,
         cells: surfaceCells,
         modeCount: modes,
       ) {
    _layers.add(LiquidLayer.at(medium, volume, concentrations));
    surface.layOut(shape, _up, shape.surfaceFor(_up, volume + displaced));
  }

  final VesselShape shape;
  final FreeSurface surface;

  /// The liquids in it, bottom first.
  List<LiquidLayer> get layers => List.unmodifiable(_layers);
  final List<LiquidLayer> _layers = [];

  /// How much of the vessel solid bodies in it take up below the surface,
  /// cubic metres: liquid cannot be where they are, so the surface stands
  /// that much higher. Set by whoever floats bodies in it — `FluidWorld`.
  double displaced = 0.0;

  /// The force the liquid puts on its vessel, newtons, in the world, for
  /// [gravity]: its weight less what it takes to carry it with the vessel's
  /// acceleration, the push of its waves rocking, and the reaction of what
  /// ran over the lip on the last step.
  Vector3 load(Vector3 gravity) {
    final mass = _layers.fold(0.0, (s, l) => s + l.medium.density * l.volume);
    final out = (gravity - _acceleration) * mass;
    out.add(rotation.transformed(surface.force(medium.density)));
    final spilt = _lastSpill;
    if (spilt != null) {
      out.addScaled(spilt.velocity, -spilt.medium.density * spilt.flow);
    }
    return out;
  }

  final Vector3 _acceleration = Vector3.zero();
  Spill? _lastSpill;

  /// The liquid at the surface.
  FluidMedium get medium =>
      _layers.isEmpty ? surface.medium : _layers.last.medium;

  /// How thick the vessel's wall is, for a stream that runs down its
  /// outside; nought for none.
  final double wallThickness;

  /// The seconds this liquid has been stepped through: what [place] stamps
  /// a position with.
  double get clock => _clock;
  double _clock = 0.0;

  /// Cubic metres of liquid, every layer.
  double get volume => _layers.fold(0.0, (sum, l) => sum + l.volume);

  /// The vessel's turn and place in the world, as last [place]d.
  final Matrix3 rotation = Matrix3.identity();
  final Vector3 position = Vector3.zero();
  final List<({double time, Vector3 at})> _history = [];

  /// Which way is up in the vessel's frame — square to the gravity felt —
  /// and the height of the surface's plane along it.
  Vector3 get up => _up.clone();
  Vector3 _up = Vector3(0, 1, 0);
  double get height => surface.height;

  /// Puts the vessel at [at], turned by [turn], as it is at [time] seconds
  /// on the liquid's clock — by default the clock as it stands, the place
  /// for the next [step]. The vessel's acceleration is read off its path, so
  /// the time must be when the vessel was there: a caller placing it once a
  /// frame and stepping a whole number of fixed steps after passes the
  /// frame's own time (`FluidWorld.time` plus the frame), since stamped with
  /// the clock instead, a frame that ran one step and the next that ran
  /// three read as a jolt worth a good part of gravity, and the liquid
  /// threw itself out of the glass.
  void place(Matrix3 turn, Vector3 at, {double? time}) {
    final stamp = time ?? _clock;
    rotation.setFrom(turn);
    position.setFrom(at);
    // Placed again for the same moment: the newer place stands for it.
    if (_history.isNotEmpty && _history.last.time >= stamp) {
      _history.removeLast();
    }
    _history.add((time: stamp, at: at.clone()));
    if (_history.length > 3) _history.removeAt(0);
  }

  /// Whether a parcel of [radius] at [point] (world) is in the vessel with
  /// its underside at or below the surface.
  @override
  bool catches(Vector3 point, double radius) {
    // Far from the glass, said at once and with nothing made: every drop
    // and parcel in flight asks every vessel this every step, and building
    // the frame for each was most of what a pour cost.
    final q = shape is RevolvedVessel ? _near(point, radius) : _local(point);
    if (q == null || !shape.contains(q)) return false;
    // Empty, there is no surface to land on: what reaches the bottom wets
    // it and stays, the start of a liquid. A quarter of a radius of slack,
    // since what rests on glass rests a radius off it and no nearer.
    final surface = volume > 0.0 ? surfaceAt(q) : shape.span(_up).low;
    return _up.dot(q) - radius <= surface + 0.25 * radius;
  }

  /// Liquid arriving from a stream: added, first heaped where it lands —
  /// its own volume over the patch it strikes — and striking the surface
  /// with the momentum it comes down with, from where both spread as waves.
  @override
  void receive(
    double volume,
    Vector3 point,
    Vector3 velocity,
    FluidMedium medium,
    Map<String, double> concentrations,
  ) {
    final spread = surface.knockSpread;
    final patch = 2.0 * math.pi * spread * spread;
    pour(volume, medium: medium, concentrations: concentrations);
    if (patch <= 0.0) return;
    // How fast it comes down onto the surface: along the vessel's up.
    final down = -(rotation.clone()..transpose())
        .transformed(velocity)
        .dot(_up);
    surface.land(
      _local(point),
      heap: volume / patch,
      flux: down > 0.0 ? volume * down / patch : 0.0,
    );
  }

  /// [point] from the world into the vessel's frame.
  Vector3 _local(Vector3 point) => _toLocal(point);

  /// [point] in the vessel's frame, or null when it is further from the
  /// vessel than [margin] beyond its inside, sideways or along its axis:
  /// what an obstacle asks first, many times a step, so no matrix is made.
  Vector3? _near(Vector3 point, double margin) {
    final shape = this.shape;
    if (shape is! RevolvedVessel) return null;
    final m = rotation.storage;
    final dx = point.x - position.x;
    final dy = point.y - position.y;
    final dz = point.z - position.z;
    // Rᵀ(p − o), column by column.
    final y = m[3] * dx + m[4] * dy + m[5] * dz;
    if (y < shape.floor - margin || y > shape.top + margin) return null;
    final x = m[0] * dx + m[1] * dy + m[2] * dz;
    final z = m[6] * dx + m[7] * dy + m[8] * dz;
    final reach = shape.widest + margin;
    if (x * x + z * z > reach * reach) return null;
    return Vector3(x, y, z);
  }

  /// Whether anything within [distance] of [centre] (world) could be at
  /// this vessel's walls: by the ball round its inside.
  bool _reaches(Vector3 centre, double distance) {
    final shape = this.shape;
    if (shape is! RevolvedVessel) return true;
    final half = 0.5 * (shape.top - shape.floor);
    final middle =
        position +
        rotation.transformed(Vector3(0, 0.5 * (shape.top + shape.floor), 0));
    final ball =
        math.sqrt(shape.widest * shape.widest + half * half) + distance;
    return centre.distanceToSquared(middle) < ball * ball;
  }

  Vector3 _toLocal(Vector3 point) =>
      (rotation.clone()..transpose()).transformed(point - position);

  /// Adds [amount] cubic metres of [medium] — the top liquid's, if none is
  /// named — carrying [concentrations]; landing, it knocks the surface at
  /// [where] (vessel frame) by [knock] metres.
  void pour(
    double amount, {
    FluidMedium? medium,
    Map<String, double> concentrations = const {},
    Vector3? where,
    double knock = 0.0,
  }) {
    if (amount <= 0.0) return;
    add(LiquidLayer.at(medium ?? this.medium, amount, concentrations));
    if (where != null && knock != 0.0) surface.knock(where, knock);
  }

  /// Adds [layer]: to the layer of the same medium, which it mixes with, or
  /// as a layer of its own where its density puts it.
  void add(LiquidLayer layer) {
    if (layer.volume <= 0.0) return;
    final same = _layers.where((l) => l.medium.name == layer.medium.name);
    if (same.isNotEmpty) {
      same.first.add(layer);
    } else {
      _layers
        ..add(
          LiquidLayer(
            medium: layer.medium,
            volume: layer.volume,
            amounts: layer.amounts,
          ),
        )
        ..sort((a, b) => b.medium.density.compareTo(a.medium.density));
    }
    surface.medium = medium;
    _relayIfMoved(force: true);
  }

  /// Takes [amount] cubic metres away from the bottom — a drain — without a
  /// spill; returns what was taken, layer by layer.
  List<LiquidLayer> drain(double amount) => drawAt(Vector3(0, -1e9, 0), amount);

  /// Takes [amount] cubic metres from the layer at [point] (vessel frame) —
  /// a pipe's opening — and from the ones above it once that runs out.
  List<LiquidLayer> drawAt(Vector3 point, double amount) {
    final tops = layerTops();
    final h = _up.dot(point);
    var first = 0;
    while (first < tops.length - 1 && tops[first] < h) {
      first++;
    }
    final out = <LiquidLayer>[];
    var left = amount;
    for (var i = first; i < _layers.length && left > 0.0; i++) {
      final taken = _layers[i].take(left);
      left -= taken.volume;
      if (taken.volume > 0.0) out.add(taken);
    }
    _layers.removeWhere((l) => l.volume <= 1e-15);
    if (_layers.isNotEmpty) surface.medium = medium;
    _relayIfMoved(force: true);
    return out;
  }

  /// The height of each layer's top along [up], bottom first: the plane
  /// that holds it and every layer under it.
  List<double> layerTops() {
    var below = 0.0;
    // Each from the surface's own height, which the top one is near and
    // the others are under.
    final guess = surface.height;
    return [
      for (final l in _layers)
        guess.isFinite && guess != 0.0
            ? shape.surfaceNear(_up, below += l.volume, guess)
            : shape.surfaceFor(_up, below += l.volume),
    ];
  }

  /// The pressure of the liquid at [point] (vessel frame) above the air's:
  /// every layer above it, each its own density times the gravity felt
  /// times how much of it stands over the point.
  double pressureAt(Vector3 point) {
    final h = _up.dot(point);
    final tops = layerTops();
    var pressure = 0.0;
    var bottom = -double.infinity;
    for (var i = 0; i < _layers.length; i++) {
      final over = tops[i] - math.max(bottom, h);
      if (over > 0.0) pressure += _layers[i].medium.density * _g * over;
      bottom = tops[i];
    }
    return pressure;
  }

  /// Moves the liquid on by [dt] under the world's [gravity], and returns
  /// what ran over the lip in that time, already taken out of [volume].
  Spill step(double dt, {required Vector3 gravity}) {
    // **Asleep while nothing happens to it.** A glass standing on a bench,
    // its surface still, has nothing to step: the same place, the same
    // volume, the same gravity, nothing knocked or landed. Eight of a
    // bench's nine glasses are that, and stepping them two hundred and
    // forty times a second was most of what a frame cost in a browser.
    if (_asleep && _sameAsAsleep(gravity)) {
      _clock += dt;
      return Spill.none;
    }
    _asleep = false;
    final spill = _stepAwake(dt, gravity: gravity);
    _maybeSleep(gravity, spill);
    return spill;
  }

  bool _asleep = false;
  double _sleptVolume = double.nan;
  double _sleptDisplaced = double.nan;
  int _sleptDisturbances = -1;
  final Vector3 _sleptAt = Vector3.zero();
  final Matrix3 _sleptTurn = Matrix3.zero();
  final Vector3 _sleptGravity = Vector3.zero();

  bool _sameAsAsleep(Vector3 gravity) =>
      volume == _sleptVolume &&
      displaced == _sleptDisplaced &&
      surface.disturbances == _sleptDisturbances &&
      position == _sleptAt &&
      rotation == _sleptTurn &&
      gravity == _sleptGravity;

  /// Falls asleep after a step in which it was still: placed where it was
  /// placed the last two times, running nothing over, its waves gone.
  void _maybeSleep(Vector3 gravity, Spill spill) {
    if (spill.flow > 0.0 || !surface.quiet) return;
    if (_history.length < 2) return;
    for (final h in _history) {
      if (h.at != position) return;
    }
    surface.calm();
    _asleep = true;
    _sleptVolume = volume;
    _sleptDisplaced = displaced;
    _sleptDisturbances = surface.disturbances;
    _sleptAt.setFrom(position);
    _sleptTurn.setFrom(rotation);
    _sleptGravity.setFrom(gravity);
  }

  Spill _stepAwake(double dt, {required Vector3 gravity}) {
    // The gravity felt: the world's, less the vessel's acceleration.
    final felt = gravity.clone();
    if (_history.length == 3) {
      // The second difference over the times the places were stamped,
      // however many steps lay between them.
      final (time: t0, at: p0) = _history[0];
      final (time: t1, at: p1) = _history[1];
      final (time: t2, at: p2) = _history[2];
      if (t1 > t0 && t2 > t1) {
        final v0 = (p1 - p0) / (t1 - t0);
        final v1 = (p2 - p1) / (t2 - t1);
        _acceleration.setFrom((v1 - v0) * (2.0 / (t2 - t0)));
        felt.sub(_acceleration);
      }
    }
    _clock += dt;
    _g = felt.length;
    final g = felt.length;
    if (g > 1e-9) {
      final turnBack = rotation.clone()..transpose();
      _up = turnBack.transformed(-felt / g)..normalize();
    }
    _relayIfMoved();
    final depth = surface.area > 0.0 ? volume / surface.area : 0.0;
    surface.step(dt, g: math.max(g, 1e-6), depth: depth);
    final spill = _spill(dt, math.max(g, 1e-6));
    _lastSpill = spill.flow > 0.0 ? spill : null;
    return spill;
  }

  /// The surface's height along [up] over [point] (vessel frame): its plane,
  /// the waves on it, and the meniscus at the wall.
  double surfaceAt(Vector3 point) =>
      height + surface.displacement(point) + meniscusAt(point);

  /// The gravity the liquid felt on its last step, m/s².
  double get gravity => _g;
  double _g = 9.81;

  /// How far the meniscus stands over [point] (vessel frame) above the flat
  /// surface of the same volume — up at a wall the liquid wets, down at one
  /// it does not. For a round vessel standing upright, the exact
  /// Young–Laplace surface for its radius at the surface ([TubeMeniscus]),
  /// nought on average. Tipped, the surface cuts the glass in a long oval
  /// and is no longer a surface of revolution about anything: the flat
  /// wall's ([wallMeniscus]) by how far [point] is from the glass. Measured
  /// by the distance from the axis there, it climbed the long sides of a
  /// tipped tube by the radius's meniscus and stood out through the glass.
  double meniscusAt(Vector3 point) {
    final shape = this.shape;
    if (shape is RevolvedVessel && _up.y < 0.999) {
      if (volume <= 0.0) return 0.0;
      return _wallRise(shape, point) - _tippedMean(shape);
    }
    final m = _meniscus();
    if (m == null) return 0.0;
    final r = math.sqrt(point.x * point.x + point.z * point.z);
    return m.heightAt(r) - m.meanHeight;
  }

  /// The pressure the meniscus takes off the liquid under it, pascals: σ
  /// times the curvature at its middle.
  double get capillaryPressure {
    final m = _meniscus();
    return m == null ? 0.0 : medium.surfaceTension * m.apexCurvature;
  }

  /// How deep [point] (vessel frame) is under the surface.
  double depthAbove(Vector3 point) => height - _up.dot(point);

  double _wallRise(RevolvedVessel shape, Vector3 point) {
    final at = shape.wallDistance(point);
    if (at == null) return 0.0;
    return wallMeniscus(medium, math.max(-at.distance, 0.0), _g);
  }

  /// The wall's meniscus averaged over a tipped surface, taken out of it so
  /// that, like the upright one, it moves liquid about and adds none: left
  /// in, a tube tipped half a radian drew a fortieth more than it held.
  /// Kept until the surface is laid out again.
  double _tippedMean(RevolvedVessel shape) {
    final layout = surface.layout;
    if (!identical(layout, _tippedFor) || _tippedG != _g) {
      _tippedFor = layout;
      _tippedG = _g;
      _tipped = surface.meanOf((p) => _wallRise(shape, p)).mean;
    }
    return _tipped;
  }

  Object? _tippedFor;
  double _tippedG = double.nan;
  double _tipped = 0.0;

  /// The most the meniscus stands above the flat surface anywhere.
  double _meniscusPeak() => shape is RevolvedVessel && _up.y < 0.999
      ? math.max(
          wallMeniscus(medium, 0.0, _g) - _tippedMean(shape as RevolvedVessel),
          0.0,
        )
      : (_meniscus()?.peak ?? 0.0);

  /// Menisci already solved, by the radius they were solved for, in steps of
  /// a hundredth of it; and the medium and gravity they were solved under.
  ///
  /// **Kept, not solved again.** Each is a shooting solution of the
  /// Young–Laplace equation. Kept one at a time, a surface rising through a
  /// test tube's round bottom, where the radius changes with every step,
  /// solved one on every question asked of the surface — each drop that
  /// landed asked one — and filling the bottom of the clean tube cost three
  /// times the rest of the pour. A hundredth of the radius is a fiftieth of
  /// the meniscus's rise or less.
  final Map<int, TubeMeniscus> _menisci = {};
  FluidMedium? _menisciMedium;
  double _menisciG = double.nan;

  TubeMeniscus? _meniscus() {
    final shape = this.shape;
    if (shape is! RevolvedVessel || volume <= 0.0) return null;
    final radius = shape.radiusAt(height.clamp(shape.floor, shape.top));
    if (radius <= 0.0) return null;
    if (!identical(_menisciMedium, medium) ||
        !((_menisciG - _g).abs() < 1e-3 * _g)) {
      _menisci.clear();
      _menisciMedium = medium;
      _menisciG = _g;
    }
    final key = (Portable.log(radius) / 0.01).round();
    return _menisci[key] ??= TubeMeniscus(
      medium: medium,
      radius: Portable.exp(key * 0.01),
      g: _menisciG,
    );
  }

  /// The volume and up the surface's height was last found for, and the
  /// height.
  double _laidFor = double.nan;
  final Vector3 _laidUp = Vector3.zero();
  double _laidAt = double.nan;

  /// Lays the surface out again when its plane has turned or moved by more
  /// than a little, carrying the waves over.
  void _relayIfMoved({bool force = false}) {
    final target = volume + displaced;
    // Standing still, nothing to find; moving, found from where it was.
    final h = !force && target == _laidFor && _up == _laidUp
        ? _laidAt
        : (_laidAt.isNaN
              ? shape.surfaceFor(_up, target)
              : shape.surfaceNear(_up, target, _laidAt));
    _laidFor = target;
    _laidUp.setFrom(_up);
    _laidAt = h;
    final turned = 1.0 - _up.dot(surface.up);
    final moved = (h - surface.height).abs();
    if (force || turned > 2e-5 || moved > 1e-4) {
      surface.layOut(shape, _up, h);
    }
  }

  /// What runs over the rim in [dt]: each stretch of it passes the weir's
  /// rate for the depth of liquid standing over it, waves included.
  Spill _spill(double dt, double g) {
    final rim = shape.rim;
    if (rim.isEmpty || volume <= 0.0) return Spill.none;
    // Nowhere near the lip, waves at their highest and meniscus and all:
    // nothing to ask the rim.
    final edge = shape.lip(_up);
    if (edge != null &&
        height + surface.reach + _meniscusPeak() < edge.height) {
      return Spill.none;
    }
    var flow = 0.0;
    var width = 0.0;
    var crest = 0.0;
    final at = Vector3.zero();
    final along = Vector3.zero();
    for (var i = 0; i < rim.length; i++) {
      final a = rim[i];
      final b = rim[(i + 1) % rim.length];
      final mid = (a + b) * 0.5;
      final depth = surfaceAt(mid) - _up.dot(mid);
      if (depth <= 0.0) continue;
      final length = (b - a).length;
      final q =
          sharpEdgeDischarge *
          (2.0 / 3.0) *
          math.sqrt(2.0 * g) *
          depth *
          math.sqrt(depth) *
          length;
      flow += q;
      width += length;
      crest += (2.0 / 3.0) * depth * length;
      at.addScaled(mid, q);
      // Out over the edge: away from the vessel's middle, in the plane.
      final out = mid - _up * _up.dot(mid);
      if (out.length2 > 0.0) along.addScaled(out.normalized(), q);
    }
    if (flow <= 0.0) return Spill.none;
    // Where and which way, weighed by what each stretch passed.
    final point = rotation.transformed(at / flow);
    final direction = along.length2 > 0.0
        ? rotation.transformed(along.normalized())
        : Vector3.zero();
    final speed = flow / crest;
    // The top layer runs out, and no more of it than there is: in the step
    // it is used up, the one under it takes its place at the lip.
    final top = _layers.last;
    final out = math.min(flow * dt, top.volume);
    final concentrations = top.concentrations;
    final what = top.medium;
    top.take(out);
    if (top.volume <= 1e-15 && _layers.length > 1) _layers.removeLast();
    surface.medium = medium;
    flow = dt > 0.0 ? out / dt : 0.0;
    _relayIfMoved();
    return Spill(
      flow: flow,
      point: point + position,
      velocity: direction * speed,
      width: width,
      medium: what,
      concentrations: concentrations,
    );
  }
}

/// The inside of a [LiquidBody]'s vessel as a wall a stream runs along: for
/// a [RevolvedVessel], the side and the floor; another shape has no walls
/// yet, and a stream passes through it.
final class InsideWalls implements JetObstacle {
  InsideWalls(this.body);

  final LiquidBody body;

  @override
  bool reaches(Vector3 centre, double distance) =>
      body._reaches(centre, distance + body.wallThickness);

  @override
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final shape = body.shape;
    if (shape is! RevolvedVessel) return null;
    final q = body._near(point, body.wallThickness + radius);
    if (q == null) return null;
    // Under the inside's floor and beyond its edge is outside the glass,
    // beside its foot, where the outside answers. Taken for the inside's,
    // a drop on the bench by a beaker's foot, half a millimetre down where
    // the floor inside is half a millimetre up, was pushed up into the
    // glass while the bench pushed it down, and left at metres a second.
    if (q.y < shape.floor &&
        q.x * q.x + q.z * q.z >=
            shape.radiusAt(shape.floor) * shape.radiusAt(shape.floor)) {
      return null;
    }
    final at = shape.wallDistance(q);
    if (at == null) return null;
    // Within a radius of the inside, or into the glass up to half its
    // thickness: past that it is the outside's.
    final glass = body.wallThickness > 0.0 ? 0.5 * body.wallThickness : radius;
    if (at.distance <= -radius || at.distance >= glass) return null;
    return (
      normal: body.rotation.transformed(-at.normal),
      depth: at.distance + radius,
    );
  }
}

/// The outside of a [LiquidBody]'s vessel, [thickness] out from its inside,
/// as a wall a stream runs along: what a slow pour clings to below the lip.
/// For a [RevolvedVessel]; another shape has none yet.
final class OutsideWalls implements JetObstacle {
  OutsideWalls(this.body, {required this.thickness});

  final LiquidBody body;
  final double thickness;

  @override
  bool reaches(Vector3 centre, double distance) =>
      body._reaches(centre, distance + thickness);

  @override
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final shape = body.shape;
    if (shape is! RevolvedVessel) return null;
    final q = body._near(point, thickness + radius);
    if (q == null) return null;
    // Below the inside's floor the glass is its foot, standing on whatever
    // the vessel stands on: pushed out sideways, never down into the bench.
    if (q.y < shape.floor) {
      final r = math.sqrt(q.x * q.x + q.z * q.z);
      final clear = shape.radiusAt(shape.floor) + thickness + radius;
      if (r >= clear || r < shape.radiusAt(shape.floor)) return null;
      final out = r > 1e-12 ? Vector3(q.x / r, 0, q.z / r) : Vector3(1, 0, 0);
      return (normal: body.rotation.transformed(out), depth: clear - r);
    }
    // The rim's top is glass too, up to its thickness above the mouth.
    final at = shape.wallDistance(
      q.y > shape.top && q.y <= shape.top + thickness
          ? Vector3(q.x, shape.top, q.z)
          : q,
    );
    if (at == null) return null;
    final clear = thickness + radius;
    if (at.distance < 0.5 * thickness || at.distance >= clear) return null;
    return (
      normal: body.rotation.transformed(at.normal),
      depth: clear - at.distance,
    );
  }
}
