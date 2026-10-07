/// Wreck Reef's sea floor: a reef flat to the west where the boat rides at
/// anchor, the reef's wall dropping off it with heads of coral standing out
/// of the slope, and a sand plain beyond where the ship lies.
///
/// The floor is a function of where you stand, so the sea's grid, the
/// collision mesh and the mesh that is drawn are read off one shape.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// The sea's side, m, and how many cells of its grid a side.
const double reefSize = 64.0;
const int seaCells = 64;
const double seaCell = reefSize / seaCells;

/// How many vertices a side the drawn and the solid floor have.
const int floorCells = 128;
const double floorCell = reefSize / floorCells;

/// The reef flat's depth, where its wall begins and ends, and the sand
/// plain's depth below it, m.
const double flatDepth = 4.0, wallTop = 18.0, wallFoot = 27.0;
const double plainDepth = 14.5;

/// Where the boat rides, over the flat.
const double boatX = 12.0, boatZ = 32.0;

/// The ship: where its middle lies, which way its bow points, radians from
/// +x, and half its length and beam.
const double wreckX = 43.0, wreckZ = 34.0, wreckHeading = 0.55;
const double wreckHalfLength = 9.0, wreckHalfBeam = 2.6;

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// Value noise of two octaves on a fixed lattice: the floor's ripples and
/// hummocks, the same every run.
double _noise(double x, double z) {
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

  return 0.6 * octave(x / 5, z / 5) + 0.25 * octave(x / 1.7, z / 1.7);
}

/// The coral heads standing out of the wall and the flat's edge: where,
/// and how wide and high.
const List<(double, double, double, double)> coralHeads =
    <(double, double, double, double)>[
      (17.0, 14.0, 2.2, 2.4),
      (19.5, 24.0, 1.8, 3.0),
      (22.0, 40.0, 2.6, 3.4),
      (18.0, 50.0, 2.0, 2.2),
      (24.5, 31.0, 1.6, 2.6),
      (21.0, 7.0, 2.4, 2.8),
      (26.0, 55.0, 1.9, 2.5),
    ];

/// The floor's height at (x, z), m: nought is the sea's surface.
double floorAt(double x, double z) {
  // Down the wall from the flat to the plain, the wall's line wandering.
  final edge = wallTop + 2.0 * math.sin(z * 0.21);
  final drop = _smooth(edge, edge + (wallFoot - wallTop), x);
  var h = -flatDepth - (plainDepth - flatDepth) * drop;
  // The plain sinks a little further out; the flat and the plain ripple.
  h -= 1.5 * _smooth(wallFoot, reefSize, x);
  h += 0.5 * _noise(x, z) - 0.25;
  // Coral heads: rounded mounds rising off the slope.
  for (final (cx, cz, r, rise) in coralHeads) {
    final d = math.sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)) / r;
    if (d < 1.0) h += rise * (1.0 - d * d) * (1.0 - d * d);
  }
  // A scour round the ship, where the current dug the sand.
  final dx = x - wreckX, dz = z - wreckZ;
  final along = dx * math.cos(wreckHeading) + dz * math.sin(wreckHeading);
  final across = -dx * math.sin(wreckHeading) + dz * math.cos(wreckHeading);
  final scour = math.sqrt(
    math.pow(along / (wreckHalfLength + 3.0), 2) +
        math.pow(across / (wreckHalfBeam + 3.0), 2),
  );
  if (scour < 1.0) h -= 0.6 * (1.0 - scour * scour);
  return h;
}

/// How much of rock the floor is at (x, z), nought sand to one reef: where
/// the floor is steep, where a coral head rises off it, and in patches over
/// the flat, whose top is old reef with sand lying in its hollows.
double rockinessAt(double x, double z) {
  const d = floorCell;
  final normal = Vector3(
    -(floorAt(x + d, z) - floorAt(x - d, z)) / (2 * d),
    1.0,
    -(floorAt(x, z + d) - floorAt(x, z - d)) / (2 * d),
  )..normalize();
  final steep = ((1.0 - normal.y) * 6.0).clamp(0.0, 1.0);
  var head = 0.0;
  for (final (cx, cz, r, _) in coralHeads) {
    final d = math.sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)) / r;
    head = math.max(head, (1.4 - d * 1.2).clamp(0.0, 1.0));
  }
  final edge = wallTop + 2.0 * math.sin(z * 0.21);
  final flat =
      x < edge + 1.0 &&
      math.sin(x * 0.9 + 2.0 * math.sin(z * 0.43)) +
              math.sin(z * 0.7 + 1.3 * math.sin(x * 0.37)) >
          0.6;
  return math.max(math.max(steep, head), flat ? 1.0 : 0.0);
}

/// How far the floor that is drawn stands above the one the diver touches,
/// m: where it is rock, lumps up to half a metre high and ledges down the
/// wall, so the reef is a rough crust rather than a picture of one on a
/// smooth slope; it gives out to nothing on the sand, as the reef does.
/// The diver's solid floor stays the smooth one: a quarter of a metre
/// under the lumps on most of the rock is too little to be seen to sink
/// into it.
double reliefAt(double x, double z) {
  final t = ((rockinessAt(x, z) - 0.2) / 0.6).clamp(0.0, 1.0);
  final lumps =
      _noise(x * 1.1 + 31.0, z * 1.1 + 7.0) +
      0.6 * _noise(x * 2.2 + 5.0, z * 2.2 + 13.0);
  // Down the wall, ledges near three metres apart in depth and wandering,
  // as a reef grows outwards in its own terraces: under each lip the wall
  // is cut back into the solid floor rather than built out from it, so the
  // diver swimming along it may hang off it but never stands inside it.
  final h = floorAt(x, z);
  final wall = _smooth(-5.0, -7.0, h) * _smooth(-15.5, -13.0, h);
  final phase = h / 2.8 + 1.5 * _noise(x * 0.4 + 3.0, z * 0.4 + 11.0);
  final under = 1.0 - (phase - phase.floorToDouble());
  return t * t * (3.0 - 2.0 * t) * (0.4 * lumps - 1.3 * wall * under * under);
}

/// The floor that is drawn: [floorAt] with the reef's [reliefAt] on it,
/// for whatever grows on the reef to stand on.
double drawnFloorAt(double x, double z) => floorAt(x, z) + reliefAt(x, z);

/// The sea's floor, a height a cell of a grid [cells] a side of [cell]
/// metres, x fastest: the lowest of the floor over the cell, so whatever
/// lies on the finer floor that is drawn and touched is in the water the
/// grid holds, and the sea lifts it.
List<double> floorGrid({int cells = seaCells, double cell = seaCell}) {
  double lowest(int i, int j) {
    var low = double.infinity;
    for (var b = 0; b <= 4; b++) {
      for (var a = 0; a <= 4; a++) {
        low = math.min(low, floorAt((i + a / 4) * cell, (j + b / 4) * cell));
      }
    }
    return low;
  }

  return <double>[
    for (var j = 0; j < cells; j++)
      for (var i = 0; i < cells; i++) lowest(i, j),
  ];
}
