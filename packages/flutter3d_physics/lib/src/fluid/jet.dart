import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'fluid_medium.dart';
import 'fluid_solver.dart';

/// When something thrown at [velocity] from [height] reaches [floor] under
/// gravity [g] pointing down: the later root of height + v_y·t − g t²/2 =
/// floor. For aiming a stream: how far it is carried while it falls. [g] is
/// the world's; [standardGravity] when the caller has none to give.
double fallTime(
  Vector3 velocity,
  double height,
  double floor, {

  /// Gravity's pull, in metres per second squared.
  double g = standardGravity,
}) {
  final drop = math.max(height - floor, 0.0);
  return (velocity.y + math.sqrt(velocity.y * velocity.y + 2.0 * g * drop)) / g;
}

/// Something a stream can land in — a vessel's liquid.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class JetReceiver {
  /// Whether a parcel of [radius] at [point] (world) has reached this
  /// receiver's surface: whether its underside has.
  bool catches(Vector3 point, double radius);

  /// Takes [volume] cubic metres of [medium] carrying [concentrations],
  /// arriving at [point] moving at [velocity].
  void receive(
    double volume,
    Vector3 point,
    Vector3 velocity,
    FluidMedium medium,
    Map<String, double> concentrations,
  );
}

/// Something a stream can run into and along — a wall.
///
/// **Mixed in, not implemented**, outside this library: a `base` type, so a
/// member added in a 1.x release arrives with a body and nothing that mixes
/// it in has to change.
abstract base mixin class JetObstacle {
  /// Where a parcel of [radius] at [point] (world) is into this obstacle:
  /// the way out and how far, or null when it is clear of it.
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius);

  /// Whether anything within [distance] of [center] (world) could touch
  /// this obstacle: false only when it certainly cannot. Asked once a step
  /// for everything in flight together, so the walls far from it are not
  /// asked again for each parcel, piece and pass.
  bool reaches(Vector3 center, double distance);
}

/// [obstacles] that something within [distance] of [center] could touch.
List<JetObstacle> obstaclesNear(
  List<JetObstacle> obstacles,
  Vector3 center,
  double distance,
) => [
  for (final o in obstacles)
    if (o.reaches(center, distance)) o,
];

/// A drop a stream broke into, leaving it: where, how fast, how much.
typedef JetDrop = ({
  Vector3 position,
  Vector3 velocity,
  double volume,
  FluidMedium medium,
  Map<String, double> concentrations,
});

/// One point of a stream as a renderer draws it: where, which way it moves,
/// and its section — an ellipse [wide] across [across] and [thick] the other
/// way.
typedef JetSample = ({
  Vector3 position,
  Vector3 direction,
  Vector3 across,
  double wide,
  double thick,
});

/// A stream of liquid, as the parcels of it that are in the air.
///
/// **Each parcel is what left the lip in one step**, Q·dt of it, thrown at
/// the speed it left with and falling freely under the world's gravity from
/// there; so a stream from a lip that has moved on keeps the path it was
/// thrown on, and when nothing more leaves, its tail comes away and falls.
/// The continuity equation is then not imposed but follows: a parcel's
/// section is its volume over the distance it covers in a step, which is the
/// flow it left with over its speed now. It leaves the lip as a flat sheet as
/// wide as the wetted edge, and its edges draw in at the Taylor–Culick speed,
/// √(2σ / ρe), until it is round.
///
/// **Water wets glass**, so a parcel that meets a wall stays on it: it loses
/// the part of its speed that went into the wall and runs along it, held
/// there while it is slower than [clingSpeed] — down the inside of a glass
/// it is poured into, and, poured slowly, down the outside of the one it is
/// poured from.
///
/// **A thin stream breaks into drops** (Plateau and Rayleigh): ripples on it
/// grow at the rate one over √(ρD³/σ) + 3μD/σ — Weber's, the first term
/// inertia against surface tension and the second viscosity — and it parts
/// where the growth reaches e¹², the factor between a stream's first
/// disturbances and its radius that Grant and Middleman measured. In still
/// air, that is the intact length L/D = 12(√We + 3We/Re). A parted parcel
/// leaves as drops of about 1.89 times the stream's diameter, handed back by
/// [step].
///
/// **Every cubic metre is somewhere**: emitted is the sum of what is in the
/// air, what receivers have taken, and what left as drops.
final class Jet {
  Jet({
    required this.medium,
    this.breakupGrowth = 12.0,
    this.solver = const DartFluid(),
  });

