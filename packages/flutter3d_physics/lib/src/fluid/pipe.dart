import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'fluid_solver.dart';
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

  /// Moves the liquid in the pipe on by [dt] under [gravity]. The column is
  /// driven on by [solver] — the reference unless a `FluidWorld` passes the
  /// run's — from the pressures worked out here.
  void step(
    double dt, {
    required Vector3 gravity,
    FluidSolver solver = const DartFluid(),
  }) {
    final medium = from.medium;
    final g = gravity.length;
    if (g <= 0.0) return;
    // Every layer over each end, at its own density, less the meniscus's
    // pull.
    final p0 = from.pressureAt(at) - from.capillaryPressure;
    final p1 = to.pressureAt(toAt) - to.capillaryPressure;
    final record = Float64List(PipeFlow.pipeFloats)
      ..[PipeFlow.flow] = flow
      ..[PipeFlow.drive] = p0 - p1
      ..[PipeFlow.headFrom] = from.depthAbove(at)
      ..[PipeFlow.headTo] = to.depthAbove(toAt)
      ..[PipeFlow.areaFrom] = from.surface.area
      ..[PipeFlow.areaTo] = to.surface.area
      ..[PipeFlow.radius] = radius
      ..[PipeFlow.length] = length
      ..[PipeFlow.density] = medium.density
      ..[PipeFlow.viscosity] = medium.viscosity
      ..[PipeFlow.minorLoss] = minorLoss;
    solver.flowPipes(PipeFlow(pipes: record, dt: dt));
    flow = record[PipeFlow.flow];
    // The liquid at each opening goes through: the layer it opens into.
    final moved = flow * dt;
    if (moved > 0.0) {
      from.drawAt(at, moved).forEach(to.add);
    } else if (moved < 0.0) {
      to.drawAt(toAt, -moved).forEach(from.add);
    }
  }
}

/// [flow] driven in Dart: what [DartFluid.flowPipes] does.
void flowPipesInDart(PipeFlow flow) {
  final dt = flow.dt;
  for (var i = 0; i < flow.count; i++) {
    final r = Float64List.sublistView(
      flow.pipes,
      i * PipeFlow.pipeFloats,
      (i + 1) * PipeFlow.pipeFloats,
    );
    final rho = r[PipeFlow.density];
    final radius = r[PipeFlow.radius];
    final length = r[PipeFlow.length];
    final head0 = r[PipeFlow.headFrom];
    final head1 = r[PipeFlow.headTo];
    var q = r[PipeFlow.flow];
    final a = math.pi * radius * radius;
    // Air cannot be pushed through: a side whose surface is below its end
    // gives nothing.
    if (head0 <= 0.0 && q > 0.0) q = 0.0;
    if (head1 <= 0.0 && q < 0.0) q = 0.0;
    final inertance =
        rho *
        (length / a +
            math.max(head0, 0.0) / math.max(r[PipeFlow.areaFrom], a) +
            math.max(head1, 0.0) / math.max(r[PipeFlow.areaTo], a));
    final viscous =
        8.0 *
        r[PipeFlow.viscosity] *
        length /
        (math.pi * (radius * radius * radius * radius));
    final quadratic = r[PipeFlow.minorLoss] * rho * q.abs() / (2.0 * a * a);
    // Friction taken implicitly, so a thick liquid in a thin pipe is stable
    // at any step.
    var drive = r[PipeFlow.drive];
    if (head0 <= 0.0 && drive > 0.0) drive = 0.0;
    if (head1 <= 0.0 && drive < 0.0) drive = 0.0;
    r[PipeFlow.flow] =
        (q + dt * drive / inertance) /
        (1.0 + dt * (viscous + quadratic) / inertance);
  }
}
