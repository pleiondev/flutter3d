import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';

/// Where sunlight goes after it meets a vessel: geometric optics, worked out
/// for the shapes on this bench.
///
/// **Every vessel here is a surface of revolution**, so cut across at any
/// height it is a set of circles round one centre: the outside of the glass,
/// its inside half a millimetre in (`glassThickness`), and the liquid's edge. A sunbeam crossing
/// that cut is a straight line bent at each circle by Snell's law, partly
/// reflected away by Fresnel's, totally reflected where it meets a thinner
/// medium too steeply, and dimmed inside the liquid by Beer and Lambert over
/// the length it actually travels there. Followed to the bench, the beams
/// pile up where the liquid focuses them and thin out at the sides: the bright
/// line and the dark edges of a real test tube's shadow, and its colour, which
/// is deeper where the light went through more of the solution.
///
/// The sun is not square to the tube: it comes down at an elevation, and a
/// ray meeting a cylinder at an angle to its axis bends in the cut as if each
/// medium had Bravais's index, √(n² − cos² γ) / sin γ for a ray at γ to the
/// axis, while the length it travels is the cut's length over sin γ. That is
/// exact for a straight wall and close for the curved bottom and the flask's
/// cone, where the wall leans.

/// One medium inside a circle of [radius], as far out as the next one: its
/// Bravais [index] in the cut, which bends the ray's direction there, and its
/// [real] index, which Fresnel's reflection is worked out from.
typedef _Layer = ({
  double radius,
  double index,
  double real,
  Vector3 absorption,
});

/// What fell on the bench across one cut: [bins] values of red, green and
/// blue, in units of the light that would have fallen with nothing there, over
/// lateral positions from −[halfWidth] to +[halfWidth] metres.
final class OpticsCut {
  OpticsCut(this.bins, this.halfWidth)
    : red = Float64List(bins),
      green = Float64List(bins),
      blue = Float64List(bins);

  final int bins;
  final double halfWidth;
  final Float64List red;
  final Float64List green;
  final Float64List blue;
}

/// The cosine of a ray's angle to the horizontal inside a medium of index
/// [n], for sunlight at an elevation whose sine is [sinE].
double _tilt(double sinE, double n) {
  final s = sinE / n;
  return math.sqrt(math.max(1.0 - s * s, 0.0));
}

/// The radius of [profile] at height [height], walking up from its base; null
/// where the profile does not reach that height.
double? radiusAt(List<Vector2> profile, double height) {
  for (var i = 0; i + 1 < profile.length; i++) {
    final a = profile[i];
    final b = profile[i + 1];
    if ((b.y - a.y).abs() < 1e-9) continue;
    final lo = math.min(a.y, b.y);
    final hi = math.max(a.y, b.y);
    if (height < lo || height > hi) continue;
    final t = (height - a.y) / (b.y - a.y);
    return a.x + (b.x - a.x) * t;
  }
  return null;
}

/// Beer–Lambert absorption per metre that leaves [color] after [distance].
/// [color] is linear light, the share of each channel that gets through, not
/// an sRGB-encoded colour.
Vector3 absorptionFor(Vector3 color, double distance) {
  if (!distance.isFinite || distance <= 0.0) return Vector3.zero();
  double mu(double c) => -math.log(c.clamp(1e-4, 1.0)) / distance;
  return Vector3(mu(color.x), mu(color.y), mu(color.z));
}