  /// The liquid a parcel is when [emit] is not told otherwise, and the one
  /// [clingSpeed] answers for.
  final FluidMedium medium;

  /// How many e-foldings of growth part the stream: a unitless count.
  final double breakupGrowth;

  /// What flies the parcels each step: the reference unless told
  /// otherwise; a `FluidWorld` gives its own, the run's.
  final FluidSolver solver;

  final List<_Parcel> _parcels = [];

  /// The fastest a film or rivulet [thickness] thick runs along a wall it
  /// wets and stays on it, for this [medium].
  ///
  /// Surface tension holds it to the wall with σ(1 + cos θ) per unit of
  /// wetted area, the work it would take to pull the liquid off; its
  /// inertia, ρv²e per unit of width, is what would carry it straight on.
  /// It clings while the second is the smaller — slower than
  /// √(σ(1 + cos θ) / ρe) — which is why a slow pour runs down the outside of
  /// a spout and a quick one leaves it cleanly. An estimate of the criterion
  /// Duez and colleagues measured (2010), whose full form also weighs how
  /// sharply the edge curves.
  double clingSpeed(double thickness) => _clingSpeed(medium, thickness);

  /// The share of a parcel that splashes back out where it lands.
  ///
  /// Mundo and colleagues' criterion: a drop of diameter D striking at v
  /// splashes when K = Oh·Re^1.25 passes 57.7, Oh = μ/√(ρσD) weighing
  /// viscosity against surface tension and Re = ρvD/μ inertia against
  /// viscosity. A stream of water three millimetres across at a metre a
  /// second is at 46 and goes in quietly. How much is thrown out past the
  /// threshold is less settled; this takes a tenth of the excess, up to
  /// half — an estimate of the secondary-drop fractions measured for crown
  /// splashes, not a fit to one.
  static double _splashShare(_Parcel p) {
    final m = p.medium;
    final d = 2.0 * math.sqrt(p.section / math.pi);
    final v = p.velocity.length;
    if (d <= 0.0 || v <= 0.0) return 0.0;
    final oh = m.viscosity / math.sqrt(m.density * m.surfaceTension * d);
    final re = m.density * v * d / m.viscosity;
    final k = oh * re * math.sqrt(math.sqrt(re));
    return k <= 57.7 ? 0.0 : math.min(0.5, 0.1 * (k / 57.7 - 1.0));
  }

  /// How much has left the lip, and how much of it receivers have taken.
  /// In cubic metres.
  double get emitted => _emitted;
  double _emitted = 0.0;

  /// How much of [emitted] receivers have taken, in cubic metres.
  double get landed => _landed;
  double _landed = 0.0;

  /// How much has left as drops, in cubic metres.
  double get dropped => _dropped;
  double _dropped = 0.0;

  /// How much is in the air, in cubic metres.
  double get inFlight => _parcels.fold(0.0, (s, p) => s + p.volume);

  /// Whether any of it is in the air.
  bool get isFlowing => _parcels.isNotEmpty;

  /// Liquid leaving a lip at [point] at [velocity] for [dt] seconds at
  /// [flow] cubic metres a second, as a sheet [width] wide across [across].
  void emit({
    required double flow,
    required double dt,
    required Vector3 point,
    required Vector3 velocity,
    required double width,
    required Vector3 across,
    FluidMedium? medium,
    Map<String, double> concentrations = const {},
  }) {
    final volume = flow * dt;
    if (volume <= 0.0) {
      // A gap: what follows is a new stream, not this one carried on.
      if (_parcels.isNotEmpty) _parcels.last.endsRun = true;
      return;
    }
    _emitted += volume;
    final speed = math.max(velocity.length, 1e-6);
    final w = math.max(width, 1e-6);
    _parcels.add(
      _Parcel(
        position: point.clone(),
        velocity: velocity.clone(),
        volume: volume,
        dt: dt,
        width: w,
        sheet: flow / (speed * w),
        across: across.clone()..normalize(),
        medium: medium ?? this.medium,
        concentrations: concentrations,
      ),
    );
  }

