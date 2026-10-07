/// The hillside as one picture: grass, worn earth, rock and shore, painted
/// once at load from the map itself.
///
/// **Painted, because the ground is one mesh with one material.** A shader
/// that blended four textures by slope and height would be the usual answer,
/// and this engine draws terrain through the same lit surface as everything
/// else; so the blend happens here, on the processor, into a single texture
/// stretched over the whole map. At 2048 texels across 160 metres that is
/// about eight centimetres a texel — finer than anything the map camera gets
/// close enough to see.
///
/// **From the map rather than for it.** What makes rock is the slope of the
/// heightfield, what makes sand is how near the ground comes to the water,
/// and what makes bare earth is where the halls stand, where the seams are
/// and the line a crowd wears between them. None of it is authored, so a
/// second map is painted the moment it loads and agrees with its own hills.
///
/// Nothing here reads or changes the match: the inputs are copied out of it
/// before the painting starts, which is also what lets the painting run on
/// another isolate.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// The five textures the ground is painted from, each a square tile.
final class GroundSwatches {
  /// Holds the tiles; every one must be square and the same size.
  const GroundSwatches({
    required this.grass,
    required this.meadow,
    required this.earth,
    required this.rock,
    required this.sand,
  });

  /// The main cover.
  final Rgba8Image grass;

  /// A lighter, drier grass the main cover gives way to in patches.
  final Rgba8Image meadow;

  /// Bare, trodden earth: camps, seams and the paths between them.
  final Rgba8Image earth;

  /// What steep slopes are.
  final Rgba8Image rock;

  /// The shore.
  final Rgba8Image sand;
}

/// A patch of ground worn bare: a footprint and how far the wear spreads
/// past it, in metres.
typedef Wear = ({
  double x,
  double z,
  double halfWidth,
  double halfDepth,
  double spread,
});

/// A trodden path from one point to another, [width] metres across.
typedef Trail = ({
  double fromX,
  double fromZ,
  double toX,
  double toZ,
  double width,
});

/// Paints [ground] into a [size]-texel square, on another isolate.
///
/// The texture's U runs along X and V along Z, one repeat across the whole
/// width of the map — draw it with `metresPerTexture` equal to the map's
/// width. [waterLevel] is where the shore is drawn, or null for none.
Future<Rgba8Image> paintGround({
  required Heightfield ground,
  required GroundSwatches swatches,
  List<Wear> wear = const <Wear>[],
  List<Trail> trails = const <Trail>[],
  double? waterLevel,
  int size = 2048,
  double metresPerSwatch = 10.0,
}) {
  final heights = Float32List(ground.columns * ground.rows);
  for (var row = 0; row < ground.rows; row++) {
    for (var column = 0; column < ground.columns; column++) {
      heights[row * ground.columns + column] = ground.sample(column, row);
    }
  }
  final job = _Job(
    heights: heights,
    columns: ground.columns,
    rows: ground.rows,
    cellSize: ground.cellSize,
    originX: ground.origin.x,
    originZ: ground.origin.z,
    swatches: swatches,
    wear: wear,
    trails: trails,
    waterLevel: waterLevel,
    size: size,
    metresPerSwatch: metresPerSwatch,
  );
  return Isolate.run(job.paint);
}

/// Everything the painting needs, as plain data an isolate can be handed.
final class _Job {
  _Job({
    required this.heights,
    required this.columns,
    required this.rows,
    required this.cellSize,
    required this.originX,
    required this.originZ,
    required this.swatches,
    required this.wear,
    required this.trails,
    required this.waterLevel,
    required this.size,
    required this.metresPerSwatch,
  });

  final Float32List heights;
  final int columns;
  final int rows;
  final double cellSize;
  final double originX;
  final double originZ;
  final GroundSwatches swatches;
  final List<Wear> wear;
  final List<Trail> trails;
  final double? waterLevel;
  final int size;
  final double metresPerSwatch;

  double get _width => (columns - 1) * cellSize;
  double get _depth => (rows - 1) * cellSize;

  /// The height under `(x, z)`, bilinear between samples and clamped at the
  /// rim. Smoother than the triangles the mesh is built from, which is what
  /// a painted slope wants: the texture should not show the lattice.
  double _height(double x, double z) {
    final double u = ((x - originX) / cellSize).clamp(0.0, columns - 1.0001);
    final double v = ((z - originZ) / cellSize).clamp(0.0, rows - 1.0001);
    final int c = u.floor();
    final int r = v.floor();
    final double fu = u - c;
    final double fv = v - r;
    final int i = r * columns + c;
    final double top = heights[i] + (heights[i + 1] - heights[i]) * fu;
    final double bottom =
        heights[i + columns] +
        (heights[i + columns + 1] - heights[i + columns]) * fu;
    return top + (bottom - top) * fv;
  }

