/// Bakes Cobble Hollow's ground into one picture the size of the valley:
///
///     dart run tool/bake_ground.dart
///
/// The ground is one mesh with one material, and a material takes one base
/// colour map. So the grass, the trodden earth, the sand by the water, the
/// bare rock of the cliffs and the quarry and the basalt of the volcano are
/// laid out here, once, from the same [groundAt] the physics and the drawn
/// mesh read: each pixel takes the tiles of `assets_src/ground/` at their
/// own scale in metres, blended where one cover gives way to the next, and
/// the result is `assets/textures/ground.jpg`, which the ground's mesh maps
/// over the whole valley.
///
/// Run it again after changing the valley's shape or the tiles.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_demo_hollow/src/terrain.dart';
import 'package:image/image.dart' as img;

/// Pixels a side of the baked picture: three centimetres a pixel.
const int _size = 2048;

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  _Tile tile(String name, double metres, {List<double>? tint}) =>
      _Tile.read('$root/assets_src/ground/$name.jpg', metres, tint);
  // Leafy grass, a little greener than the photograph's late summer.
  final grass = tile('grass', 3.5, tint: <double>[0.74, 0.95, 0.6]);
  final earth = tile('earth', 4.0);
  final sand = tile('sand', 5.0);
  final rock = tile('rock', 5.0, tint: <double>[0.78, 0.76, 0.72]);
  final rubble = tile('rubble', 2.5);
  // Grey-black, warmed a little towards the brown of weathered lava.
  final basalt = tile('basalt', 6.0, tint: <double>[1.0, 0.94, 0.88]);

  final out = Uint8List(_size * _size * 3);
  const metres = hollowSize / _size;
  final colour = Float64List(3);
  for (var py = 0; py < _size; py++) {
    final z = (py + 0.5) * metres;
    for (var px = 0; px < _size; px++) {
      final x = (px + 0.5) * metres;
      _cover(
        x,
        z,
        colour,
        grass: grass,
        earth: earth,
        sand: sand,
        rock: rock,
        rubble: rubble,
        basalt: basalt,
      );
      final o = (px + py * _size) * 3;
      out[o] = colour[0].round().clamp(0, 255);
      out[o + 1] = colour[1].round().clamp(0, 255);
      out[o + 2] = colour[2].round().clamp(0, 255);
    }
  }
  final picture = img.Image.fromBytes(
    width: _size,
    height: _size,
    bytes: out.buffer,
    numChannels: 3,
  );
  final path = '$root/assets/textures/ground.jpg';
  await File(path).writeAsBytes(img.encodeJpg(picture, quality: 84));
  stdout.writeln('wrote $path');
}

/// What covers the ground at (x, z), into [into] as sRGB bytes: grass on
/// the level, bare rock where it is steep, pebbles in the river's bed, sand
/// by the lagoon and in the ford, rubble on the quarry's floor, basalt on
/// the volcano, trodden earth where the village and the builder stand.
///
/// Each cover over the last, as a painter would lay them, and every edge
/// frayed by a little noise so no boundary is a drawn circle.
void _cover(
  double x,
  double z,
  Float64List into, {
  required _Tile grass,
  required _Tile earth,
  required _Tile sand,
  required _Tile rock,
  required _Tile rubble,
  required _Tile basalt,
}) {
  const d = 0.25;
  final h = groundAt(x, z);
  final nx = (groundAt(x - d, z) - groundAt(x + d, z)) / (2 * d);
  final nz = (groundAt(x, z - d) - groundAt(x, z + d)) / (2 * d);
  final up = 1.0 / math.sqrt(nx * nx + 1.0 + nz * nz);
  final fray = _noise(x / 2.2, z / 2.2) - 0.5;
  final patch = _noise(x / 9.0 + 17.0, z / 9.0 - 5.0);

  // Grass, darker and lighter in broad patches as a meadow is.
  grass.sample(x, z, into);
  _scale(into, 0.82 + 0.3 * patch);
  void over(_Tile tile, double amount, [double bright = 1.0]) {
    final a = amount.clamp(0.0, 1.0);
    if (a <= 0.0) return;
    final r = into[0], g = into[1], b = into[2];
    tile.sample(x, z, into);
    into[0] = r + (into[0] * bright - r) * a;
    into[1] = g + (into[1] * bright - g) * a;
    into[2] = b + (into[2] * bright - b) * a;
  }

  final steep = (1.0 - up) * 4.0 - 0.35 + 0.6 * fray;
  over(rock, steep * 1.5, 0.9 + 0.2 * patch);

  // The river's bed over the plateau, under the water.
  if (z < cliffTop + 1.0) {
    final off = (x - riverX(math.min(z, cliffTop))).abs();
    over(rubble, (1.9 - off + fray) * 1.5, 0.8);
  }
  final dl =
      math.sqrt(math.pow(x - lagoonX, 2) + math.pow(z - lagoonZ, 2)) /
      lagoonRadius;
  over(sand, (1.3 - dl + 0.15 * fray) * 3.0);
  if (x > lagoonX) {
    final across = (z - (lagoonZ + 0.1 * (x - lagoonX))).abs();
    over(sand, (3.2 - across + fray) * 0.8, 0.95);
  }
  final dq = math.max(
    (x - quarryX).abs() / quarryHalfX,
    (z - quarryZ).abs() / quarryHalfZ,
  );
  over(rubble, (1.05 - dq + 0.1 * fray) * 6.0);
  final dv =
      math.sqrt(math.pow(x - volcanoX, 2) + math.pow(z - volcanoZ, 2)) /
      volcanoRadius;
  over(basalt, (1.0 - dv + 0.15 * fray) * 3.5, 0.85 + 0.3 * patch);
  final dvill =
      math.sqrt(math.pow(x - villageX, 2) + math.pow(z - villageZ, 2)) / 8.0;
  final dsite = math.sqrt(math.pow(x - siteX, 2) + math.pow(z - siteZ, 2)) / 4;
  over(earth, (1.1 - math.min(dvill, dsite) + 0.25 * fray) * 1.4 - patch * 0.3);
  // A little darker where the ground lies low, as wet ground is.
  _scale(into, 0.94 + 0.06 * ((h - 0.5) / 2.0).clamp(0.0, 1.0));
}