  /// Moves every parcel on by [dt] under [gravity], against [obstacles],
  /// into [receivers]; returns the drops it broke into.
  ///
  /// The flight is the [solver]'s; where a parcel lands and whether it
  /// parts are worked out here, the same on every backend.
  List<JetDrop> step(
    double dt, {
    required Vector3 gravity,
    List<JetObstacle> obstacles = const [],
    List<JetReceiver> receivers = const [],
  }) {
    final drops = <JetDrop>[];
    if (_parcels.isNotEmpty) {
      // Every parcel, and as far as any moves this step, in one ball.
      final low = _parcels.first.position.clone();
      final high = low.clone();
      var travel = 0.0;
      for (final p in _parcels) {
        Vector3.min(low, p.position, low);
        Vector3.max(high, p.position, high);
        final speed = p.velocity.length + gravity.length * dt;
        travel = math.max(travel, speed * dt + math.sqrt(p.section / math.pi));
      }
      final walls = obstaclesNear(
        obstacles,
        (low + high) * 0.5,
        (high - low).length * 0.5 + travel + 0.01,
      );
      _fly(dt, gravity, walls);
    }
    // Landed, broken: out of the stream, each by its own account.
    final kept = <_Parcel>[];
    for (final p in _parcels) {
      JetReceiver? into;
      // Anywhere along the way it came this step, a radius at a time: what
      // passes the surface of a liquid between one step and the next has
      // landed in it.
      final radius = math.sqrt(p.section / math.pi);
      final way = p.position - p.previous;
      final looks = (way.length / radius).ceil().clamp(1, 16);
      search:
      for (var k = 1; k <= looks; k++) {
        final at = p.previous + way * (k / looks);
        for (final r in receivers) {
          if (r.catches(at, radius)) {
            into = r;
            break search;
          }
        }
      }
      if (into != null) {
        // Struck hard enough, part of it splashes back out (Mundo).
        final splash = _splashShare(p);
        final stays = p.volume * (1.0 - splash);
        if (splash > 0.0) {
          final up = gravity.length2 > 0.0
              ? -gravity.normalized()
              : Vector3(0, 1, 0);
          final side = up.cross(
            up.x.abs() < 0.9 ? Vector3(1, 0, 0) : Vector3(0, 0, 1),
          )..normalize();
          final other = up.cross(side);
          final speed = 0.3 * p.velocity.length;
          const crown = 8;
          for (var k = 0; k < crown; k++) {
            final a = 2.0 * math.pi * (k + 0.5) / crown;
            final out =
                (side * Portable.cos(a) + other * Portable.sin(a)) * 0.6 +
                up * 0.8;
            drops.add((
              position: p.position.clone(),
              velocity: out.normalized() * speed,
              volume: p.volume * splash / crown,
              medium: p.medium,
              concentrations: p.concentrations,
            ));
          }
          _dropped += p.volume * splash;
        }
        into.receive(stays, p.position, p.velocity, p.medium, p.concentrations);
        _landed += stays;
        if (kept.isNotEmpty) kept.last.endsRun = true;
        continue;
      }
      // A rivulet on a wall does not part: the wall holds it.
      if (!p.onWall && p.growth >= breakupGrowth) {
        // Drops of 1.89 diameters, as many as its volume makes.
        final d = 2.0 * math.sqrt(p.section / math.pi) * 1.89;
        final one = math.pi * d * d * d / 6.0;
        final count = math.max(1, (p.volume / one).round());
        for (var k = 0; k < count; k++) {
          drops.add((
            position: p.position.clone(),
            velocity: p.velocity.clone(),
            volume: p.volume / count,
            medium: p.medium,
            concentrations: p.concentrations,
          ));
        }
        _dropped += p.volume;
        if (kept.isNotEmpty) kept.last.endsRun = true;
        continue;
      }
      kept.add(p);
    }
    _parcels
      ..clear()
      ..addAll(kept);
    return drops;
  }

