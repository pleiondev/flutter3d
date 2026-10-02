import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'liquid_body.dart';

/// A round pipe joining two vessels below their surfaces: communicating
/// vessels.
///
/// **The liquid in it has mass**, so it is not pushed through at once but
/// accelerated: the pressure difference between its ends drives the column
/// — the pipe's own length over its section, and the liquid standing in each
/// vessel above it over the vessel's — and friction holds it back, linearly
/// for a slow viscous flow (Hagen–Poiseuille, 8μL/πr⁴) and as the square of
/// the flow for the losses where it enters and leaves (K·ρQ|Q|/2a²). Two
/// vessels joined this way swing about a common level before they settle on
/// it — a U-tube's period 2π√(l/2g) for a column l long — and a thick liquid
/// creeps to it without swinging.
///
/// **The pressure at each end** is the weight of the liquid above it in the
/// gravity that vessel feels, less the pull of its surface where it is
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

  /// Cubic metres a second from [from] to [to]; negative the other way.
  double flow = 0.0;

  /// Moves the liquid in the pipe on by [dt] under [gravity].
  void step(double dt, {required Vector3 gravity}) {
    final medium = from.medium;
    final rho = medium.density;
    final g = gravity.length;
    if (g <= 0.0) return;
    final down = gravity / g;
    final a = math.pi * radius * radius;
    final head0 = from.depthAbove(at, down);
    final head1 = to.depthAbove(toAt, down);
    final p0 = rho * g * head0 - from.capillaryPressure;
    final p1 = rho * g * head1 - to.capillaryPressure;
    // Air cannot be pushed through: a side whose surface is below its end
    // gives nothing.
    if (head0 <= 0.0 && flow > 0.0) flow = 0.0;
    if (head1 <= 0.0 && flow < 0.0) flow = 0.0;
    final inertance =
        rho *
        (length / a +
            math.max(head0, 0.0) / math.max(from.surface.area, a) +
            math.max(head1, 0.0) / math.max(to.surface.area, a));
    final viscous =
        8.0 *
        medium.viscosity *
        length /
        (math.pi * (radius * radius * radius * radius));
    final quadratic = minorLoss * rho * flow.abs() / (2.0 * a * a);
    // Friction taken implicitly, so a thick liquid in a thin pipe is stable
    // at any step.
    var drive = p0 - p1;
    if (head0 <= 0.0 && drive > 0.0) drive = 0.0;
    if (head1 <= 0.0 && drive < 0.0) drive = 0.0;
    flow =
        (flow + dt * drive / inertance) /
        (1.0 + dt * (viscous + quadratic) / inertance);
    var moved = flow * dt;
    if (moved > 0.0) {
      moved = math.min(moved, from.volume);
      from.drain(moved);
      to.pour(moved);
    } else if (moved < 0.0) {
      final back = math.min(-moved, to.volume);
      to.drain(back);
      from.pour(back);
    }
  }
}
