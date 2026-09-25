/// A six-way smoke sheet baked on the CPU — `N6`.
///
/// Six-way particles are lit through six pictures of one puff, each rendered
/// with a light from one side, and those pictures usually come out of a fluid
/// tool. This makes them here instead, from a density field: the engine can
/// then ship smoke of its own, and a test can make a sheet without an asset.
///
/// **Single scattering along the six axes, and that is the whole trick.** The
/// six lights are axis-aligned, so the light reaching a voxel from the right is
/// the extinction summed along its row to the right-hand face — a running sum
/// rather than a march per sample. Each frame is a voxel grid, six running
/// sums, and one march from the viewer through each column: a few million
/// multiplications for a sixteen-frame sheet, where marching a shadow ray from
/// every sample towards six lights would be hundreds of millions.
///
/// The layout written is `flutter3d_particles`' own: `positive` holds right,
/// top, back and coverage, `negative` holds left, bottom, front and emission,
/// the responses unpremultiplied, and each cell's rows bottom to top, so the
/// sheet uploads as it is. The viewer looks down −z; "back" is the light from
/// −z, behind the puff.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Density at a point of the cube from −1 to 1 on every axis, at [t] through
/// the animation from nought to one. Nought is empty; one is as thick as the
/// bake's extinction.
typedef SixWayField = double Function(double x, double y, double z, double t);

/// A baked sheet: [columns] by [rows] cells of [cell] pixels, RGBA8.
final class SixWaySheet {
  const SixWaySheet({
    required this.columns,
    required this.rows,
    required this.cell,
    required this.positive,
    required this.negative,
  });

  final int columns;
  final int rows;
  final int cell;

  /// Right, top, back, coverage.
  final Uint8List positive;

  /// Left, bottom, front, emission.
  final Uint8List negative;

  int get width => columns * cell;
  int get height => rows * cell;
}

/// Bakes [frames] frames of [density] into a sheet, cells in reading order.
///
/// [extinction] is how much light a unit of density takes out per unit of
/// length, the cube being two units across: the one control over how dense
/// the smoke reads. [emission] is how much of the emission colour a point
/// gives off, nought to one, or null for none.
SixWaySheet bakeSixWay({
  required SixWayField density,
  SixWayField? emission,
  int frames = 16,
  int columns = 4,
  int cell = 64,
  double extinction = 6.0,
}) {
  if (frames < 1 || columns < 1 || cell < 1) {
    throw ArgumentError('a sheet has at least one frame, column and pixel');
  }
  final rows = (frames + columns - 1) ~/ columns;
  final width = columns * cell;
  final positive = Uint8List(width * rows * cell * 4);
  final negative = Uint8List(width * rows * cell * 4);

  final n = cell;
  final step = 2.0 / n;
  double at(int i) => -1.0 + (i + 0.5) * step;
  int index(int x, int y, int z) => (z * n + y) * n + x;

  // Extinction per voxel, and then the optical depth from each voxel's middle
  // to the face each of the six lights comes in through.
  final sigma = Float64List(n * n * n);
  final glow = Float64List(n * n * n);
  final depth = List<Float64List>.generate(6, (_) => Float64List(n * n * n));

  int byte(double v) => (v.clamp(0.0, 1.0) * 255.0 + 0.5).floor();

  for (var frame = 0; frame < frames; frame++) {
    final t = frames == 1 ? 0.0 : frame / (frames - 1);
    for (var z = 0; z < n; z++) {
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final i = index(x, y, z);
          sigma[i] =
              extinction * math.max(density(at(x), at(y), at(z), t), 0.0);
          glow[i] = emission == null
              ? 0.0
              : emission(at(x), at(y), at(z), t).clamp(0.0, 1.0);
        }
      }
    }

    // Directions in the order right, left, top, bottom, back, front: +x, −x,
    // +y, −y, −z, +z, each the side the light enters from.
    void sweep(
      Float64List into,
      int Function(int a, int b, int c) voxel, {
      required bool fromHigh,
    }) {
      for (var a = 0; a < n; a++) {
        for (var b = 0; b < n; b++) {
          var total = 0.0;
          for (var s = 0; s < n; s++) {
            final c = fromHigh ? n - 1 - s : s;
            final i = voxel(a, b, c);
            // Half of this voxel's own, so a lone voxel is not dimmed by all
            // of itself.
            into[i] = total + sigma[i] * step * 0.5;
            total += sigma[i] * step;
          }
        }
      }
    }

    sweep(depth[0], (y, z, x) => index(x, y, z), fromHigh: true);
    sweep(depth[1], (y, z, x) => index(x, y, z), fromHigh: false);
    sweep(depth[2], (x, z, y) => index(x, y, z), fromHigh: true);
    sweep(depth[3], (x, z, y) => index(x, y, z), fromHigh: false);
    sweep(depth[4], (x, y, z) => index(x, y, z), fromHigh: false);
    sweep(depth[5], (x, y, z) => index(x, y, z), fromHigh: true);

    final left = (frame % columns) * cell;
    final top = (frame ~/ columns) * cell;
    final lit = Float64List(6);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        lit.fillRange(0, 6, 0.0);
        var through = 1.0;
        var emitted = 0.0;
        // From the viewer's side at +z towards the back.
        for (var z = n - 1; z >= 0; z--) {
          final i = index(x, y, z);
          final absorbed = 1.0 - math.exp(-sigma[i] * step);
          if (absorbed <= 0.0) continue;
          final weight = through * absorbed;
          for (var d = 0; d < 6; d++) {
            lit[d] += weight * math.exp(-depth[d][i]);
          }
          emitted += weight * glow[i];
          through *= 1.0 - absorbed;
        }
        final coverage = 1.0 - through;
        // Unpremultiplied: the light as it reads where the puff is opaque.
        final scale = coverage > 1e-4 ? 1.0 / coverage : 0.0;
        // Rows bottom to top within the cell: `y` counts up from the bottom.
        final out = ((top + y) * width + left + x) * 4;
        positive
          ..[out] = byte(lit[0] * scale)
          ..[out + 1] = byte(lit[2] * scale)
          ..[out + 2] = byte(lit[4] * scale)
          ..[out + 3] = byte(coverage);
        negative
          ..[out] = byte(lit[1] * scale)
          ..[out + 1] = byte(lit[3] * scale)
          ..[out + 2] = byte(lit[5] * scale)
          ..[out + 3] = byte(emitted * scale);
      }
    }
  }
  return SixWaySheet(
    columns: columns,
    rows: rows,
    cell: cell,
    positive: positive,
    negative: negative,
  );
}

