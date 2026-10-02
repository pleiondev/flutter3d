import 'dart:math' as math;

import '../portable_math.dart';
import 'fluid_medium.dart';

/// How liquid leaves a vessel, from Bernoulli's equation.
///
/// Along a streamline of an incompressible liquid p + ½ρv² + ρgz is the
/// same everywhere, so liquid that falls a head h from a still surface to
/// open air at the same pressure arrives at √(2gh) — Torricelli's speed —
/// whatever the vessel. Real openings pass less than their area times that:
/// the stream narrows past the edge (the vena contracta) and loses a little
/// to friction, which the measured discharge coefficient C_d carries.

/// The discharge coefficient of a sharp-edged opening or crest: the stream
/// contracts to about 0.62 of the opening past a sharp edge.
const double sharpEdgeDischarge = 0.62;

/// What a submerged opening of [area] passes under a [head] of liquid, in
/// gravity [g]: Torricelli's speed, and that over the contracted section.
({double flow, double speed}) orificeFlow({
  required double area,
  required double head,
  required double g,
  double discharge = sharpEdgeDischarge,
}) {
  if (head <= 0.0 || area <= 0.0) return (flow: 0.0, speed: 0.0);
  final speed = math.sqrt(2.0 * g * head);
  return (flow: discharge * area * speed, speed: speed);
}

/// How much passes a weir round a circular mouth of [radius] tipped [tilt]
/// from upright, with the still surface [head] over its lowest point, in
/// gravity [g]; and the section of the sheet at the crest.
///
/// **Bernoulli over a sharp crest**: each strip of the edge passes
/// C_d·(2/3)·√(2g)·depth^(3/2) per metre, the integral of Torricelli's speed
/// over the depth above it. The mouth is a circle tipped with the glass, so
/// at an angle φ round it from the lowest point the liquid is
/// head − R(1 − cos φ)·sin(tilt) deep over the edge, where that is above
/// nought. At the crest the flow is critical, about two thirds of the head
/// deep, which is the section the sheet leaves with. Nothing passes at a
/// head of nought or less: the liquid has drawn back from the edge.
({double flow, double area}) circularWeir({
  required double head,
  required double radius,
  required double tilt,
  required double g,
  double discharge = sharpEdgeDischarge,
  int steps = 360,
}) {
  if (head <= 0.0) return (flow: 0.0, area: 0.0);
  final dip = radius * math.max(Portable.sin(tilt).abs(), 1e-3);
  var q = 0.0;
  var area = 0.0;
  final dPhi = 2.0 * math.pi / steps;
  for (var i = 0; i < steps; i++) {
    final phi = -math.pi + (i + 0.5) * dPhi;
    final depth = head - dip * (1.0 - Portable.cos(phi));
    if (depth <= 0.0) continue;
    final edge = radius * dPhi;
    q += Portable.pow(depth, 1.5) * edge;
    area += depth * edge;
  }
  return (
    flow: discharge * (2.0 / 3.0) * math.sqrt(2.0 * g) * q,
    area: (2.0 / 3.0) * area,
  );
}

/// The other way round: the head over a circular mouth's lip that passes
/// [flow], the speed the sheet leaves at — the flow over its crest section —
/// and the sheet's width, the chord of the wetted edge.
({double head, double speed, double width}) overCircularLip({
  required double flow,
  required double radius,
  required double tilt,
  required double g,
}) {
  final dip = radius * math.max(Portable.sin(tilt).abs(), 1e-3);
  var lo = 0.0;
  var hi = 2.0 * dip + radius;
  for (var i = 0; i < 52; i++) {
    final mid = 0.5 * (lo + hi);
    final passed = circularWeir(head: mid, radius: radius, tilt: tilt, g: g);
    if (passed.flow < flow) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final head = 0.5 * (lo + hi);
  final crest = circularWeir(head: head, radius: radius, tilt: tilt, g: g);
  final reach = (1.0 - head / dip).clamp(-1.0, 1.0);
  return (
    head: head,
    speed: crest.area > 0.0 ? flow / crest.area : math.sqrt(g * head),
    width: 2.0 * radius * Portable.sin(Portable.acos(reach)),
  );
}

/// Flow through a straight round pipe of [length] and [radius] driven by a
/// head difference [head], for [medium] in gravity [g].
///
/// Two limits, and the lesser flow governs. A long thin pipe is held back by
/// viscosity: Hagen–Poiseuille, Q = πr⁴Δp / 8μL, with Δp = ρg·head. A short
/// wide one is held back by the liquid's own inertia, and passes what
/// Bernoulli lets through its section, C_d·A·√(2g·head). The sign follows
/// the head: negative flows the other way.
double pipeFlow({
  required double length,
  required double radius,
  required double head,
  required FluidMedium medium,
  required double g,
}) {
  if (head == 0.0) return 0.0;
  final drop = medium.density * g * head.abs();
  final viscous =
      math.pi *
      Portable.pow(radius, 4) *
      drop /
      (8.0 * medium.viscosity * math.max(length, 1e-6));
  final inertial = orificeFlow(
    area: math.pi * radius * radius,
    head: head.abs(),
    g: g,
  ).flow;
  return math.min(viscous, inertial) * head.sign;
}