/// Follows [rays] parallel sunbeams across one cut of a vessel.
///
/// [outer] is the glass's outside radius at this height, or null where there
/// is no glass; [wall] its thickness; [liquid] the liquid's radius, or null
/// above the level. [elevation] is the sun's angle above the bench, and
/// [reach] how far, along the light's way across the bench, the bench point
/// this cut throws its shadow on lies from the vessel's axis.
OpticsCut traceCut({
  required double? outer,
  required double wall,
  required double? liquid,
  required double glassIndex,
  required double liquidIndex,
  required Vector3 liquidAbsorption,
  required double elevation,
  required double reach,
  required double halfWidth,
  int bins = 128,
  int rays = 1600,
}) {
  final cut = OpticsCut(bins, halfWidth);
  final binWidth = 2.0 * halfWidth / bins;
  final spacing = 2.0 * halfWidth / rays;
  final weight = spacing / binWidth;

  void land(double y, double r, double g, double b) {
    final index = ((y + halfWidth) / binWidth).floor();
    if (index < 0 || index >= bins) return;
    cut.red[index] += r * weight;
    cut.green[index] += g * weight;
    cut.blue[index] += b * weight;
  }

  // The media from the inside out. Air between the liquid and the glass when
  // the liquid stops short of it, as it does by two millimetres here.
  final cosE = math.cos(elevation);
  final sinE = math.sin(elevation);
  double bravais(double n) =>
      math.sqrt(math.max(n * n - sinE * sinE, 0.0)) / cosE;
  final layers = <_Layer>[];
  final inner = outer == null ? null : math.max(outer - wall, 0.0);
  if (liquid != null && liquid > 0.0) {
    layers.add((
      radius: inner == null ? liquid : math.min(liquid, inner),
      index: bravais(liquidIndex),
      real: liquidIndex,
      absorption: liquidAbsorption,
    ));
  }
  if (outer != null && inner != null) {
    if (inner > 0.0) {
      layers.add((
        radius: inner,
        index: 1.0,
        real: 1.0,
        absorption: Vector3.zero(),
      ));
    }
    layers.add((
      radius: outer,
      index: bravais(glassIndex),
      real: glassIndex,
      absorption: Vector3.zero(),
    ));
  }
  final edge = layers.isEmpty ? 0.0 : layers.last.radius;

  _Layer? mediumAt(double r) {
    for (final layer in layers) {
      if (r < layer.radius) return layer;
    }
    return null;
  }

  for (var k = 0; k < rays; k++) {
    final b = -halfWidth + (k + 0.5) * spacing;
    if (b.abs() >= edge) {
      land(b, 1.0, 1.0, 1.0);
      continue;
    }
    // In from upstream, along +x, b across.
    var px = -edge - 1.0;
    var py = b;
    var dx = 1.0;
    var dy = 0.0;
    var r = 1.0, g = 1.0, bl = 1.0;
    var escaped = false;
    for (var event = 0; event < 24; event++) {
      // The nearest circle ahead.
      var tBest = double.infinity;
      var hit = -1;
      for (var i = 0; i < layers.length; i++) {
        final radius = layers[i].radius;
        final along = px * dx + py * dy;
        final c = px * px + py * py - radius * radius;
        final disc = along * along - c;
        if (disc < 0.0) continue;
        final root = math.sqrt(disc);
        for (final t in <double>[-along - root, -along + root]) {
          if (t > 1e-9 && t < tBest) {
            tBest = t;
            hit = i;
          }
        }
      }
      if (hit < 0) {
        escaped = true;
        break;
      }
      // What the stretch to it crossed, dimmed by its absorption.
      final midX = px + dx * tBest * 0.5;
      final midY = py + dy * tBest * 0.5;
      final here = mediumAt(math.sqrt(midX * midX + midY * midY));
      if (here != null) {
        // The ray's tilt inside the medium is its own: n · sin of the
        // elevation is what Snell keeps across a vertical wall.
        final path = tBest / _tilt(sinE, here.real);
        r *= math.exp(-here.absorption.x * path);
        g *= math.exp(-here.absorption.y * path);
        bl *= math.exp(-here.absorption.z * path);
      }
      px += dx * tBest;
      py += dy * tBest;
      // Which side is which: the normal faces the medium the ray is in.
      final len = math.sqrt(px * px + py * py);
      var nx = px / len;
      var ny = py / len;
      var cosI = -(dx * nx + dy * ny);
      final outward = cosI < 0.0;
      if (outward) {
        nx = -nx;
        ny = -ny;
        cosI = -cosI;
      }
      final n1 = here?.index ?? 1.0;
      final beyondRadius = outward ? len * 1.000001 : len * 0.999999;
      final beyond = mediumAt(beyondRadius);
      final n2 = beyond?.index ?? 1.0;
      final eta = n1 / n2;
      final k2 = 1.0 - eta * eta * (1.0 - cosI * cosI);
      if (k2 < 0.0) {
        // Total internal reflection: all of it turns back inside.
        dx += 2.0 * cosI * nx;
        dy += 2.0 * cosI * ny;
        continue;
      }
      final cosT = math.sqrt(k2);
      // Fresnel for unpolarised light, at the angle the ray really meets the
      // surface in space and with the media's real indices: the Bravais ones
      // say where the ray goes in the cut, not how much glass reflects. The
      // wall is vertical and the ray comes down at the sun's elevation, so
      // the true cosine is the cut's times cos E. What is reflected leaves
      // the shadow.
      final m1 = here?.real ?? 1.0;
      final m2 = beyond?.real ?? 1.0;
      final cosTrue = cosI * _tilt(sinE, m1);
      final sinT2 = (m1 / m2) * (m1 / m2) * (1.0 - cosTrue * cosTrue);
      var transmitted = 0.0;
      if (sinT2 < 1.0) {
        final cosTrueT = math.sqrt(1.0 - sinT2);
        final rs =
            (m1 * cosTrue - m2 * cosTrueT) / (m1 * cosTrue + m2 * cosTrueT);
        final rp =
            (m2 * cosTrue - m1 * cosTrueT) / (m2 * cosTrue + m1 * cosTrueT);
        transmitted = 1.0 - 0.5 * (rs * rs + rp * rp);
      }
      r *= transmitted;
      g *= transmitted;
      bl *= transmitted;
      final tx = eta * dx + (eta * cosI - cosT) * nx;
      final ty = eta * dy + (eta * cosI - cosT) * ny;
      final tl = math.sqrt(tx * tx + ty * ty);
      dx = tx / tl;
      dy = ty / tl;
    }
    if (!escaped || dx <= 1e-6) continue;
    // Out across the bench to where this cut's shadow falls.
    land(py + dy / dx * (reach - px), r, g, bl);
  }

  // A little smoothing: sixteen hundred rays into a hundred and twenty-eight
  // bins leaves the noise of the binning itself.
  for (final channel in <Float64List>[cut.red, cut.green, cut.blue]) {
    for (var pass = 0; pass < 2; pass++) {
      final copy = Float64List.fromList(channel);
      for (var i = 0; i < bins; i++) {
        final a = copy[math.max(i - 1, 0)];
        final c = copy[math.min(i + 1, bins - 1)];
        channel[i] = 0.25 * a + 0.5 * copy[i] + 0.25 * c;
      }
    }
  }
  return cut;
}

