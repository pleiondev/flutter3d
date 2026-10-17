import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'fluid_solver.dart';
import 'liquid_body.dart';

/// A round pipe joining two vessels below their surfaces: communicating
/// vessels.
///
/// **The liquid in it has mass**, so it is not pushed through at once but
/// accelerated: the pressure difference between its ends drives the column
/// — the pipe's own length over its section, and the liquid standing in each
/// vessel above it over the vessel's — and friction holds it back: along
/// the pipe as Darcy's f·(L/D)·ρv²/2, f the [frictionFactor] at the flow's
/// [reynolds] number — Hagen–Poiseuille's 8μL/πr⁴ while it is laminar,
/// Haaland's for the bore's [roughness] once it is turbulent — and as the
/// square of the flow for the losses where it enters and leaves
/// (K·ρQ|Q|/2a²). Two
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

  /// The pipe's length, in metres.
  final double length;

  /// The loss where it enters and leaves, in velocity heads: about 0.5 in
  /// and 1 out for sharp ends. A unitless coefficient.
  final double minorLoss;

  /// The height of the bumps on the bore, metres: 1.5 µm by default, drawn
  /// glass and plastic tubing. What turbulent friction feels; a laminar
  /// flow does not.
  final double roughness;

  /// Cubic metres a second from [from] to [to]; negative the other way.
  double flow = 0.0;

  /// The flow's Reynolds number, ρ·v·D/μ, no unit: under 2300 laminar, over
  /// 4000 turbulent.
  double get reynolds {
    final medium = from.medium;
    final v = flow.abs() / (math.pi * radius * radius);
    return medium.density * v * 2.0 * radius / medium.viscosity;
  }

  /// Darcy's friction factor at Reynolds number [re] in a bore of
  /// [relativeRoughness] ε/D, no unit.
  ///
  /// Laminar, Hagen and Poiseuille's 64/Re, exact. Turbulent, Haaland's
  /// explicit form of Colebrook's, 1/√f = −1.8·log₁₀((ε/D/3.7)^1.11 +
  /// 6.9/Re) (J. Fluids Eng. 105, 1983), within a couple of percent of it.
  /// Between 2300 and 4000 the flow is neither, and goes from one to the
  /// other with Re: no law holds there, and a straight line between the two
  /// does not pretend to one.
  static double frictionFactor(double re, {double relativeRoughness = 0.0}) {
    if (re <= 0.0) return double.infinity;
    double turbulent() {
      final x = Portable.pow(relativeRoughness / 3.7, 1.11) + 6.9 / re;
      final inverse = -1.8 * Portable.log(x) / math.ln10;
      return 1.0 / (inverse * inverse);
    }

    final laminar = 64.0 / re;
    if (re <= 2300.0) return laminar;
    if (re >= 4000.0) return turbulent();
    final t = (re - 2300.0) / 1700.0;
    return (1.0 - t) * laminar + t * turbulent();
  }

  /// Darcy's loss over Poiseuille's at the flow there is: f·Re/64, one for a
  /// laminar flow and at no flow. Darcy's Δp/Q = f·L·ρ·|Q|/(2·D·a²) is
  /// Poiseuille's 8μL/πr⁴ times this, so the column's solver, which holds
  /// it back by Poiseuille's friction, holds it back by Darcy's when handed
  /// the viscosity times this.
  double get _darcyOverPoiseuille {
    final re = reynolds;
    if (re <= 2300.0) return 1.0;
    return frictionFactor(re, relativeRoughness: roughness / (2.0 * radius)) *
        re /
        64.0;
  }

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
      ..[PipeFlow.viscosity] = medium.viscosity * _darcyOverPoiseuille
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