  Rgba8Image paint() {
    final pixels = Uint8List(size * size * 4);
    final double metresPerTexel = _width / size;
    // Where a texel's U of nought lands in the world: HeightfieldGeometry
    // writes U as `x / metresPerTexture` from the world origin, not the
    // map's, so a map that does not start at nought starts part-way across
    // the texture, and the painting has to start there too.
    final double shiftX = _fraction(originX / _width);
    final double shiftZ = _fraction(originZ / _depth);
    final double step = metresPerTexel * 1.5;

    final _Tile grass = _Tile(swatches.grass, metresPerSwatch);
    final _Tile meadow = _Tile(swatches.meadow, metresPerSwatch * 1.3);
    final _Tile earth = _Tile(swatches.earth, metresPerSwatch * 0.8);
    final _Tile rock = _Tile(swatches.rock, metresPerSwatch * 1.2);
    final _Tile sand = _Tile(swatches.sand, metresPerSwatch);
    final colour = Float64List(3);
    final mix = Float64List(3);

    for (var j = 0; j < size; j++) {
      final double z = originZ + _fraction((j + 0.5) / size - shiftZ) * _depth;
      for (var i = 0; i < size; i++) {
        final double x =
            originX + _fraction((i + 0.5) / size - shiftX) * _width;
        final double h = _height(x, z);
        final double gx =
            (_height(x + step, z) - _height(x - step, z)) / (2.0 * step);
        final double gz =
            (_height(x, z + step) - _height(x, z - step)) / (2.0 * step);
        final double slope = math.sqrt(gx * gx + gz * gz);

        // Patches: two octaves of value noise, one broad and one fine, so a
        // field is not one green and a path's edge is not a ruled line.
        final double broad = valueNoise(x / 23.0, z / 23.0);
        final double fine = valueNoise(x / 4.0 + 17.0, z / 4.0 - 9.0);
        final double patchy = broad * 0.7 + fine * 0.3;

        grass.sample(x, z, colour);
        meadow.sample(x + 3.1, z - 7.7, mix);
        _blend(colour, mix, _smooth(0.42, 0.68, patchy));

        final double worn = _worn(x, z, fine);
        if (worn > 0.0) {
          earth.sample(x, z, mix);
          _blend(colour, mix, worn);
        }

        final double steep = _smooth(0.42, 0.72, slope + (fine - 0.5) * 0.18);
        if (steep > 0.0) {
          rock.sample(x, z, mix);
          _blend(colour, mix, steep);
        }

        final double? level = waterLevel;
        if (level != null) {
          final double shore =
              1.0 - _smooth(level + 0.15, level + 0.8 + fine * 0.5, h);
          if (shore > 0.0) {
            // Damp sand, a shade under the swatch's dry beach.
            sand.sample(x, z, mix);
            mix[0] *= 0.8;
            mix[1] *= 0.78;
            mix[2] *= 0.74;
            _blend(colour, mix, shore);
          }
          // Under the surface the bed darkens and greens, so the water
          // reads as deep in the middle rather than as a sheet of glass.
          if (h < level) {
            final double deep = _smooth(0.0, 2.5, level - h);
            colour[0] *= 1.0 - 0.55 * deep;
            colour[1] *= 1.0 - 0.40 * deep;
            colour[2] *= 1.0 - 0.30 * deep;
          }
        }

        // Hollows a touch darker and crests a touch lighter: what a sun
        // straight overhead would leave, and what keeps a gentle slope from
        // reading as flat under the map camera.
        final double light = 0.84 + 0.16 * _smooth(-0.6, 0.6, -gx * 0.5 - gz);

        final int at = (j * size + i) * 4;
        pixels[at] = _byte(colour[0] * light);
        pixels[at + 1] = _byte(colour[1] * light);
        pixels[at + 2] = _byte(colour[2] * light);
        pixels[at + 3] = 255;
      }
    }
    return Rgba8Image(width: size, height: size, pixels: pixels);
  }

  /// How bare the ground at `(x, z)` is worn, nought to one.
  double _worn(double x, double z, double fine) {
    var worn = 0.0;
    final double ragged = (fine - 0.5) * 2.0;
    for (final Wear it in wear) {
      final double dx = (x - it.x).abs() - it.halfWidth;
      final double dz = (z - it.z).abs() - it.halfDepth;
      final double outside = math.sqrt(
        math.max(dx, 0.0) * math.max(dx, 0.0) +
            math.max(dz, 0.0) * math.max(dz, 0.0),
      );
      final double w =
          1.0 - _smooth(it.spread * 0.4, it.spread, outside + ragged);
      if (w > worn) worn = w;
    }
    for (final Trail it in trails) {
      final double d = _toSegment(x, z, it);
      final double w =
          1.0 - _smooth(it.width * 0.25, it.width * 0.5, d + ragged * 0.5);
      // A path is worn less than a camp: grass still grows up its middle.
      if (w * 0.85 > worn) worn = w * 0.85;
    }
    return worn;
  }