/// The picture a vessel's shadow card carries: [cuts] rows from the base to
/// [height], each a [traceCut] at that height, light stored over [scale] so
/// that light gathered past one, up to [scale], survives eight bits.
Rgba8Image shadowPicture({
  required List<Vector2> glass,
  required List<Vector2>? liquid,
  required double wall,
  required double height,
  required double glassIndex,
  required double liquidIndex,
  required Vector3 liquidAbsorption,
  required double elevation,
  required double halfWidth,
  required double scale,
  int bins = 128,
  int cuts = 64,
}) {
  final pixels = Uint8List(bins * cuts * 4);
  final cotE = math.cos(elevation) / math.sin(elevation);
  for (var row = 0; row < cuts; row++) {
    final h = height * (row + 0.5) / cuts;
    final cut = traceCut(
      outer: radiusAt(glass, h),
      wall: wall,
      liquid: liquid == null ? null : radiusAt(liquid, h),
      glassIndex: glassIndex,
      liquidIndex: liquidIndex,
      liquidAbsorption: liquidAbsorption,
      elevation: elevation,
      reach: h * cotE,
      halfWidth: halfWidth,
      bins: bins,
    );
    for (var i = 0; i < bins; i++) {
      final at = (row * bins + i) * 4;
      int byte(double value) => (value / scale * 255.0).round().clamp(0, 255);
      pixels[at] = byte(cut.red[i]);
      pixels[at + 1] = byte(cut.green[i]);
      pixels[at + 2] = byte(cut.blue[i]);
      pixels[at + 3] = 255;
    }
  }
  return Rgba8Image(width: bins, height: cuts, pixels: pixels);
}
