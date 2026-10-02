import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

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
    surface.layOut(shape, _up, shape.surfaceFor(_up, volume));
  }

  final VesselShape shape;
  final FreeSurface surface;

  /// The liquids in it, bottom first.
  List<LiquidLayer> get layers => List.unmodifiable(_layers);
  final List<LiquidLayer> _layers = [];

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

  /// Puts the vessel at [at], turned by [turn]. Called once a step, before
  /// [step], so the vessel's acceleration can be read off its path.
  void place(Matrix3 turn, Vector3 at) {
    rotation.setFrom(turn);
    position.setFrom(at);
    // Placed again before a step: the newer place stands for this moment.
    if (_history.isNotEmpty && _history.last.time == _clock) {
      _history.removeLast();
    }
    _history.add((time: _clock, at: at.clone()));
    if (_history.length > 3) _history.removeAt(0);
  }

  /// Whether a parcel of [radius] at [point] (world) is in the vessel with
  /// its underside at or below the surface.
  @override
  bool catches(Vector3 point, double radius) {
    final q = _local(point);
    return shape.contains(q) && _up.dot(q) - radius <= surfaceAt(q);
  }

  /// Liquid arriving from a stream: added, and first heaped where it lands,
  /// its own volume over the patch it strikes, from where it spreads as
  /// waves.
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
    pour(
      volume,
      medium: medium,
      concentrations: concentrations,
      where: _local(point),
      knock: patch > 0.0 ? volume / patch : 0.0,
    );
  }

  /// [point] from the world into the vessel's frame.
  Vector3 _local(Vector3 point) =>
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
    return [for (final l in _layers) shape.surfaceFor(_up, below += l.volume)];
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
        felt.sub((v1 - v0) * (2.0 / (t2 - t0)));
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
    return _spill(dt, math.max(g, 1e-6));
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
  /// it does not, nought on average. For a round vessel, the exact
  /// Young–Laplace surface for its radius at the surface ([TubeMeniscus]);
  /// for another, the flat wall's ([wallMeniscus]) by distance from it.
  double meniscusAt(Vector3 point) {
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

  TubeMeniscus? _tube;

  TubeMeniscus? _meniscus() {
    final shape = this.shape;
    if (shape is! RevolvedVessel || volume <= 0.0) return null;
    final radius = shape.radiusAt(height.clamp(shape.floor, shape.top));
    if (radius <= 0.0) return null;
    final tube = _tube;
    if (tube != null &&
        (tube.radius - radius).abs() < 1e-3 * radius &&
        (tube.g - _g).abs() < 1e-3 * _g) {
      return tube;
    }
    return _tube = TubeMeniscus(medium: medium, radius: radius, g: _g);
  }

  /// Lays the surface out again when its plane has turned or moved by more
  /// than a little, carrying the waves over.
  void _relayIfMoved({bool force = false}) {
    final h = shape.surfaceFor(_up, volume);
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
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final shape = body.shape;
    if (shape is! RevolvedVessel) return null;
    final q = (body.rotation.clone()..transpose()).transformed(
      point - body.position,
    );
    if (q.y > shape.top || q.y < shape.floor - radius) return null;
    final r = math.sqrt(q.x * q.x + q.z * q.z);
    final wall = shape.radiusAt(math.max(q.y, shape.floor));
    if (r > wall + radius) return null;
    if (q.y < shape.floor + radius) {
      return (
        normal: body.rotation.transformed(Vector3(0, 1, 0)),
        depth: shape.floor + radius - q.y,
      );
    }
    final reach = wall - radius;
    if (r <= reach || r < 1e-9) return null;
    return (
      normal: body.rotation.transformed(Vector3(-q.x / r, 0, -q.z / r)),
      depth: r - reach,
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
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius) {
    final shape = body.shape;
    if (shape is! RevolvedVessel) return null;
    final q = (body.rotation.clone()..transpose()).transformed(
      point - body.position,
    );
    if (q.y > shape.top + thickness || q.y < shape.floor - thickness) {
      return null;
    }
    final r = math.sqrt(q.x * q.x + q.z * q.z);
    final outside =
        shape.radiusAt(q.y.clamp(shape.floor, shape.top)) + thickness;
    final clear = outside + radius;
    if (r >= clear || r < shape.radiusAt(q.y.clamp(shape.floor, shape.top))) {
      return null;
    }
    final out = r > 1e-9 ? Vector3(q.x / r, 0, q.z / r) : Vector3(1, 0, 0);
    return (normal: body.rotation.transformed(out), depth: clear - r);
  }
}
