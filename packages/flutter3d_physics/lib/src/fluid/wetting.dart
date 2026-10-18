import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';

import 'fluid_medium.dart';

/// A solid a liquid lies on or runs down, as the liquid meets it: a
/// material of the catalogue, whose `MaterialPair` with each liquid says the
/// angle and how far the edge holds.
///
/// **A contact angle is not one angle.** A drop's edge moving forward meets
/// the solid at the advancing angle θa, drawing back at the receding angle
/// θr, and anywhere between the edge does not move at all: the hysteresis
/// θa − θr is what holds a raindrop still on a window. The force it can
/// hold a drop with is σ·w·(cos θr − cos θa) across a contact w wide
/// (Furmidge, J. Colloid Sci. 17, 1962), and a drop slides when the pull
/// along the solid is more than that.
///
/// **Read from the catalogue's pairs** (`MaterialPair.contactAngle` and
/// `MaterialPair.contactAngleHysteresis`), so a number has one source. On
/// glass, the liquid's own angle stands ([FluidMedium.contactAngle], which
/// is its angle on glass and which a caller may change); where the pair
/// says no hysteresis, [defaultHysteresis] does.
final class SolidSurface {
  /// [material] as liquids meet it, by the pairs in [pairs] — the built-in
  /// ones by default.
  const SolidSurface(this.material, {this.pairs = Materials.pairs});

  /// Laboratory glass ([Materials.glass]): water spreads on it at about
  /// 20° and its edge holds over about 10°.
  static const SolidSurface glass = SolidSurface(Materials.glass);

  /// PTFE ([Materials.ptfe]): water stands up on it at about 110°.
  static const SolidSurface ptfe = SolidSurface(Materials.ptfe);

  /// A phenolic laboratory bench top ([Materials.bakelite]): water beads on
  /// it at about 75° and its edge holds over about 25°.
  static const SolidSurface benchTop = SolidSurface(Materials.bakelite);

  /// The surfaces this version names. Any other material is a surface too
  /// ([SolidSurface.new]); a later version appends.
  static const List<SolidSurface> values = <SolidSurface>[
    glass,
    ptfe,
    benchTop,
  ];

  /// The named surface whose material's id is [name], or null.
  static SolidSurface? byName(String name) {
    for (final surface in values) {
      if (surface.name == name) return surface;
    }
    return null;
  }

  /// Its material's id: `f3d.glass`.
  String get name => material.id;

  /// The hysteresis taken where a pair says none, radians: about 10°, an
  /// estimate of the order measured on smooth clean solids, not one
  /// measurement.
  static const double defaultHysteresis = 0.17;

  /// What the solid is.
  final PhysicalMaterial material;

  /// The pairs the angles are read from.
  final List<MaterialPair> pairs;

  MaterialPair? _pairWith(FluidMedium medium) {
    final liquid = medium.material?.id;
    if (liquid == null) return null;
    final key = MaterialPair.keyOf(liquid, material.id);
    for (final pair in pairs) {
      if (pair.key == key) return pair;
    }
    return null;
  }

  /// [medium]'s angle at rest on this solid, radians: its own on glass, the
  /// pair's on another solid, its own where no pair says.
  double angleFor(FluidMedium medium) {
    if (material.id == Materials.glass.id) return medium.contactAngle;
    return _pairWith(medium)?.contactAngle ?? medium.contactAngle;
  }

  /// How far apart [medium]'s advancing and receding angles are on this
  /// solid, radians.
  double hysteresisFor(FluidMedium medium) =>
      _pairWith(medium)?.contactAngleHysteresis ?? defaultHysteresis;

  /// The angles [medium]'s edge advances and recedes at, radians, about
  /// its angle at rest.
  ({double advancing, double receding}) _anglesFor(FluidMedium medium) {
    final rest = angleFor(medium);
    final spread = 0.5 * hysteresisFor(medium);
    return (
      advancing: math.min(rest + spread, math.pi),
      receding: math.max(rest - spread, 0.0),
    );
  }

  /// The most this solid holds a drop of [medium] [width] wide by its edge,
  /// newtons: σ·w·(cos θr − cos θa).
  double retention(FluidMedium medium, double width) {
    final a = _anglesFor(medium);
    return medium.surfaceTension *
        width *
        (Portable.cos(a.receding) - Portable.cos(a.advancing));
  }

  /// The radius of the circle a drop of [volume] of [medium] wets on this
  /// solid at rest, metres: a spherical cap meeting it at its angle, which
  /// holds πR³(2 − 3cosθ + cos³θ)/(3sin³θ).
  double baseRadius(FluidMedium medium, double volume) =>
      capBaseRadius(volume, angleFor(medium));

  @override
  String toString() => 'SolidSurface(${material.id})';
}

/// The radius of the base of a spherical cap holding [volume] that meets
/// its plane at [angle] radians: πR³(2 − 3cosθ + cos³θ)/(3sin³θ) solved for
/// R. The angle is held a hair inside nought and π, where the cap is a
/// film or a whole sphere.
double capBaseRadius(double volume, double angle) {
  if (volume <= 0.0) return 0.0;
  final theta = angle.clamp(0.05, math.pi - 0.05);
  final s = Portable.sin(theta);
  final c = Portable.cos(theta);
  return Portable.pow(
    3.0 * volume * s * s * s / (math.pi * (2.0 - 3.0 * c + c * c * c)),
    1.0 / 3.0,
  );
}