  /// Every parcel through the air for [dt], by the [solver]: written out as
  /// [ParcelFlight] records and read back.
  void _fly(double dt, Vector3 gravity, List<JetObstacle> walls) {
    const stride = ParcelFlight.parcelFloats;
    final records = Float64List(_parcels.length * stride);
    for (var i = 0; i < _parcels.length; i++) {
      final p = _parcels[i];
      final at = i * stride;
      for (var k = 0; k < 3; k++) {
        records[at + ParcelFlight.position + k] = p.position[k];
        records[at + ParcelFlight.velocity + k] = p.velocity[k];
      }
      records
        ..[at + ParcelFlight.volume] = p.volume
        ..[at + ParcelFlight.emittedIn] = p.dt
        ..[at + ParcelFlight.age] = p.age
        ..[at + ParcelFlight.growth] = p.growth
        ..[at + ParcelFlight.onWall] = p.onWall ? 1.0 : 0.0
        ..[at + ParcelFlight.density] = p.medium.density
        ..[at + ParcelFlight.tension] = p.medium.surfaceTension
        ..[at + ParcelFlight.viscosity] = p.medium.viscosity;
    }
    solver.flyParcels(
      ParcelFlight(
        parcels: records,
        dt: dt,
        gravity: gravity,
        medium: medium,
        walls: walls,
      ),
    );
    for (var i = 0; i < _parcels.length; i++) {
      final p = _parcels[i];
      final at = i * stride;
      for (var k = 0; k < 3; k++) {
        p.position[k] = records[at + ParcelFlight.position + k];
        p.velocity[k] = records[at + ParcelFlight.velocity + k];
        p.previous[k] = records[at + ParcelFlight.previous + k];
      }
      p
        ..age = records[at + ParcelFlight.age]
        ..growth = records[at + ParcelFlight.growth]
        ..onWall = records[at + ParcelFlight.onWall] != 0.0;
    }
  }

  /// The stream as runs of samples, lip first: each run is a stretch with
  /// nothing missing from it, ready to be swept into a tube.
  List<List<JetSample>> get runs {
    final out = <List<JetSample>>[];
    var run = <JetSample>[];
    for (var i = _parcels.length - 1; i >= 0; i--) {
      final p = _parcels[i];
      // A break between this parcel and the newer ones already in the run.
      if (p.endsRun && run.isNotEmpty) {
        if (run.length > 1) out.add(run);
        run = <JetSample>[];
      }
      final section = p.section;
      final round = math.sqrt(section / math.pi);
      final retract = math.sqrt(
        2.0 *
            p.medium.surfaceTension /
            (p.medium.density * math.max(p.sheet, 1e-6)),
      );
      final wide = p.onWall
          ? math.sqrt(2.0) * round
          : math.max(0.5 * p.width - retract * p.age, round);
      run.add((
        position: p.position.clone(),
        direction: p.velocity.normalized(),
        across: p.across.clone(),
        wide: wide,
        thick: section / (math.pi * wide),
      ));
    }
    if (run.length > 1) out.add(run);
    return out;
  }
}

/// The fastest a film [thickness] thick of [medium] runs along a wall it
/// wets and stays on it: [Jet.clingSpeed].
double _clingSpeed(FluidMedium medium, double thickness) => math.sqrt(
  medium.surfaceTension *
      (1.0 + Portable.cos(medium.contactAngle)) /
      (medium.density * math.max(thickness, 1e-9)),
);

