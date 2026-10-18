import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

import 'fluid_air.dart';
import 'fluid_medium.dart';
import 'jet.dart';
import 'particle_fluid.dart';
import 'wetting.dart';

/// Liquid lying on a flat surface: a drop or a puddle, as one body.
///
/// **Its shape is surface tension's and gravity's.** Spread out, a puddle
/// is as deep as the capillary length and the contact angle make it,
/// h = 2ℓc·sin(θ/2) with ℓc = √(σ/ρg) (de Gennes, Brochard-Wyart and Quéré,
/// *Capillarity and Wetting Phenomena*, 2004, §2.1.2): wider and it would
/// thin past what surface tension holds at its edge, narrower and gravity
/// flattens it further. Smaller than that, it is a drop, a spherical cap
/// meeting the surface at θ. Whichever is wider is what it is: the cap
/// while it is small, the puddle once its weight counts.
///
/// **It gets there as a viscous gravity current.** A volume V let go on a
/// plane spreads as R(t) = 0.894·(ρgV³/3μ)^⅛·t^⅛ (Huppert, J. Fluid Mech.
/// 121, 1982); it stops where it reaches its shape. Water reaches it in
/// milliseconds; honey takes its time.
final class Puddle {
  /// An empty puddle of [medium] centred at [center] on a surface facing
  /// [normal], meeting it at [angle] radians (the medium's own angle when
  /// not given).
  Puddle({
    required this.medium,
    required Vector3 center,
    required Vector3 normal,
    double? angle,
  }) : center = center.clone(),
       normal = normal.normalized(),
       angle = angle ?? medium.contactAngle;

  /// The liquid it is.
  final FluidMedium medium;

  /// The angle it meets the surface at, radians: the surface's for this
  /// liquid ([SolidSurface.angleFor]). Water beads on a phenolic bench and
  /// spreads on glass.
  final double angle;

  /// Its middle, on the surface; moved as liquid lands in it.
  final Vector3 center;

  /// The surface's normal, away from it.
  final Vector3 normal;

  double _volume = 0.0;
  final Map<String, double> _amounts = {};

  /// Seconds since it was first wetted, as a gravity current counts them.
  double ageSeconds = 0.0;

  /// Cubic metres in it.
  double get volume => _volume;

  /// What is dissolved in it, as concentrations.
  Map<String, double> get concentrations => _volume <= 0.0
      ? const {}
      : {for (final e in _amounts.entries) e.key: e.value / _volume};

  /// Adds [volume] carrying [concentrations], landing at [point]: the
  /// middle moves to the center of what it holds.
  void add(double volume, Vector3 point, Map<String, double> concentrations) {
    if (volume <= 0.0) return;
    final onPlane = point - normal * normal.dot(point - center);
    final total = _volume + volume;
    center.setFrom(center * (_volume / total) + onPlane * (volume / total));
    _volume = total;
    concentrations.forEach((k, c) {
      _amounts[k] = (_amounts[k] ?? 0.0) + c * volume;
    });
  }

  /// [other] taken in, whole.
  void merge(Puddle other) {
    final total = _volume + other._volume;
    if (total <= 0.0) return;
    center.setFrom(
      center * (_volume / total) + other.center * (other._volume / total),
    );
    _volume = total;
    other._amounts.forEach((k, a) => _amounts[k] = (_amounts[k] ?? 0.0) + a);
    ageSeconds = math.max(ageSeconds, other.ageSeconds);
  }

