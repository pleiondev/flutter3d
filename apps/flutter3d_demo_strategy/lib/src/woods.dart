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

import 'package:flutter3d_demo_content/map_world.dart' show nearestSeam;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'ground_paint.dart';

/// The scale each of the map's kinds of tree is drawn at: two pines, then
/// three broadleaves. One list for the picture and for the world the trees
/// burn in, so both plant the same woods.
const List<double> woodScales = <double>[4.0, 3.6, 4.2, 3.4, 3.8];

/// A tree where it was planted: where its foot is, which way it is turned,
/// and how much its model is scaled.
typedef PlantedTree = ({
  double x,
  double y,
  double z,
  double yaw,
  double scale,
});

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
}) => <List<Matrix4>>[
  for (final List<PlantedTree> kind in plantTrees(
    simulation: simulation,
    kinds: kinds,
    waterLevel: waterLevel,
    spacing: spacing,
  ))
    <Matrix4>[
      // Sunk a little, so a tree on a slope does not stand on one edge of
      // its trunk with daylight under the other.
      for (final PlantedTree t in kind)
        Matrix4.translationValues(t.x, t.y - 0.2, t.z)
          ..rotateY(t.yaw)
          ..scaleByDouble(t.scale, t.scale, t.scale, 1.0),
    ],
];

/// The same woods as [plantWoods], as numbers rather than matrices: what the
/// map's world burns, which has to be the same on every platform — and a
/// matrix turned by the yaw holds `dart:math`'s sines in its scale.
List<List<PlantedTree>> plantTrees({
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
        if (nearestSeam(hall, seams) == seam) (hall.center, seam.at),
    for (var a = 0; a < halls.length; a++)
      for (var b = a + 1; b < halls.length; b++)
        (halls[a].center, halls[b].center),
  ];

  final List<List<PlantedTree>> placed = <List<PlantedTree>>[
    for (final _ in kinds) <PlantedTree>[],
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
      placed[kind].add((x: x, y: y, z: z, yaw: yaw, scale: scale));
    }
  }
  return placed;
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
