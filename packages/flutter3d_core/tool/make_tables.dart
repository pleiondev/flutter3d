/// Writes the engine's data tables — `G1`.
///
///     dart run tool/make_tables.dart
///
/// A table is bytes a shader samples that nobody should compute at startup:
/// blue noise today, the LTC fit and the sheen albedo later. Each is written
/// once, here, into a Dart file under `lib/src/engine/render/tables/`, so the
/// software rasteriser and the GPUs sample the same bytes and a test can pin
/// them by hash. Running this again writes the same files: every choice below
/// is seeded.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const String _out = 'lib/src/engine/render/tables';

void main() {
  final noise = blueNoiseSlices(size: 64, slices: 32);
  _write(
    'blue_noise.dart',
    name: 'blueNoise',
    doc: '''
/// 32 slices of 64×64 blue noise, one byte a texel, laid out as an 8×4 atlas
/// of slices (512×256, slice `i` at column `i % 8`, row `i ~/ 8`).
///
/// Each slice is its own void-and-cluster ranking (Ulichney 1993) on a torus,
/// with a Gaussian of σ = 1.5 texels, so it tiles. Every value 0–255 occurs
/// exactly sixteen times in a slice. Slices are seeded independently: a
/// temporal effect steps through them by `Renderer.frameIndex % 32`.''',
    width: 512,
    height: 256,
    format: 'r8UNormInt',
    bytes: _atlas(noise, size: 64, columns: 8, rows: 4),
  );

  _write(
    'aces2_display.dart',
    name: 'aces2Display',
    doc: '''
/// A display transform for `TonemapCurve.aces2` — `L2`: 33³ entries as a
/// strip of 33 slices (1089×33, blue picks the slice, red runs across it,
/// green down), rgba16f, indexed through a log2 shaper of −10…+10 stops about
/// 0.18 (`DisplayTransform`'s shaper), which reaches past 128, where the
/// SDR tonescale meets the display's peak.
///
/// **The ACES 2.0 tonescale, not the whole ACES 2.0 output transform.** Each
/// entry is the SDR (100 nit, Rec.709) tonescale Daniele Siragusano wrote for
/// ACES 2.0, applied to the largest channel and the colour scaled with it so
/// its hue holds, with a path to white that desaturates what the curve
/// compresses. The reference transform does its chroma and gamut work in a
/// colour appearance model; this table does not. A table baked from the
/// reference implementation drops into `LookSettings.displayTransform` in
/// the same shape.''',
    width: _kDisplaySize * _kDisplaySize,
    height: _kDisplaySize,
    format: 'r16g16b16a16Float',
    bytes: aces2DisplayTable(),
  );

  _write(
    'ltc.dart',
    name: 'ltc',
    doc: '''
/// The linearly transformed cosines of GGX — `L7`: two 64×64 tables stacked
/// in one 64×128 rgba16f texture, indexed by `(roughness, sqrt(1 − n·v))`
/// scaled into texel centres. Rows 0–63 hold the inverse matrix, normalised
/// by its middle element, as (m00, m02, m20, m22); rows 64–127 hold the
/// fitted norm and Fresnel term in x and y, the directional albedo of the
/// Charlie sheen lobe in z — `M2`, indexed by the sheen's own roughness —
/// and the form factor of a sphere by the clipped cosine in w.
///
/// The z lane is this engine's own: the Charlie distribution and Neubelt's
/// visibility, as `lib/pbr.glsl` evaluates them, integrated over the
/// hemisphere by `tool/make_tables.dart`. The rest is the published fit of Heitz, Dupuy, Hill and Neubelt, "Real-Time
/// Polygonal-Light Shading with Linearly Transformed Cosines", ACM TOG 35(4),
/// 2016, copied half for half from `tool/third_party/ltc/`:
///
/// Copyright (c) 2017, Eric Heitz, Jonathan Dupuy, Stephen Hill and David
/// Neubelt. All rights reserved. Redistributed under the conditions in
/// `tool/third_party/ltc/LICENSE`.''',
    width: 64,
    height: 128,
    format: 'r16g16b16a16Float',
    bytes: ltcTable(),
  );
}

