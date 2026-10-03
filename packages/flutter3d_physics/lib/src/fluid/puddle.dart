import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'atmosphere.dart';
import 'fluid_medium.dart';
import 'jet.dart';
import 'particle_fluid.dart';
import 'wetting.dart';

/// Liquid lying on a flat surface: a drop or a puddle, as one body.
///
/// **Its shape is surface tension's and gravity's.** Spread out, a puddle
/// is as deep as the capillary length and the contact angle make it,
/// h = 2ℓc·sin(θ/2) with ℓc = √(σ/ρg) (de Gennes, Brochard-Wyart and Quéré,
/// *Capillarity and Wetting Phenomena*, §2.1.2): wider and it would thin
/// past what surface tension holds at its edge, narrower and gravity
/// flattens it further. Smaller than that, it is a drop, a spherical cap
/// meeting the surface at θ. Whichever is wider is what it is: the cap
/// while it is small, the puddle once its weight counts.
///
/// **It gets there as a viscous gravity current.** A volume V let go on a
/// plane spreads as R(t) = 0.894·(ρgV³/3μ)^⅛·t^⅛ (Huppert, 1982); it stops
/// where it reaches its shape. Water reaches it in milliseconds; honey
/// takes its time.
final class Puddle {
  Puddle({
    required this.medium,
    required this.centre,
    required this.normal,
    double? angle,
  }) : angle = angle ?? medium.contactAngle;

  final FluidMedium medium;

  /// The angle it meets the surface at, radians: the surface's for this
  /// liquid ([SolidSurface.angleFor]). Water beads on a lacquered bench
  /// and spreads on glass.
  final double angle;

  /// Its middle, on the surface.
  final Vector3 centre;

  /// The surface's normal, away from it.
  final Vector3 normal;

  double _volume = 0.0;
  final Map<String, double> _amounts = {};

  /// Seconds since it was first wetted, as a gravity current counts them.
  double age = 0.0;

  /// Cubic metres in it.
  double get volume => _volume;

  /// What is dissolved in it, as concentrations.
  Map<String, double> get concentrations => _volume <= 0.0
      ? const {}
      : {for (final e in _amounts.entries) e.key: e.value / _volume};

  /// Adds [volume] carrying [concentrations], landing at [point]: the
  /// middle moves to the centre of what it holds.
  void add(double volume, Vector3 point, Map<String, double> concentrations) {
    if (volume <= 0.0) return;
    final onPlane = point - normal * normal.dot(point - centre);
    final total = _volume + volume;
    centre.setFrom(centre * (_volume / total) + onPlane * (volume / total));
    _volume = total;
    concentrations.forEach((k, c) {
      _amounts[k] = (_amounts[k] ?? 0.0) + c * volume;
    });
  }

  /// [other] taken in, whole.
  void merge(Puddle other) {
    final total = _volume + other._volume;
    if (total <= 0.0) return;
    centre.setFrom(
      centre * (_volume / total) + other.centre * (other._volume / total),
    );
    _volume = total;
    other._amounts.forEach((k, a) => _amounts[k] = (_amounts[k] ?? 0.0) + a);
    age = math.max(age, other.age);
  }

  /// **What evaporates from it in [dt]** into [air], cubic metres, taken
  /// from its solvent: what is dissolved stays behind in less liquid.
  ///
  /// In still air vapour diffuses away from a sessile drop at
  /// π·R·D·Δc·(0.27θ² + 1.30) kilograms a second, R its radius and θ its
  /// contact angle (Hu and Larson, 2002); at θ → 0 that is the flat disc's
  /// 4·R·D·Δc. In a wind the vapour is carried off over it as from a flat
  /// plate 2R long: a laminar boundary layer's mean Sherwood number
  /// 0.664·Re^½·Sc^⅓. Whichever takes it faster does.
  double evaporate(double dt, Atmosphere air, double g) {
    if (_volume <= 0.0) return 0.0;
    final deficit = air.vapourDeficit(medium);
    if (deficit <= 0.0) return 0.0;
    final r = radius(g);
    if (r <= 0.0) return 0.0;
    final d = air.vapourDiffusivity;
    final theta = angle.clamp(0.0, math.pi / 2);
    final still = math.pi * r * d * deficit * (0.27 * theta * theta + 1.30);
    final across = air.windAt(centre)
      ..addScaled(normal, -air.windAt(centre).dot(normal));
    final length = 2.0 * r;
    final re = air.density * across.length * length / air.viscosity;
    final sc = air.viscosity / (air.density * d);
    final sherwood = 0.664 * math.sqrt(re) * Portable.pow(sc, 1.0 / 3.0);
    final carried = sherwood * d / length * deficit * math.pi * r * r;
    final gone = math.min(
      math.max(still, carried) / medium.density * dt,
      _volume,
    );
    _volume -= gone;
    return gone;
  }

  /// How far it reaches across the surface, metres.
  double radius(double g) {
    if (_volume <= 0.0) return 0.0;
    final rest = restRadius(g);
    if (medium.viscosity <= 0.0 || age <= 0.0) return rest;
    final current =
        0.894 *
        Portable.pow(
          medium.density *
              g *
              _volume *
              _volume *
              _volume /
              (3.0 * medium.viscosity),
          0.125,
        ) *
        Portable.pow(age, 0.125);
    return math.min(rest, current.toDouble());
  }

