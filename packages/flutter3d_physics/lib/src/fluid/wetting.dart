import 'dart:math' as math;

import '../portable_math.dart';
import 'fluid_medium.dart';

/// A solid a liquid lies on or runs down: how water meets it.
///
/// **A contact angle is not one angle.** A drop's edge moving forward meets
/// the solid at the advancing angle θa, drawing back at the receding angle
/// θr, and anywhere between the edge does not move at all: the hysteresis
/// θa − θr is what holds a raindrop still on a window. The force it can
/// hold a drop with is σ·w·(cos θr − cos θa) across a contact w wide
/// (Furmidge, 1962), and a drop slides when the pull along the solid is
/// more than that.
///
/// The angles here are water's, typical of the clean surface and not of
/// one measurement: a solid's angles move with how it was cleaned, coated
/// and worn. For another liquid the solid's own angles are not known here,
/// and its angle against glass ([FluidMedium.contactAngle]) stands in, with
/// the same hysteresis.
final class SolidSurface {
  const SolidSurface({
    required this.name,
    required this.waterAngle,
    required this.hysteresis,
  });

  /// Clean glass: water spreads on it, 20° (as [FluidMedium.water]), and its
  /// edge holds over about 10°.
  static const SolidSurface glass = SolidSurface(
    name: 'glass',
    waterAngle: 0.35,
    hysteresis: 0.17,
  );

  /// A lacquered or laminate bench top: water beads on it at about 75° and
  /// its edge holds over about 25°.
  static const SolidSurface laminate = SolidSurface(
    name: 'laminate',
    waterAngle: 1.31,
    hysteresis: 0.44,
  );

  /// PTFE: water stands up on it at about 110° and rolls off easily.
  static const SolidSurface ptfe = SolidSurface(
    name: 'ptfe',
    waterAngle: 1.92,
    hysteresis: 0.17,
  );

  final String name;

  /// Water's contact angle at rest, radians.
  final double waterAngle;

  /// The advancing angle less the receding one, radians.
  final double hysteresis;

  /// [medium]'s angle at rest on this solid.
  double angleFor(FluidMedium medium) =>
      medium.vapour?.isWater ?? false ? waterAngle : medium.contactAngle;

  /// The angles [medium]'s edge advances and recedes at.
  ({double advancing, double receding}) anglesFor(FluidMedium medium) {
    final rest = angleFor(medium);
    return (
      advancing: math.min(rest + 0.5 * hysteresis, math.pi),
      receding: math.max(rest - 0.5 * hysteresis, 0.0),
    );
  }

  /// The most this solid holds a drop of [medium] [width] wide by its edge,
  /// newtons: σ·w·(cos θr − cos θa).
  double retention(FluidMedium medium, double width) {
    final a = anglesFor(medium);
    return medium.surfaceTension *
        width *
        (Portable.cos(a.receding) - Portable.cos(a.advancing));
  }

  /// The radius of the circle a drop of [volume] of [medium] wets on this
  /// solid at rest: a spherical cap meeting it at its angle, which holds
  /// πR³(2 − 3cosθ + cos³θ)/(3sin³θ).
  double baseRadius(FluidMedium medium, double volume) {
    final theta = angleFor(medium).clamp(0.05, math.pi - 0.05);
    final s = Portable.sin(theta);
    final c = Portable.cos(theta);
    return Portable.pow(
      3.0 * volume * s * s * s / (math.pi * (2.0 - 3.0 * c + c * c * c)),
      1.0 / 3.0,
    );
  }
}
