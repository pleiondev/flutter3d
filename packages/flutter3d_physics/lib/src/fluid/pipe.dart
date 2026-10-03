import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../portable_math.dart';
import 'liquid_body.dart';

/// A round pipe joining two vessels below their surfaces: communicating
/// vessels.
///
/// **The liquid in it has mass**, so it is not pushed through at once but
/// accelerated: the pressure difference between its ends drives the column
/// — the pipe's own length over its section, and the liquid standing in each
/// vessel above it over the vessel's — and friction holds it back: along
/// the pipe as Darcy's f·(L/D)·ρv²/2, f the [frictionFactor] at the flow's
/// Reynolds number, laminar or turbulent, and as the square of the flow for
/// the losses where it enters and leaves (K·ρQ|Q|/2a²). Two
/// vessels joined this way swing about a common level before they settle on
/// it — a U-tube's period 2π√(l/2g) for a column l long — and a thick liquid
/// creeps to it without swinging.
///
/// **The pressure at each end** is the weight of the liquid above it in the
/// gravity that vessel feels — layer by layer, each at its own density —
/// less the pull of its surface where it is
/// curved: σ times the curvature at the middle of the meniscus, which is why
/// a narrow tube joined to a wide one stands higher by Jurin's height.
final class Pipe {
  Pipe({
    required this.from,
    required this.at,
    required this.to,
    required this.toAt,
    required this.radius,
    required this.length,
    this.minorLoss = 1.5,
    this.roughness = 1.5e-6,
  });

  /// The two vessels, and where the pipe opens into each (vessel frame).
  final LiquidBody from;
  final Vector3 at;
  final LiquidBody to;
  final Vector3 toAt;

  /// The pipe's bore and length, metres.
  final double radius;
  final double length;

  /// The loss where it enters and leaves, in velocity heads: about 0.5 in
  /// and 1 out for sharp ends.
  final double minorLoss;

  /// The height of the bumps on the bore, metres: 1.5 µm, drawn glass and
  /// plastic tubing. What turbulent friction feels; a laminar flow does not.
  final double roughness;

  /// Cubic metres a second from [from] to [to]; negative the other way.
  double flow = 0.0;

  /// The flow's Reynolds number, ρ·v·D/μ: under 2300 laminar, over 4000
  /// turbulent.
  double get reynolds {
    final medium = from.medium;
    final v = flow.abs() / (math.pi * radius * radius);
    return medium.density * v * 2.0 * radius / medium.viscosity;
  }

  /// Darcy's friction factor at Reynolds number [re] in a bore of
  /// [relativeRoughness] ε/D.
  ///
  /// Laminar, Hagen and Poiseuille's 64/Re, exact. Turbulent, Haaland's
  /// explicit form of Colebrook's, 1/√f = −1.8·log₁₀((ε/D/3.7)^1.11 +
  /// 6.9/Re), within a couple of percent of it. Between 2300 and 4000 the
  /// flow is neither, and goes from one to the other with Re: no law
  /// holds there, and a straight line between the two does not pretend to
  /// one.
  static double frictionFactor(double re, {double relativeRoughness = 0.0}) {
    if (re <= 0.0) return double.infinity;
    double turbulent(double re) {
      final x = Portable.pow(relativeRoughness / 3.7, 1.11) + 6.9 / re;
      final inverse = -1.8 * Portable.log(x) / math.ln10;
      return 1.0 / (inverse * inverse);
    }

    final laminar = 64.0 / re;
    if (re <= 2300.0) return laminar;
    if (re >= 4000.0) return turbulent(re);
    final t = (re - 2300.0) / 1700.0;
    return (1.0 - t) * laminar + t * turbulent(re);
  }

  /// Moves the liquid in the pipe on by [dt] under [gravity].
  void step(double dt, {required Vector3 gravity}) {
    final medium = from.medium;
    final rho = medium.density;
    final g = gravity.length;
    if (g <= 0.0) return;
    final a = math.pi * radius * radius;
    final head0 = from.depthAbove(at);
    final head1 = to.depthAbove(toAt);
    // Every layer over each end, at its own density, less the meniscus's
    // pull.
    final p0 = from.pressureAt(at) - from.capillaryPressure;
    final p1 = to.pressureAt(toAt) - to.capillaryPressure;
    // Air cannot be pushed through: a side whose surface is below its end
    // gives nothing.
    if (head0 <= 0.0 && flow > 0.0) flow = 0.0;
    if (head1 <= 0.0 && flow < 0.0) flow = 0.0;
    final inertance =
        rho *
        (length / a +
            math.max(head0, 0.0) / math.max(from.surface.area, a) +
            math.max(head1, 0.0) / math.max(to.surface.area, a));
    // Darcy's loss as a resistance, Δp/Q = f·L·ρ·|Q|/(2·D·a²); laminar it
    // is Poiseuille's 8μL/πr⁴, whatever the flow, and that is what it is
    // at no flow at all.
    final re = reynolds;
    final viscous = re < 1.0
        ? 8.0 *
              medium.viscosity *
              length /
              (math.pi * (radius * radius * radius * radius))
        : frictionFactor(re, relativeRoughness: roughness / (2.0 * radius)) *
              length *
              rho *
              flow.abs() /
              (2.0 * 2.0 * radius * a * a);
    final quadratic = minorLoss * rho * flow.abs() / (2.0 * a * a);
    // Friction taken implicitly, so a thick liquid in a thin pipe is stable
    // at any step.
    var drive = p0 - p1;
    if (head0 <= 0.0 && drive > 0.0) drive = 0.0;
    if (head1 <= 0.0 && drive < 0.0) drive = 0.0;
    flow =
        (flow + dt * drive / inertance) /
        (1.0 + dt * (viscous + quadratic) / inertance);
    // The liquid at each opening goes through: the layer it opens into.
    final moved = flow * dt;
    if (moved > 0.0) {
      from.drawAt(at, moved).forEach(to.add);
    } else if (moved < 0.0) {
      to.drawAt(toAt, -moved).forEach(from.add);
    }
  }
}
