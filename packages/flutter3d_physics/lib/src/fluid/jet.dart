import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'fluid_medium.dart';

/// When something thrown at [velocity] from [height] reaches [floor] under
/// gravity [g] pointing down: the later root of height + v_y·t − g t²/2 =
/// floor. For aiming a stream: how far it is carried while it falls.
double fallTime(
  Vector3 velocity,
  double height,
  double floor, {
  double g = 9.81,
}) {
  final drop = math.max(height - floor, 0.0);
  return (velocity.y + math.sqrt(velocity.y * velocity.y + 2.0 * g * drop)) / g;
}

/// Something a stream can land in — a vessel's liquid.
abstract interface class JetReceiver {
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
abstract interface class JetObstacle {
  /// Where a parcel of [radius] at [point] (world) is into this obstacle:
  /// the way out and how far, or null when it is clear of it.
  ({Vector3 normal, double depth})? touch(Vector3 point, double radius);
}

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
  Jet({required this.medium, this.breakupGrowth = 12.0});

  /// The liquid a parcel is when [emit] is not told otherwise, and the one
  /// [clingSpeed] answers for.
  final FluidMedium medium;

  /// How many e-foldings of growth part the stream.
  final double breakupGrowth;

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
  double clingSpeed(double thickness) => math.sqrt(
    medium.surfaceTension *
        (1.0 + Portable.cos(medium.contactAngle)) /
        (medium.density * math.max(thickness, 1e-9)),
  );

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
  double get emitted => _emitted;
  double _emitted = 0.0;
  double get landed => _landed;
  double _landed = 0.0;

  /// How much has left as drops.
  double get dropped => _dropped;
  double _dropped = 0.0;

  /// How much is in the air.
  double get inFlight => _parcels.fold(0.0, (s, p) => s + p.volume);

  /// Whether any of it is in the air.
  bool get flowing => _parcels.isNotEmpty;

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
  List<JetDrop> step(
    double dt, {
    required Vector3 gravity,
    List<JetObstacle> obstacles = const [],
    List<JetReceiver> receivers = const [],
  }) {
    final drops = <JetDrop>[];
    for (var i = 0; i < _parcels.length; i++) {
      final p = _parcels[i];
      final rho = p.medium.density;
      final sigma = p.medium.surfaceTension;
      final mu = p.medium.viscosity;
      p.velocity.addScaled(gravity, dt);
      p.position.addScaled(p.velocity, dt);
      p.age += dt;
      final section = p.section;
      final radius = math.sqrt(section / math.pi);
      var touched = false;
      for (final wall in obstacles) {
        final hit = wall.touch(p.position, radius);
        if (hit == null) continue;
        p.position.addScaled(hit.normal, hit.depth);
        final into = p.velocity.dot(hit.normal);
        if (into < 0.0) p.velocity.addScaled(hit.normal, -into);
        p.onWall = true;
        touched = true;
      }
      // Off the wall this step: held to it while surface tension outweighs
      // its inertia, let go when it does not.
      if (p.onWall && !touched) {
        // Still touching, sliding along: on the wall at any speed. Drawn a
        // little off it: pulled back while slow enough to cling.
        final contact = 0.1 * radius;
        final reach = 2.0 * radius;
        var held = false;
        for (final wall in obstacles) {
          final near = wall.touch(p.position, radius + contact);
          if (near != null) {
            held = true;
            break;
          }
        }
        if (!held && p.velocity.length < clingSpeed(2.0 * radius)) {
          for (final wall in obstacles) {
            final hit = wall.touch(p.position, radius + reach);
            if (hit == null) continue;
            p.position.addScaled(hit.normal, hit.depth - reach);
            final away = p.velocity.dot(hit.normal);
            if (away > 0.0) p.velocity.addScaled(hit.normal, -away);
            held = true;
            break;
          }
        }
        p.onWall = held;
      }
      // Weber's growth of the ripples on it, at its own diameter.
      if (!p.onWall) {
        final d = 2.0 * radius;
        final tau = math.sqrt(rho * d * d * d / sigma) + 3.0 * mu * d / sigma;
        p.growth += dt / tau;
      }
    }
    // Landed, broken: out of the stream, each by its own account.
    final kept = <_Parcel>[];
    for (final p in _parcels) {
      JetReceiver? into;
      for (final r in receivers) {
        if (r.catches(p.position, math.sqrt(p.section / math.pi))) {
          into = r;
          break;
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
  final double volume;

  /// The step it left in: its length along the stream is its speed times
  /// this, so its section is its volume over that.
  final double dt;

  /// How wide and thick a sheet it left as, and which way across.
  final double width;
  final double sheet;
  final Vector3 across;

  double age = 0.0;
  double growth = 0.0;
  bool onWall = false;

  /// Whether the stream breaks between this parcel and the next one to
  /// have left the lip.
  bool endsRun = false;

  double get section => volume / (math.max(velocity.length, 1e-6) * dt);
}