/// The two published LTC tables, headers dropped, one under the other.
Uint8List ltcTable() {
  Uint8List body(String name) {
    final dds = File('tool/third_party/ltc/$name').readAsBytesSync();
    // A plain DDS: four bytes of magic, a 124-byte header, then 64×64
    // rgba16f with no DX10 extension.
    const header = 128;
    const size = 64 * 64 * 8;
    if (dds.length != header + size) {
      throw StateError('$name is not the 64×64 rgba16f table it should be');
    }
    return Uint8List.sublistView(dds, header);
  }

  final table = Uint8List.fromList(<int>[
    ...body('ltc_1.dds'),
    ...body('ltc_2.dds'),
  ]);
  // `M2`: the sheen's albedo in the second table's empty z lane, on the same
  // axes — roughness across, sqrt(1 − n·v) down.
  final view = ByteData.sublistView(table);
  for (var row = 0; row < 64; row++) {
    final y = row / 63.0;
    final nDotV = 1.0 - y * y;
    for (var column = 0; column < 64; column++) {
      final at = ((64 + row) * 64 + column) * 8 + 4;
      view.setUint16(
        at,
        toHalf(sheenAlbedo(nDotV, column / 63.0)),
        Endian.little,
      );
    }
  }
  return table;
}

/// The least sheen roughness `lib/pbr.glsl` shades with: below it the
/// Charlie lobe's exponent outgrows a half float.
const double kSheenRoughnessFloor = 0.07;

/// How much light the Charlie sheen lobe of [roughness] reflects towards a
/// view at [nDotV], over a white hemisphere — the albedo `M2` scales the
/// layer beneath by. The lobe is `D_Charlie · V_Neubelt · n·l`, with the
/// floors `lib/pbr.glsl` applies, integrated by the midpoint rule in
/// `cos θ` and `φ` (the view lies in the xz plane, so φ is folded in half).
double sheenAlbedo(double nDotV, double roughness) {
  final r = math.max(roughness, kSheenRoughnessFloor);
  final invAlpha = 1.0 / (r * r);
  final mu = math.max(nDotV, 1e-4);
  final vx = math.sqrt(math.max(1.0 - mu * mu, 0.0));
  const steps = 96;
  const turns = 64;
  var sum = 0.0;
  for (var i = 0; i < steps; i++) {
    final cosL = (i + 0.5) / steps;
    final sinL = math.sqrt(1.0 - cosL * cosL);
    for (var j = 0; j < turns; j++) {
      final phi = (j + 0.5) / turns * math.pi;
      final lx = sinL * math.cos(phi);
      final ly = sinL * math.sin(phi);
      final hx = lx + vx;
      final hy = ly;
      final hz = cosL + mu;
      final nDotH = hz / math.sqrt(hx * hx + hy * hy + hz * hz);
      final sin2h = math.max(1.0 - nDotH * nDotH, 0.0078125);
      final d =
          (2.0 + invAlpha) * math.pow(sin2h, invAlpha * 0.5) / (2.0 * math.pi);
      final visibility = 1.0 / (4.0 * (cosL + mu - cosL * mu));
      sum += d * visibility * cosL;
    }
  }
  // dω = d(cos θ) dφ over φ in [0, 2π), folded: twice the half. Held to
  // one: Neubelt's visibility is a fit, not a conserving term, and at the
  // grazing edge of a smooth sheen it integrates to a hair over, which would
  // scale the layer beneath below nothing.
  return math.min(sum * (1.0 / steps) * (math.pi / turns) * 2.0, 1.0);
}

/// Entries per axis of a display transform table.
const int _kDisplaySize = 33;

/// The shaper: an entry `i` of `n` holds the colour
/// `0.18 · 2^(low + stops · i / (n − 1))`.
///
/// Twenty stops, so the last entry is 0.18 · 2^10 ≈ 184: the tonescale only
/// reaches the display's peak at 128 (`r_hit_min`), 9.47 stops over grey.
/// Sixteen stopped at 11.5, where the curve is at 0.92 of peak, and every
/// highlight above it clamped to that one grey short of white.
const double _kShaperLow = -10.0;
const double _kShaperStops = 20.0;

