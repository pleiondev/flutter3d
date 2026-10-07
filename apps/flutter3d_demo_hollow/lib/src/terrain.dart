/// Cobble Hollow's ground: a valley with a plateau to the north the river
/// runs over, a cliff it falls off into a lagoon, a quarry to the west, the
/// village to the south-east and a volcano in the north-east corner.
///
/// The ground is a function of where you stand, so the liquids, the
/// collision mesh and the mesh that is drawn are all read off one shape and
/// cannot disagree.
library;

import 'dart:math' as math;

/// The valley's side, m, and how many cells of the liquids' grid a side.
const double hollowSize = 64.0;
const int hollowCells = 128;
const double hollowCell = hollowSize / hollowCells;

/// The plateau's edge: the cliff runs across the valley between these z.
const double cliffTop = 20.0, cliffFoot = 21.5;

/// The lagoon: its middle and radius, and how deep its bowl is.
const double lagoonX = 24.0, lagoonZ = 29.0, lagoonRadius = 7.0;

/// The volcano: its middle, its foot's radius and its height over the
/// plateau, and its crater's radius.
const double volcanoX = 52.0, volcanoZ = 10.0;
const double volcanoRadius = 13.0, volcanoHeight = 13.0, craterRadius = 2.2;

/// The quarry: its middle and half its width and length.
const double quarryX = 10.0, quarryZ = 47.0;
const double quarryHalfX = 5.0, quarryHalfZ = 4.0;

/// Where the builder waits for stone, and the village.
const double siteX = 32.0, siteZ = 51.0, siteRadius = 3.0;
const double villageX = 47.0, villageZ = 48.0;

/// Where the spring wells up on the plateau.
const double springX = 12.0, springZ = 5.0;

/// The river's line over the plateau: x at a given z, reaching the cliff at
/// the lagoon's x.
double riverX(double z) {
  final t = ((z - springZ) / (cliffTop - springZ)).clamp(0.0, 1.0);
  return springX +
      (lagoonX - springX) * t * t * (3 - 2 * t) +
      2.0 * math.sin(0.5 * z);
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _bump(double distance, double width) {
  final t = distance / width;
  return t >= 1.0 ? 0.0 : 1.0 - t * t;
}

/// Gentle rolling of the ground, a few decimetres: value noise of two
/// octaves on a fixed lattice, so the valley is the same every run.
double _roll(double x, double z) {
  double lattice(int i, int j) {
    var h = (i * 374761393 + j * 668265263) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return (h & 0xffff) / 0xffff;
  }

  double octave(double x, double z) {
    final i = x.floor(), j = z.floor();
    final fx = x - i, fz = z - j;
    final sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz);
    final a = lattice(i, j), b = lattice(i + 1, j);
    final c = lattice(i, j + 1), d = lattice(i + 1, j + 1);
    return a + (b - a) * sx + (c - a) * sz + (a - b - c + d) * sx * sz;
  }

  return 0.35 * octave(x / 6, z / 6) + 0.15 * octave(x / 2.5, z / 2.5);
}

/// The ground's height at (x, z), m.
double groundAt(double x, double z) {
  // The valley floor, rolling a little, its walls rising at the edges.
  final fromEdge = math.min(
    math.min(x, hollowSize - x),
    math.min(z, hollowSize - z),
  );
  final walls = 5.0 * (1.0 - _smooth(0.0, 5.0, fromEdge));
  var h = 1.0 + _roll(x, z) + walls;
  // The plateau to the north, its river cut into it.
  final plateau = 5.5 * (1.0 - _smooth(cliffTop, cliffFoot, z));
  if (plateau > 0.0) {
    final off = (x - riverX(math.min(z, cliffTop))).abs();
    final bed =
        0.7 * _bump(off, 1.6) * (1.0 - _smooth(cliffTop - 0.3, cliffTop, z));
    h +=
        plateau -
        bed +
        0.05 * off * (1.0 - _smooth(cliffTop - 1, cliffFoot, z));
  }
  // The lagoon's bowl, and the channel draining it east.
  final toLagoon = math.sqrt(
    math.pow(x - lagoonX, 2) + math.pow(z - lagoonZ, 2),
  );
  h -= 3.2 * _bump(toLagoon, lagoonRadius);
  if (x > lagoonX) {
    // Wide and shallow, its banks gentle: a ford the car can cross, the
    // water knee-deep in its middle.
    final across = (z - (lagoonZ + 0.1 * (x - lagoonX))).abs();
    final channel = 1.0 - _smooth(0.5, 3.5, across);
    h -=
        channel *
        (0.55 * _smooth(lagoonX + 4, lagoonX + 7, x) + 0.012 * (x - lagoonX));
  }
  // The quarry: a pit with straight walls, a ramp up its east side.
  final qx = (x - quarryX).abs() / quarryHalfX;
  final qz = (z - quarryZ).abs() / quarryHalfZ;
  final inQuarry = 1.0 - _smooth(0.85, 1.0, math.max(qx, qz));
  final ramp = _smooth(quarryX, quarryX + quarryHalfX + 3, x);
  h -= 2.2 * inQuarry * (1.0 - ramp);
  // The volcano, its crater open at the top.
  final toVolcano = math.sqrt(
    math.pow(x - volcanoX, 2) + math.pow(z - volcanoZ, 2),
  );
  final cone =
      volcanoHeight *
          math.pow((1.0 - toVolcano / volcanoRadius).clamp(0.0, 1.0), 1.4) -
      3.0 * _bump(toVolcano, craterRadius);
  if (toVolcano < volcanoRadius) {
    h = math.max(h, 1.0 + 5.5 * (1.0 - _smooth(cliffTop, cliffFoot, z)) + cone);
  }
  // Flat ground where the village and the builder stand.
  final flat = math.max(
    _bump(math.sqrt(math.pow(x - villageX, 2) + math.pow(z - villageZ, 2)), 9),
    _bump(math.sqrt(math.pow(x - siteX, 2) + math.pow(z - siteZ, 2)), 5),
  );
  return h + (1.2 - h) * flat * _smooth(0.0, 0.2, flat);
}

/// The ground at every cell's centre of a grid [cells] a side of [cell]
/// metres from [x0], [z0], x fastest.
List<double> groundGrid({
  double x0 = 0.0,
  double z0 = 0.0,
  int nx = hollowCells,
  int nz = hollowCells,
  double cell = hollowCell,
}) => <double>[
  for (var j = 0; j < nz; j++)
    for (var i = 0; i < nx; i++)
      groundAt(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell),
];