  static double _toSegment(double x, double z, Trail it) {
    final double sx = it.toX - it.fromX;
    final double sz = it.toZ - it.fromZ;
    final double length2 = sx * sx + sz * sz;
    final double t = length2 == 0.0
        ? 0.0
        : (((x - it.fromX) * sx + (z - it.fromZ) * sz) / length2).clamp(
            0.0,
            1.0,
          );
    final double dx = x - (it.fromX + sx * t);
    final double dz = z - (it.fromZ + sz * t);
    return math.sqrt(dx * dx + dz * dz);
  }
}

/// One swatch, tiled across the world at [metres] a repeat.
final class _Tile {
  _Tile(Rgba8Image image, this.metres)
    : _pixels = image.pixels,
      _side = image.width;

  final Uint8List _pixels;
  final int _side;
  final double metres;

  /// The swatch's colour at world `(x, z)`, as linear-ish 0..1 floats in
  /// [out]. Nearest texel: the painting is already about as fine as the
  /// swatch, so filtering here would only blur it twice.
  void sample(double x, double z, Float64List out) {
    final int i = (_fraction(x / metres) * _side).floor() % _side;
    final int j = (_fraction(z / metres) * _side).floor() % _side;
    final int at = (j * _side + i) * 4;
    out[0] = _pixels[at] / 255.0;
    out[1] = _pixels[at + 1] / 255.0;
    out[2] = _pixels[at + 2] / 255.0;
  }
}

/// Shrinks a square [image] by whole factors until it is no wider than
/// [side], averaging each block — what a tile wants before it is laid on
/// the ground at about one of its texels per painted texel.
Rgba8Image shrinkSwatch(Rgba8Image image, int side) {
  var current = image;
  while (current.width > side) {
    final int half = current.width ~/ 2;
    final Uint8List from = current.pixels;
    final int w = current.width;
    final out = Uint8List(half * half * 4);
    for (var j = 0; j < half; j++) {
      for (var i = 0; i < half; i++) {
        for (var c = 0; c < 4; c++) {
          final int a = ((2 * j) * w + 2 * i) * 4 + c;
          final int b = ((2 * j + 1) * w + 2 * i) * 4 + c;
          out[(j * half + i) * 4 + c] =
              (from[a] + from[a + 4] + from[b] + from[b + 4] + 2) >> 2;
        }
      }
    }
    current = Rgba8Image(width: half, height: half, pixels: out);
  }
  return current;
}

void _blend(Float64List into, Float64List other, double t) {
  if (t <= 0.0) return;
  final double k = t >= 1.0 ? 1.0 : t;
  into[0] += (other[0] - into[0]) * k;
  into[1] += (other[1] - into[1]) * k;
  into[2] += (other[2] - into[2]) * k;
}

double _fraction(double v) => v - v.floorToDouble();

double _smooth(double edge0, double edge1, double v) {
  final double t = ((v - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

int _byte(double v) => (v * 255.0).round().clamp(0, 255);

/// Smooth value noise in nought to one, from a hash of the lattice corners —
/// the same answer on every run and every machine, which a painting that a
/// screenshot is compared against has to be.
double valueNoise(double x, double z) {
  final int x0 = x.floor();
  final int z0 = z.floor();
  final double fx = x - x0;
  final double fz = z - z0;
  final double sx = fx * fx * (3.0 - 2.0 * fx);
  final double sz = fz * fz * (3.0 - 2.0 * fz);
  final double a = latticeHash(x0, z0);
  final double b = latticeHash(x0 + 1, z0);
  final double c = latticeHash(x0, z0 + 1);
  final double d = latticeHash(x0 + 1, z0 + 1);
  final double top = a + (b - a) * sx;
  final double bottom = c + (d - c) * sx;
  return top + (bottom - top) * sz;
}

/// A number in nought to one that depends only on the lattice point
/// `(x, z)` — what [valueNoise] blends between, and what scatters anything
/// else that has to land in the same place on every run.
double latticeHash(int x, int z) {
  var h = (x * 374761393 + z * 668265263) & 0xffffffff;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff;
  h ^= h >> 16;
  return (h & 0xffff) / 65535.0;
}