  /// Its radius once it has stopped spreading: the cap's or the puddle's,
  /// whichever is wider.
  double restRadius(double g) {
    if (_volume <= 0.0) return 0.0;
    final theta = angle.clamp(0.05, math.pi - 0.05);
    final s = Portable.sin(theta);
    final c = Portable.cos(theta);
    // A spherical cap of base R meeting the plane at θ holds
    // πR³(2 − 3cosθ + cos³θ)/(3sin³θ).
    final cap = math
        .pow(
          3.0 * _volume * s * s * s / (math.pi * (2.0 - 3.0 * c + c * c * c)),
          1.0 / 3.0,
        )
        .toDouble();
    final capillary = math.sqrt(
      medium.surfaceTension / (medium.density * math.max(g, 1e-9)),
    );
    final deep = 2.0 * capillary * Portable.sin(theta / 2.0);
    final flat = math.sqrt(_volume / (math.pi * deep));
    return math.max(cap, flat);
  }

  /// The height of a spherical cap of base [radius] holding what it holds:
  /// what it is drawn as. A flat puddle drawn so is a lens twice as deep
  /// in the middle as it is on average, and holds the same.
  double capHeight(double radius) {
    if (_volume <= 0.0 || radius <= 0.0) return 0.0;
    // V = πH(3R² + H²)/6, solved for H by Newton from the flat guess.
    var h = 2.0 * _volume / (math.pi * radius * radius);
    for (var i = 0; i < 8; i++) {
      final f = math.pi * h * (3.0 * radius * radius + h * h) / 6.0 - _volume;
      final df = math.pi * (radius * radius + h * h) / 2.0;
      h -= f / df;
    }
    return math.max(h, 0.0);
  }
}

/// A flat surface's puddles: everything that reaches the surface becomes
/// one, or joins the one it lands in.
///
/// A receiver like a vessel: a stream that runs onto the bench lands in
/// it, and so does a drop. Liquid on the bench is then a few bodies, each
/// its volume and what is dissolved in it, and not thousands of particles
/// to step and draw.
final class PuddleSurface implements JetReceiver {
  PuddleSurface(this.surface);

  final PlaneObstacle surface;

  final List<Puddle> puddles = [];

  /// The gravity the puddles last spread under.
  double _g = 9.81;

  /// Cubic metres lying here.
  double get volume => puddles.fold(0.0, (s, p) => s + p.volume);

  @override
  bool catches(Vector3 point, double radius) =>
      // What rests on the surface rests a radius off it; a quarter of one
      // more, as a vessel's floor allows.
      surface.normal.dot(point) - surface.offset <= 1.25 * radius;

  @override
  bool wets(Vector3 point, double radius) => false;

  @override
  bool reaches(Vector3 centre, double distance) =>
      surface.reaches(centre, distance);

  @override
  void receive(
    double volume,
    Vector3 point,
    Vector3 velocity,
    FluidMedium medium,
    Map<String, double> concentrations,
  ) {
    final onPlane =
        point - surface.normal * (surface.normal.dot(point) - surface.offset);
    // Into a puddle it lands on, or the start of a new one.
    Puddle? into;
    for (final p in puddles) {
      if (p.medium.name != medium.name) continue;
      if ((p.centre - onPlane).length <= p.radius(_g)) {
        into = p;
        break;
      }
    }
    into ??= () {
      final made = Puddle(
        medium: medium,
        centre: onPlane.clone(),
        normal: surface.normal.clone(),
        angle: surface.solid.angleFor(medium),
      );
      puddles.add(made);
      return made;
    }();
    into.add(volume, onPlane, concentrations);
    _join();
  }

  /// What evaporates from every puddle in [dt] into [air], cubic metres;
  /// a puddle dried out is gone.
  double evaporate(double dt, Atmosphere air) {
    var gone = 0.0;
    for (final p in puddles) {
      gone += p.evaporate(dt, air, _g);
    }
    puddles.removeWhere((p) => p.volume <= 0.0);
    return gone;
  }

  /// Spreads every puddle on by [dt] under [gravity], and runs together
  /// those that meet.
  void step(double dt, {required Vector3 gravity}) {
    _g = math.max(-gravity.dot(surface.normal), 0.0);
    if (puddles.isEmpty) return;
    for (final p in puddles) {
      p.age += dt;
    }
    _join();
  }

  void _join() {
    var joined = true;
    while (joined) {
      joined = false;
      outer:
      for (var i = 0; i < puddles.length; i++) {
        for (var j = i + 1; j < puddles.length; j++) {
          final a = puddles[i];
          final b = puddles[j];
          if (a.medium.name != b.medium.name) continue;
          if ((a.centre - b.centre).length < a.radius(_g) + b.radius(_g)) {
            a.merge(b);
            puddles.removeAt(j);
            joined = true;
            break outer;
          }
        }
      }
    }
  }
}