void _scale(Float64List c, double by) {
  c[0] *= by;
  c[1] *= by;
  c[2] *= by;
}

/// Smooth value noise on a fixed lattice, nought to one.
double _noise(double x, double z) {
  double lattice(int i, int j) {
    var h = (i * 374761393 + j * 668265263) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return (h & 0xffff) / 0xffff;
  }

  final i = x.floor(), j = z.floor();
  final fx = x - i, fz = z - j;
  final sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz);
  final a = lattice(i, j), b = lattice(i + 1, j);
  final c = lattice(i, j + 1), e = lattice(i + 1, j + 1);
  return a + (b - a) * sx + (c - a) * sz + (a - b - c + e) * sx * sz;
}

/// One ground photograph, repeating every [metres], already shrunk to the
/// pixels it covers at the baked scale so that sampling it does not alias.
final class _Tile {
  _Tile(this._pixels, this._side, this.metres);

  factory _Tile.read(String path, double metres, List<double>? tint) {
    final decoded = img.decodeJpg(File(path).readAsBytesSync());
    if (decoded == null) throw StateError('$path is not a JPEG');
    final side = (metres / hollowSize * _size).round();
    final small = img.copyResize(
      decoded,
      width: side,
      height: side,
      interpolation: img.Interpolation.average,
    );
    final t = tint ?? const <double>[1.0, 1.0, 1.0];
    final pixels = Float64List(side * side * 3);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final p = small.getPixel(x, y);
        final o = (x + y * side) * 3;
        pixels[o] = p.r * t[0];
        pixels[o + 1] = p.g * t[1];
        pixels[o + 2] = p.b * t[2];
      }
    }
    return _Tile(pixels, side, metres);
  }

  final Float64List _pixels;
  final int _side;
  final double metres;

  /// The tile's colour at world (x, z), into [into]: the photograph as it
  /// lies in some broad patches and turned a quarter and shifted in others,
  /// so that its repeat does not march across the valley in rows.
  void sample(double x, double z, Float64List into) {
    final w = _noise(x / 7.0 + 31.0, z / 7.0 - 11.0);
    final turned = ((w - 0.38) / 0.24).clamp(0.0, 1.0);
    final a = turned * turned * (3 - 2 * turned);
    if (a < 1.0) _bilinear(x, z, into);
    if (a <= 0.0) return;
    final r = into[0], g = into[1], b = into[2];
    _bilinear(z + 0.37 * metres, -x + 0.61 * metres, into);
    if (a >= 1.0) return;
    into[0] = r + (into[0] - r) * a;
    into[1] = g + (into[1] - g) * a;
    into[2] = b + (into[2] - b) * a;
  }

  /// The photograph's colour at (x, z), bilinear and wrapping, into [into].
  void _bilinear(double x, double z, Float64List into) {
    final u = x / metres * _side - 0.5, v = z / metres * _side - 0.5;
    final i = u.floor(), j = v.floor();
    final fu = u - i, fv = v - j;
    final i0 = i % _side, i1 = (i + 1) % _side;
    final j0 = j % _side, j1 = (j + 1) % _side;
    for (var c = 0; c < 3; c++) {
      final a = _pixels[(i0 + j0 * _side) * 3 + c];
      final b = _pixels[(i1 + j0 * _side) * 3 + c];
      final e = _pixels[(i0 + j1 * _side) * 3 + c];
      final f = _pixels[(i1 + j1 * _side) * 3 + c];
      into[c] = (a + (b - a) * fu) * (1 - fv) + (e + (f - e) * fu) * fv;
    }
  }
}
