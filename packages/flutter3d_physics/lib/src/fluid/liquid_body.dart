import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'fluid_medium.dart';
import 'free_surface.dart';
import 'jet.dart';
import 'outflow.dart';
import 'vessel_shape.dart';

/// What ran over a vessel's lip in one step, in the world.
final class Spill {
  const Spill({
    required this.flow,
    required this.point,
    required this.velocity,
    required this.width,
  });

  /// No spill.
  static final Spill none = Spill(
    flow: 0.0,
    point: Vector3.zero(),
    velocity: Vector3.zero(),
    width: 0.0,
  );

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
final class LiquidBody implements JetReceiver {
  LiquidBody({
    required this.shape,
    required this.medium,
    required double volume,
    int surfaceCells = 40,
    int modes = 12,
  }) : _volume = volume,
       surface = FreeSurface(
         medium: medium,
         cells: surfaceCells,
         modeCount: modes,
       ) {
    surface.layOut(shape, _up, shape.surfaceFor(_up, volume));
  }

  final VesselShape shape;
  final FluidMedium medium;
  final FreeSurface surface;

  /// Cubic metres of liquid.
  double get volume => _volume;
  double _volume;

  /// The vessel's turn and place in the world, as last [place]d.
  final Matrix3 rotation = Matrix3.identity();
  final Vector3 position = Vector3.zero();
  final List<Vector3> _history = [];

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
    _history.add(at.clone());
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
  void receive(double volume, Vector3 point, Vector3 velocity) {
    final spread = surface.knockSpread;
    final patch = 2.0 * math.pi * spread * spread;
    pour(
      volume,
      where: _local(point),
      knock: patch > 0.0 ? volume / patch : 0.0,
    );
  }

  /// [point] from the world into the vessel's frame.
  Vector3 _local(Vector3 point) =>
      (rotation.clone()..transpose()).transformed(point - position);

  /// Adds [amount] cubic metres of liquid; landing, it knocks the surface
  /// at [where] (vessel frame) by [knock] metres.
  void pour(double amount, {Vector3? where, double knock = 0.0}) {
    _volume += amount;
    _relayIfMoved(force: true);
    if (where != null && knock != 0.0) surface.knock(where, knock);
  }

  /// Takes [amount] cubic metres away — a drain, a pipe — without a spill.
  void drain(double amount) {
    _volume = math.max(_volume - amount, 0.0);
    _relayIfMoved(force: true);
  }

  /// Moves the liquid on by [dt] under the world's [gravity], and returns
  /// what ran over the lip in that time, already taken out of [volume].
  Spill step(double dt, {required Vector3 gravity}) {
    // The gravity felt: the world's, less the vessel's acceleration.
    final felt = gravity.clone();
    if (_history.length == 3 && dt > 0.0) {
      final a = (_history[2] - _history[1] * 2.0 + _history[0]) / (dt * dt);
      felt.sub(a);
    }
    final g = felt.length;
    if (g > 1e-9) {
      final turnBack = rotation.clone()..transpose();
      _up = turnBack.transformed(-felt / g)..normalize();
    }
    _relayIfMoved();
    final depth = surface.area > 0.0 ? _volume / surface.area : 0.0;
    surface.step(dt, g: math.max(g, 1e-6), depth: depth);
    return _spill(dt, math.max(g, 1e-6));
  }

  /// The surface's height along [up] over [point] (vessel frame): its plane
  /// and the waves on it.
  double surfaceAt(Vector3 point) => height + surface.displacement(point);

  /// Lays the surface out again when its plane has turned or moved by more
  /// than a little, carrying the waves over.
  void _relayIfMoved({bool force = false}) {
    final h = shape.surfaceFor(_up, _volume);
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
    if (rim.isEmpty || _volume <= 0.0) return Spill.none;
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
    // No more can leave than there is.
    final out = math.min(flow * dt, _volume);
    flow = dt > 0.0 ? out / dt : 0.0;
    _volume -= out;
    _relayIfMoved();
    return Spill(
      flow: flow,
      point: point + position,
      velocity: direction * speed,
      width: width,
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