/// [flight] flown in Dart: what [DartFluid.flyParcels] does.
void flyParcelsInDart(ParcelFlight flight) {
  final records = flight.parcels;
  final dt = flight.dt;
  final gravity = flight.gravity;
  final walls = flight.walls;
  const stride = ParcelFlight.parcelFloats;
  for (var i = 0; i < flight.count; i++) {
    final at = i * stride;
    Vector3 read(int offset) => Vector3(
      records[at + offset],
      records[at + offset + 1],
      records[at + offset + 2],
    );
    final position = read(ParcelFlight.position);
    final velocity = read(ParcelFlight.velocity);
    final volume = records[at + ParcelFlight.volume];
    final emittedIn = records[at + ParcelFlight.emittedIn];
    final rho = records[at + ParcelFlight.density];
    final sigma = records[at + ParcelFlight.tension];
    final mu = records[at + ParcelFlight.viscosity];
    var onWall = records[at + ParcelFlight.onWall] != 0.0;
    velocity.addScaled(gravity, dt);
    final previous = position.clone();
    records[at + ParcelFlight.age] += dt;
    final section = volume / (math.max(velocity.length, 1e-6) * emittedIn);
    final radius = math.sqrt(section / math.pi);
    var touched = false;
    // **In pieces no longer than its own radius**, held by the walls after
    // each. A stream falls five millimetres a step into a test tube whose
    // glass is half a millimetre: moved in one go, a parcel above the
    // bottom of an empty tube was under its glass a step later, and broke
    // into drops beneath the tube.
    final pieces = (velocity.length * dt / radius).ceil().clamp(1, 16);
    for (var k = 0; k < pieces; k++) {
      position.addScaled(velocity, dt / pieces);
      for (final wall in walls) {
        final hit = wall.touch(position, radius);
        if (hit == null) continue;
        position.addScaled(hit.normal, hit.depth);
        final into = velocity.dot(hit.normal);
        if (into < 0.0) velocity.addScaled(hit.normal, -into);
        onWall = true;
        touched = true;
      }
    }
    // Off the wall this step: held to it while surface tension outweighs
    // its inertia, let go when it does not.
    if (onWall && !touched) {
      // Still touching, sliding along: on the wall at any speed. Drawn a
      // little off it: pulled back while slow enough to cling.
      final contact = 0.1 * radius;
      final reach = 2.0 * radius;
      var held = false;
      for (final wall in walls) {
        final near = wall.touch(position, radius + contact);
        if (near != null) {
          held = true;
          break;
        }
      }
      if (!held && velocity.length < _clingSpeed(flight.medium, 2.0 * radius)) {
        for (final wall in walls) {
          final hit = wall.touch(position, radius + reach);
          if (hit == null) continue;
          position.addScaled(hit.normal, hit.depth - reach);
          final away = velocity.dot(hit.normal);
          if (away > 0.0) velocity.addScaled(hit.normal, -away);
          held = true;
          break;
        }
      }
      onWall = held;
    }
    // Weber's growth of the ripples on it, at its own diameter.
    if (!onWall) {
      final d = 2.0 * radius;
      final tau = math.sqrt(rho * d * d * d / sigma) + 3.0 * mu * d / sigma;
      records[at + ParcelFlight.growth] += dt / tau;
    }
    for (var k = 0; k < 3; k++) {
      records[at + ParcelFlight.position + k] = position[k];
      records[at + ParcelFlight.velocity + k] = velocity[k];
      records[at + ParcelFlight.previous + k] = previous[k];
    }
    records[at + ParcelFlight.onWall] = onWall ? 1.0 : 0.0;
  }
}

final class _Parcel {
  _Parcel({
    required this.position,
    required this.velocity,
    required this.volume,
    required this.dt,
    required this.width,
    required this.sheet,
    required this.across,
    required this.medium,
    required this.concentrations,
  });

  /// What it is: which liquid, and what is dissolved in it.
  final FluidMedium medium;
  final Map<String, double> concentrations;

  final Vector3 position;
  final Vector3 velocity;

  /// How much liquid it is, in cubic metres.
  final double volume;

  /// The step it left in: its length along the stream is its speed times
  /// this, so its section is its volume over that.
  final double dt;

  /// How wide and thick a sheet it left as, and which way across. In
  /// metres.
  final double width;

  /// How thick a sheet it left as, in metres.
  final double sheet;
  final Vector3 across;

  /// How long it has been in the air, in seconds.
  double age = 0.0;

  /// How far its ripples have grown: a unitless count of e-foldings.
  double growth = 0.0;
  bool onWall = false;

  /// Where it was at the start of the step.
  final Vector3 previous = Vector3.zero();

  /// Whether the stream breaks between this parcel and the next one to
  /// have left the lip.
  bool endsRun = false;

  /// Its cross-section along the stream, in square metres.
  double get section => volume / (math.max(velocity.length, 1e-6) * dt);
}