/// A puff of smoke that billows out and thins over its life — the engine's
/// own, so a six-way particle has something to show with no asset at all.
///
/// A ball whose edge is broken up by a few octaves of value noise, growing
/// from half the cube to most of it while its density falls. [seed] picks the
/// noise; the same seed bakes the same bytes, in the browser as well.
SixWayField smokePuff({int seed = 1}) {
  double hash(int x, int y, int z) {
    // An integer hash, bit-mixed; any fixed permutation would do, and this one
    // needs no table. **In 32 bits, with every product under 2^53**: it was
    // written for the VM's 64-bit integers, and compiled for the web the same
    // products lost their low bits as doubles, so a browser baked another
    // puff and `smoke-six-way` stood 2% apart from the native backends.
    final h0 = _add32(
      _add32(_mul32(x, 374761393), _mul32(y, 668265263)),
      _add32(_mul32(z, 2147483647), _mul32(seed, 144269)),
    );
    final h1 = _mul32(h0 ^ (h0 >> 13), 1274126177);
    final h = h1 ^ (h1 >> 16);
    return (h & 0xffff) / 0xffff;
  }

  double smooth(double f) => f * f * (3.0 - 2.0 * f);

  double noise(double x, double y, double z) {
    final ix = x.floor();
    final iy = y.floor();
    final iz = z.floor();
    final fx = smooth(x - ix);
    final fy = smooth(y - iy);
    final fz = smooth(z - iz);
    double lerp(double a, double b, double f) => a + (b - a) * f;
    double corner(int dx, int dy, int dz) => hash(ix + dx, iy + dy, iz + dz);
    return lerp(
      lerp(
        lerp(corner(0, 0, 0), corner(1, 0, 0), fx),
        lerp(corner(0, 1, 0), corner(1, 1, 0), fx),
        fy,
      ),
      lerp(
        lerp(corner(0, 0, 1), corner(1, 0, 1), fx),
        lerp(corner(0, 1, 1), corner(1, 1, 1), fx),
        fy,
      ),
      fz,
    );
  }

  return (x, y, z, t) {
    final radius = 0.45 + 0.4 * t;
    final r = math.sqrt(x * x + y * y + z * z) / radius;
    if (r >= 1.4) return 0.0;
    // Rising: the noise drifts down through the ball, so the billows move up.
    final drift = t * 1.5;
    final n =
        noise(x * 3.0, y * 3.0 - drift, z * 3.0) * 0.6 +
        noise(x * 6.0, y * 6.0 - drift * 2.0, z * 6.0) * 0.3 +
        noise(x * 12.0, y * 12.0, z * 12.0) * 0.1;
    final shape = 1.0 - r + (n - 0.5) * 0.9;
    return (shape * 2.5).clamp(0.0, 1.0) * (1.0 - 0.6 * t);
  };
}

/// [a] times [b] modulo 2^32, the same on the VM and in a browser: [a] is
/// taken in halves so that no product reaches 2^53, where a double stops
/// holding every integer.
int _mul32(int a, int b) {
  final x = a & 0xffffffff;
  final y = b & 0xffffffff;
  final low = (x & 0xffff) * y;
  final high = (((x >> 16) * y) & 0xffff) << 16;
  return (low + high) & 0xffffffff;
}

/// [a] plus [b] modulo 2^32.
int _add32(int a, int b) => ((a & 0xffffffff) + (b & 0xffffffff)) & 0xffffffff;