  /// **What evaporates from it in [dt]** into [air] under gravity [g],
  /// cubic metres, taken from its solvent: what is dissolved stays behind
  /// in less liquid.
  ///
  /// In still air vapour diffuses away from a sessile drop at
  /// π·R·D·Δc·(0.27θ² + 1.30) kilograms a second, R its radius and θ its
  /// contact angle (Hu and Larson, J. Phys. Chem. B 106, 2002); at θ → 0
  /// that is the flat disc's 4·R·D·Δc. In a wind the vapour is carried off
  /// over it as from a flat plate 2R long: a laminar boundary layer's mean
  /// Sherwood number 0.664·Re^½·Sc^⅓. Whichever takes it faster does.
  double evaporate(double dt, FluidAir air, double g) {
    if (_volume <= 0.0) return 0.0;
    final deficit = air.vapourDeficit(medium);
    if (deficit <= 0.0) return 0.0;
    final r = radius(g);
    if (r <= 0.0) return 0.0;
    final d = air.vapourDiffusivity;
    final theta = angle.clamp(0.0, math.pi / 2);
    final still = math.pi * r * d * deficit * (0.27 * theta * theta + 1.30);
    final wind = air.windAt(center);
    final across = wind..addScaled(normal, -wind.dot(normal));
    final length = 2.0 * r;
    final density = air.density;
    final re = density * across.length * length / air.viscosity;
    final sc = air.viscosity / (density * d);
    final sherwood = 0.664 * math.sqrt(re) * Portable.pow(sc, 1.0 / 3.0);
    final carried = sherwood * d / length * deficit * math.pi * r * r;
    final gone = math.min(
      math.max(still, carried) / medium.density * dt,
      _volume,
    );
    _volume -= gone;
    return gone;
  }

  /// How far it reaches across the surface under gravity [g], metres: as
  /// far as it has spread, up to its [restRadius].
  double radius(double g) {
    if (_volume <= 0.0) return 0.0;
    final rest = restRadius(g);
    if (medium.viscosity <= 0.0 || ageSeconds <= 0.0) return rest;
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
        Portable.pow(ageSeconds, 0.125);
    return math.min(rest, current);
  }

  /// Its radius once it has stopped spreading under gravity [g], metres:
  /// the cap's or the puddle's, whichever is wider.
  double restRadius(double g) {
    if (_volume <= 0.0) return 0.0;
    final cap = capBaseRadius(_volume, angle);
    final theta = angle.clamp(0.05, math.pi - 0.05);
    final deep =
        2.0 *
        medium.capillaryLength(math.max(g, 1e-9)) *
        Portable.sin(theta / 2.0);
    final flat = math.sqrt(_volume / (math.pi * deep));
    return math.max(cap, flat);
  }

  /// The height of a spherical cap of base [radius] holding what it holds,
  /// metres: what it is drawn as. A flat puddle drawn so is a lens twice as
  /// deep in the middle as it is on average, and holds the same.
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
/// **A receiver, as a vessel is**: a stream that runs onto the bench lands
/// in it, and so do a drop and a spilt particle. Liquid on the bench is
/// then a few bodies, each its volume and what is dissolved in it, and not
/// thousands of particles to step and draw. A `FluidWorld` steps the ones
/// in its `puddles`.
final class PuddleSurface with JetReceiver {
  /// The puddles on [surface], which says what the surface is made of
  /// ([JetObstacle.surface]) and so what angle they meet it at.
  PuddleSurface(this.surface);

  /// The plane they lie on.
  final PlaneObstacle surface;

  /// The puddles on it now.
  final List<Puddle> puddles = [];

  /// The gravity across the surface the puddles last spread under, m/s².
  double _g = standardGravity;

  /// Cubic metres lying here.
  double get volume => puddles.fold(0.0, (s, p) => s + p.volume);

  @override
  bool catches(Vector3 point, double radius) =>
      // What rests on the surface rests a radius off it; a quarter of one
      // more, as a vessel's floor allows.
      surface.normal.dot(point) - surface.offset <= 1.25 * radius;

  @override
  void receive(JetLanding landing) {
    final point = landing.point;
    final medium = landing.medium;
    final onPlane =
        point - surface.normal * (surface.normal.dot(point) - surface.offset);
    // Into a puddle it lands on, or the start of a new one.
    Puddle? into;
    for (final p in puddles) {
      if (p.medium.name != medium.name) continue;
      if ((p.center - onPlane).length <= p.radius(_g)) {
        into = p;
        break;
      }
    }
    into ??= () {
      final made = Puddle(
        medium: medium,
        center: onPlane,
        normal: surface.normal,
        angle: (surface.surface ?? SolidSurface.glass).angleFor(medium),
      );
      puddles.add(made);
      return made;
    }();
    into.add(landing.volume, onPlane, landing.concentrations);
    _join();
  }

  /// What evaporates from every puddle in [dt] into [air], cubic metres; a
  /// puddle dried out is gone.
  double evaporate(double dt, FluidAir air) {
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
      p.ageSeconds += dt;
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
          if ((a.center - b.center).length < a.radius(_g) + b.radius(_g)) {
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