/// The ACES 2.0 tonescale for a peak of [peak] nits, as nits — the forward
/// half of `Lib.Academy.Tonescale` with its published constants.
double aces2Tonescale(double x, {double peak = 100.0}) {
  const nR = 100.0;
  const g = 1.15;
  const c = 0.18;
  const cD = 10.013;
  const wG = 0.14;
  const t1 = 0.04;
  const rHitMin = 128.0;
  const rHitMax = 896.0;

  final rHit =
      rHitMin + (rHitMax - rHitMin) * (math.log(peak / nR) / math.log(100.0));
  final m0 = peak / nR;
  final m1 = 0.5 * (m0 + math.sqrt(m0 * (m0 + 4.0 * t1)));
  final u = math.pow((rHit / m1) / ((rHit / m1) + 1.0), g);
  final m = m1 / u;
  final wI = math.log(peak / 100.0) / math.ln2;
  final cT = cD / nR * (1.0 + wI * wG);
  final gIp = 0.5 * (cT + math.sqrt(cT * (cT + 4.0 * t1)));
  final gIpRatio = math.pow(gIp / m, 1.0 / g);
  final gIpp2 = -(m1 * gIpRatio) / (gIpRatio - 1.0);
  final w2 = c / gIpp2;
  final s2 = w2 * m1;
  final u2 = math.pow((rHit / m1) / ((rHit / m1) + w2), g);
  final m2 = m1 / u2;

  final f = m2 * math.pow(math.max(0.0, x) / (x + s2), g);
  final h = math.max(0.0, f * f / (f + t1));
  return h * nR;
}

/// One entry of the ACES 2.0 SDR table: [rgb] scene-linear in, display-linear
/// Rec.709 in [0, 1] out.
List<double> aces2Display(List<double> rgb) {
  final peak = math.max(rgb[0], math.max(rgb[1], rgb[2]));
  if (peak <= 0.0) return const <double>[0.0, 0.0, 0.0];
  final mapped = aces2Tonescale(peak) / 100.0;
  final scale = mapped / peak;
  // The path to white: as the curve flattens towards the display's peak, the
  // colour is pulled towards its own mapped peak, so a light brighter than
  // the display can show turns white rather than clipping to a flat hue.
  final white = math.pow(mapped, 3.0).toDouble();
  return <double>[
    for (final channel in rgb)
      (channel * scale * (1.0 - white) + mapped * white).clamp(0.0, 1.0),
  ];
}

/// The whole table, as rgba16f bytes.
Uint8List aces2DisplayTable() {
  const n = _kDisplaySize;
  final out = ByteData(n * n * n * 8);
  double shaped(int i) =>
      0.18 * math.pow(2.0, _kShaperLow + _kShaperStops * i / (n - 1));
  for (var b = 0; b < n; b++) {
    for (var g = 0; g < n; g++) {
      for (var r = 0; r < n; r++) {
        final value = aces2Display(<double>[shaped(r), shaped(g), shaped(b)]);
        final at = (g * n * n + b * n + r) * 8;
        for (var ch = 0; ch < 3; ch++) {
          out.setUint16(at + ch * 2, toHalf(value[ch]), Endian.little);
        }
        out.setUint16(at + 6, toHalf(1.0), Endian.little);
      }
    }
  }
  return out.buffer.asUint8List();
}

/// [value] as an IEEE half, rounded to nearest. Finite and non-negative here.
///
/// The rounded mantissa is added to the exponent, not OR-ed into it: when
/// rounding carries out of the ten mantissa bits, the carry has to bump the
/// exponent. OR-ed, it vanished whenever the exponent was odd, and 0.4999
/// came out as 0.25. A carry out of the largest exponent reaches infinity.
int toHalf(double value) {
  final bits = ByteData(4)..setFloat32(0, value, Endian.little);
  final f = bits.getUint32(0, Endian.little);
  final sign = (f >> 16) & 0x8000;
  final exponent = ((f >> 23) & 0xff) - 127 + 15;
  final mantissa = f & 0x7fffff;
  if (exponent <= 0) {
    if (exponent < -10) return sign;
    final m = (mantissa | 0x800000) >> (1 - exponent);
    return sign | ((m + 0x1000) >> 13);
  }
  if (exponent >= 31) return sign | 0x7c00;
  return sign |
      math.min((exponent << 10) + ((mantissa + 0x1000) >> 13), 0x7c00);
}

/// [slices] rankings of a [size]×[size] torus, each as bytes 0–255.
List<Uint8List> blueNoiseSlices({required int size, required int slices}) => [
  for (var s = 0; s < slices; s++) _voidAndCluster(size, seed: 0x5eed + s),
];

