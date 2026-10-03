import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'atmosphere.dart';
import 'fluid_medium.dart';
import 'wetting.dart';

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

  /// Whether anything within [distance] of [centre] (world) could be
  /// caught: false only when it certainly cannot. What a parcel asks
  /// first, so the receivers far from it are not asked at every point of
  /// its way.
  bool reaches(Vector3 centre, double distance);

  /// Whether a drop of [radius] at [point] (world) touches this receiver's
  /// glass from inside it: water wets glass, and a drop held there by the
  /// wall runs down into the liquid as a film.
  bool wets(Vector3 point, double radius);

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

  /// Whether anything within [distance] of [centre] (world) could touch
  /// this obstacle: false only when it certainly cannot. Asked once a step
  /// for everything in flight together, so the walls far from it are not
  /// asked again for each parcel, piece and pass.
  bool reaches(Vector3 centre, double distance);

  /// What it is made of: how a liquid wets it, and how hard its edge holds
  /// a drop.
  SolidSurface get solid;
}

/// [obstacles] that something within [distance] of [centre] could touch.
List<JetObstacle> obstaclesNear(
  List<JetObstacle> obstacles,
  Vector3 centre,
  double distance,
) => [
  for (final o in obstacles)
    if (o.reaches(centre, distance)) o,
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
    _fresh = true;
    final speed = math.max(velocity.length, 1e-6);
    final w = math.max(width, 1e-6);
    // **Laminar or turbulent, from how it leaves.** Under a Reynolds number
    // of 2300 the stream is smooth, and parts where its own ripples have
    // grown e¹² times, as [breakupGrowth] counts. Past 4000 it leaves the
    // lip already disturbed, and parts sooner, at L/D = 8.51·We^0.32
    // (Grant and Middleman, 1966, for turbulent jets). Between the two the
    // length runs from one correlation to the other with Re.
    final m = medium ?? this.medium;
    final d = 2.0 * math.sqrt(flow / (speed * math.pi));
    final re = m.density * speed * d / m.viscosity;
    var intact = double.infinity;
    if (re > 2300.0 && m.surfaceTension > 0.0) {
      final we = m.density * speed * speed * d / m.surfaceTension;
      final laminar = 12.0 * d * (math.sqrt(we) + 3.0 * we / re);
      final turbulent = 8.51 * d * Portable.pow(we, 0.32);
      final t = ((re - 2300.0) / 1700.0).clamp(0.0, 1.0);
      intact = laminar + t * (turbulent - laminar);
    }
    _parcels.add(
      _Parcel(
        intact: intact,
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
    Atmosphere? air,
    Vector3 Function(Vector3 point)? gravityAt,
  }) {
    final drops = <JetDrop>[];
    _retract(dt);
    var walls = obstacles;
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
      walls = obstaclesNear(
        obstacles,
        (low + high) * 0.5,
        (high - low).length * 0.5 + travel + 0.01,
      );
    }
    for (var i = 0; i < _parcels.length; i++) {
      final p = _parcels[i];
      final rho = p.medium.density;
      final sigma = p.medium.surfaceTension;
      final mu = p.medium.viscosity;
      // Its own gravity, where it is, when gravity is not one vector.
      p.velocity.addScaled(gravityAt?.call(p.position) ?? gravity, dt);
      p.previous.setFrom(p.position);
      p.age += dt;
      p.travelled += p.velocity.length * dt;
      final section = p.section;
      final radius = math.sqrt(section / math.pi);
      var touched = false;
      // **The air across it**, as on a long cylinder: what blows across a
      // stream bends it, at ½·C_d·ρ_a·u⊥²·d a metre over its ρ·πd²/4,
      // White's C_d for a cylinder. Along it the air only rubs, a skin
      // friction that over the centimetres of a pour comes to nothing.
      if (air != null && !p.onWall && radius > 0.0) {
        final speed = p.velocity.length;
        final u = p.velocity - air.windAt(p.position);
        if (speed > 0.0) {
          u.addScaled(p.velocity, -u.dot(p.velocity) / (speed * speed));
        }
        final across = u.length;
        if (across > 0.0) {
          final d = 2.0 * radius;
          final re = air.density * across * d / air.viscosity;
          final k =
              -2.0 *
              Atmosphere.cylinderDrag(re) *
              air.density *
              across /
              (math.pi * rho * d);
          p.velocity.addScaled(u, k * dt);
        }
      }
      // Its own walls: within what it moves this step and the three radii a
      // clinging parcel is looked for by. Every wall near the whole stream,
      // asked for every piece of every parcel, cost the tail of a pour a
      // third of a frame.
      final near = obstaclesNear(
        walls,
        p.position,
        p.velocity.length * dt + 3.0 * radius,
      );
      // **In pieces no longer than its own radius**, held by the walls after
      // each. A stream falls five millimetres a step into a test tube whose
      // glass is half a millimetre: moved in one go, a parcel above the
      // bottom of an empty tube was under its glass a step later, and broke
      // into drops beneath the tube.
      final pieces = (p.velocity.length * dt / radius).ceil().clamp(1, 16);
      for (var k = 0; k < pieces; k++) {
        p.position.addScaled(p.velocity, dt / pieces);
        for (final wall in near) {
          final hit = wall.touch(p.position, radius);
          if (hit == null) continue;
          p.position.addScaled(hit.normal, hit.depth);
          final into = p.velocity.dot(hit.normal);
          if (into < 0.0) p.velocity.addScaled(hit.normal, -into);
          p.onWall = true;
          touched = true;
        }
      }
      // Off the wall this step: held to it while surface tension outweighs
      // its inertia, let go when it does not.
      if (p.onWall && !touched) {
        // Still touching, sliding along: on the wall at any speed. Drawn a
        // little off it: pulled back while slow enough to cling.
        final contact = 0.1 * radius;
        final reach = 2.0 * radius;
        var held = false;
        for (final wall in near) {
          final near = wall.touch(p.position, radius + contact);
          if (near != null) {
            held = true;
            break;
          }
        }
        if (!held && p.velocity.length < clingSpeed(2.0 * radius)) {
          for (final wall in near) {
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
      // Anywhere along the way it came this step, a radius at a time: what
      // passes the surface of a liquid between one step and the next has
      // landed in it.
      final radius = math.sqrt(p.section / math.pi);
      final way = p.position - p.previous;
      final looks = (way.length / radius).ceil().clamp(1, 16);
      // Only the receivers its way passes near: every point of every
      // parcel's way asked of every glass on the bench was a third of a
      // pour's cost.
      final middle = (p.position + p.previous)..scale(0.5);
      final near = [
        for (final r in receivers)
          if (r.reaches(middle, 0.5 * way.length + radius)) r,
      ];
      search:
      for (var k = 1; k <= looks && near.isNotEmpty; k++) {
        // One point moved along, not one made per look.
        final at = _look
          ..setFrom(way)
          ..scale(k / looks)
          ..add(p.previous);
        for (final r in near) {
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
      if (!p.onWall && (p.growth >= breakupGrowth || p.travelled >= p.intact)) {
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

  final Vector3 _look = Vector3.zero();

  /// Whether anything left the lip since the last step: the newest parcel
  /// is held to the lip while it does, and its end is free once it stops.
  bool _fresh = false;

  /// **A free end draws back into the stream** (Keller, 1983): surface
  /// tension pulls a thread's end in at √(σ/ρr), gathering what it passes
  /// into a bulb. The upper end of a stretch held neither by the lip nor by
  /// a wall gives as much of its liquid to its neighbour as that speed
  /// covers of its length in the step, and goes once it has given it all.
  /// Without it the tail of a pour, cut off as the glass came back up, fell
  /// whole, as wide at its end as anywhere, like a bent rod of glass.
  void _retract(double dt) {
    final fresh = _fresh;
    _fresh = false;
    bool newerFree(int i) =>
        (i == _parcels.length - 1 && !fresh) || _parcels[i].endsRun;
    bool olderFree(int i) => i == 0 || _parcels[i - 1].endsRun;
    var i = _parcels.length - 1;
    while (i >= 1) {
      final bulb = _parcels[i];
      if (bulb.onWall || !newerFree(i)) {
        i--;
        continue;
      }
      // The bulb eats the thread ahead of it at the speed the thread's own
      // radius gives, a parcel at a time, for as long as the step lasts.
      var left = dt;
      while (left > 0.0 && !olderFree(i)) {
        final thread = _parcels[i - 1];
        // The thread's far end is an end too: what is left is a drop.
        if (thread.onWall || olderFree(i - 1)) break;
        final radius = math.sqrt(thread.section / math.pi);
        if (radius <= 0.0) break;
        final speed = math.sqrt(
          thread.medium.surfaceTension / (thread.medium.density * radius),
        );
        final length = math.max(thread.velocity.length, 1e-6) * thread.dt;
        final whole = length / speed;
        final eaten = whole <= left ? 1.0 : left / whole;
        _gather(bulb, thread, thread.volume * eaten);
        left -= whole * eaten;
        if (eaten < 1.0) {
          thread.dt *= 1.0 - eaten;
          break;
        }
        // All of it: the bulb is where it was.
        bulb.position.setFrom(thread.position);
        bulb.previous.setFrom(thread.previous);
        _parcels.removeAt(i - 1);
        i--;
      }
      i--;
    }
  }

  /// [amount] of [from]'s liquid into [into], with its momentum and what is
  /// dissolved in it.
  static void _gather(_Parcel into, _Parcel from, double amount) {
    if (amount <= 0.0) return;
    final total = into.volume + amount;
    into.velocity
      ..scale(into.volume / total)
      ..addScaled(from.velocity, amount / total);
    into.concentrations = {
      for (final k in {
        ...into.concentrations.keys,
        ...from.concentrations.keys,
      })
        k:
            ((into.concentrations[k] ?? 0.0) * into.volume +
                (from.concentrations[k] ?? 0.0) * amount) /
            total,
    };
    into.volume = total;
    from.volume -= amount;
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
    required this.intact,
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
  Map<String, double> concentrations;

  final Vector3 position;
  final Vector3 velocity;
  double volume;

  /// The step it left in: its length along the stream is its speed times
  /// this, so its section is its volume over that. Shortened as a bulb
  /// eats into it, which leaves its section as it was.
  double dt;

  /// How wide and thick a sheet it left as, and which way across.
  final double width;
  final double sheet;
  final Vector3 across;

  double age = 0.0;
  double growth = 0.0;

  /// How far it has come from the lip, and how far a stream that left as
  /// it did goes before it parts: infinite for a laminar one, which parts
  /// by [growth] instead.
  double travelled = 0.0;
  final double intact;
  bool onWall = false;

  /// Where it was at the start of the step.
  final Vector3 previous = Vector3.zero();

  /// Whether the stream breaks between this parcel and the next one to
  /// have left the lip.
  bool endsRun = false;

  double get section => volume / (math.max(velocity.length, 1e-6) * dt);
}
