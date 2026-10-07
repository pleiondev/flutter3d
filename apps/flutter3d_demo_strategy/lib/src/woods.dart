/// Where the trees stand.
///
/// **Groves, and none in the way.** A tree here is scenery — the simulation
/// has no idea it exists, and a crowd would walk straight through one. So the
/// woods are kept off everything a crowd uses: the camps, the seams, the path
/// each camp wears to its seam, and the ground between the two camps where
/// the fighting happens. What is left — the hilltops, the far corners, the
/// slopes behind each camp — is where they grow, in clumps a value noise
/// decides, with a few strays between.
///
/// Placed from a hash of the ground, so a map grows the same woods every
/// time it is opened, and a second map grows its own.
library;

import 'dart:math' as math;

import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'ground_paint.dart';

/// Trees for [simulation]'s map: one list of placements per entry of
/// [kinds], each entry the scale that kind's model is drawn at.
///
/// The first two kinds are taken to be conifers and are favoured on high
/// ground; the rest are broadleaves and favoured low.
List<List<Matrix4>> plantWoods({
  required StrategySimulation simulation,
  required List<double> kinds,
  double? waterLevel,
  double spacing = 4.2,
}) {
  final Heightfield ground = simulation.ground;
  final List<Building> halls = simulation.buildings;
  final List<ResourceNode> seams = simulation.resources;
  final lanes = <(Vector3, Vector3)>[
    for (final Building hall in halls)
      for (final ResourceNode seam in seams)
        if (nearestSeam(hall, seams) == seam) (hall.centre, seam.at),
    for (var a = 0; a < halls.length; a++)
      for (var b = a + 1; b < halls.length; b++)
        (halls[a].centre, halls[b].centre),
  ];

  final List<List<Matrix4>> placed = <List<Matrix4>>[
    for (final _ in kinds) <Matrix4>[],
  ];
  final int across = (ground.width / spacing).floor();
  final int down = (ground.depth / spacing).floor();
  for (var j = 0; j < down; j++) {
    for (var i = 0; i < across; i++) {
      final double roll = latticeHash(i * 3 + 1, j * 7 + 2);
      final double x =
          ground.origin.x +
          (i + 0.5 + (latticeHash(i, j) - 0.5) * 0.8) * spacing;
      final double z =
          ground.origin.z +
          (j + 0.5 + (latticeHash(j + 101, i - 57) - 0.5) * 0.8) * spacing;
      final double grove = valueNoise(x / 26.0 + 5.0, z / 26.0 - 3.0);
      // Thick in a grove, the odd stray outside one.
      final bool grows = grove > 0.56 ? roll < 0.85 : roll < 0.035;
      if (!grows) continue;
      if (x < ground.origin.x + 2.0 ||
          z < ground.origin.z + 2.0 ||
          x > ground.origin.x + ground.width - 2.0 ||
          z > ground.origin.z + ground.depth - 2.0) {
        continue;
      }

      final double y = ground.heightAt(x, z);
      if (waterLevel != null && y < waterLevel + 1.0) continue;
      if (halls.any((Building it) => it.distanceTo(x, z) < 15.0)) continue;
      if (seams.any((ResourceNode it) => _flat(it.at, x, z) < 12.0)) continue;
      if (lanes.any(((Vector3, Vector3) it) => _toLane(it, x, z) < 10.0)) {
        continue;
      }

      final double pick = latticeHash(i + 911, j + 313);
      final bool high = y > 18.0;
      final int kind = kinds.length < 3
          ? (pick * kinds.length).floor()
          : high == (pick < 0.75)
          ? (pick * 7.0).floor() % 2
          : 2 + (pick * 11.0).floor() % (kinds.length - 2);
      final double scale =
          kinds[kind] * (0.8 + 0.5 * latticeHash(i - 17, j + 29));
      final double yaw = latticeHash(i + 5, j - 5) * math.pi * 2.0;
      // Sunk a little, so a tree on a slope does not stand on one edge of
      // its trunk with daylight under the other.
      placed[kind].add(
        Matrix4.translationValues(x, y - 0.2, z)
          ..rotateY(yaw)
          ..scaleByDouble(scale, scale, scale, 1.0),
      );
    }
  }
  return placed;
}

/// The seam nearest [hall], on the ground plane: the one its crowd wears a
/// path to.
ResourceNode? nearestSeam(Building hall, List<ResourceNode> seams) {
  ResourceNode? best;
  var bestDistance = double.infinity;
  for (final ResourceNode seam in seams) {
    final double d = _flat(seam.at, hall.centre.x, hall.centre.z);
    if (d < bestDistance) {
      bestDistance = d;
      best = seam;
    }
  }
  return best;
}

double _flat(Vector3 at, double x, double z) {
  final double dx = at.x - x;
  final double dz = at.z - z;
  return math.sqrt(dx * dx + dz * dz);
}

double _toLane((Vector3, Vector3) lane, double x, double z) {
  final (Vector3 from, Vector3 to) = lane;
  final double sx = to.x - from.x;
  final double sz = to.z - from.z;
  final double length2 = sx * sx + sz * sz;
  final double t = length2 == 0.0
      ? 0.0
      : (((x - from.x) * sx + (z - from.z) * sz) / length2).clamp(0.0, 1.0);
  final double dx = x - (from.x + sx * t);
  final double dz = z - (from.z + sz * t);
  return math.sqrt(dx * dx + dz * dz);
}