Uint8List _atlas(
  List<Uint8List> slices, {
  required int size,
  required int columns,
  required int rows,
}) {
  final width = size * columns;
  final out = Uint8List(width * size * rows);
  for (var s = 0; s < slices.length; s++) {
    final x0 = (s % columns) * size;
    final y0 = (s ~/ columns) * size;
    for (var y = 0; y < size; y++) {
      out.setRange(
        (y0 + y) * width + x0,
        (y0 + y) * width + x0 + size,
        slices[s],
        y * size,
      );
    }
  }
  return out;
}

/// One void-and-cluster ranking, mapped to bytes.
Uint8List _voidAndCluster(int size, {required int seed}) {
  final n = size * size;
  final kernel = _gaussian(size, sigma: 1.5);
  final random = math.Random(seed);

  // The energy a set of points puts on every texel, kept incrementally: a
  // point switched on adds the kernel centred on it, one switched off takes
  // it away.
  final energy = Float64List(n);
  final on = List<bool>.filled(n, false);
  void toggle(int p, {required bool set}) {
    on[p] = set;
    final sign = set ? 1.0 : -1.0;
    final px = p % size;
    final py = p ~/ size;
    for (var y = 0; y < size; y++) {
      final ky = ((y - py) % size) * size;
      for (var x = 0; x < size; x++) {
        energy[y * size + x] += sign * kernel[ky + (x - px) % size];
      }
    }
  }

  int extreme({required bool ofOn, required bool highest}) {
    var best = -1;
    for (var p = 0; p < n; p++) {
      if (on[p] != ofOn) continue;
      if (best < 0 ||
          (highest ? energy[p] > energy[best] : energy[p] < energy[best])) {
        best = p;
      }
    }
    return best;
  }

  // A tenth of the texels, at random, relaxed until moving the most crowded
  // point into the emptiest gap puts it back where it was.
  final initial = n ~/ 10;
  for (var placed = 0; placed < initial;) {
    final p = random.nextInt(n);
    if (on[p]) continue;
    toggle(p, set: true);
    placed++;
  }
  while (true) {
    final cluster = extreme(ofOn: true, highest: true);
    toggle(cluster, set: false);
    final gap = extreme(ofOn: false, highest: false);
    toggle(gap, set: true);
    if (gap == cluster) break;
  }

  final rank = Int32List(n);
  final prototype = List<bool>.of(on);
  final prototypeEnergy = Float64List.fromList(energy);

  // Down from the prototype: the most crowded point goes first and ranks
  // highest among what is left.
  for (var left = initial; left > 0; left--) {
    final cluster = extreme(ofOn: true, highest: true);
    toggle(cluster, set: false);
    rank[cluster] = left - 1;
  }

  // Up from the prototype: the emptiest gap is filled next.
  on.setAll(0, prototype);
  energy.setAll(0, prototypeEnergy);
  for (var filled = initial; filled < n; filled++) {
    final gap = extreme(ofOn: false, highest: false);
    toggle(gap, set: true);
    rank[gap] = filled;
  }

  return Uint8List.fromList([for (final r in rank) r * 256 ~/ n]);
}

/// A toroidal Gaussian, indexed by `dy * size + dx` with both wrapped.
Float64List _gaussian(int size, {required double sigma}) {
  final kernel = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    final dy = math.min(y, size - y);
    for (var x = 0; x < size; x++) {
      final dx = math.min(x, size - x);
      kernel[y * size + x] = math.exp(
        -(dx * dx + dy * dy) / (2 * sigma * sigma),
      );
    }
  }
  return kernel;
}

void _write(
  String file, {
  required String name,
  required String doc,
  required int width,
  required int height,
  required String format,
  required Uint8List bytes,
}) {
  final encoded = base64.encode(bytes);
  final lines = [
    for (var i = 0; i < encoded.length; i += 76)
      // Indented the way `dart format` leaves it, so formatting the package
      // does not make the generated file stale.
      "      '${encoded.substring(i, math.min(i + 76, encoded.length))}'",
  ];
  File('$_out/$file')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
// GENERATED by tool/make_tables.dart. Do not edit by hand.
//
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../engine_table.dart';

$doc
const EngineTable $name = EngineTable(
  name: '$name',
  width: $width,
  height: $height,
  format: TextureFormat.$format,
  base64:
${lines.join('\n')},
);
''');
  stdout.writeln('wrote $_out/$file (${bytes.length} bytes)');
}
