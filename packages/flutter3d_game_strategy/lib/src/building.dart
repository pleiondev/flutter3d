/// Something built on the map, and the ground it takes away.
///
/// **A footprint, not a body.** A building is a rectangle on the ground and a
/// height nobody walks through; giving it a collider would put it in a
/// collision world the crowd never consults, since units read the navigation
/// grid rather than sweeping. So what a building *is*, to a simulation, is a
/// patch of ground that stops being walkable.
///
/// **Placing one re-bakes the grid, and that is affordable because it was
/// measured.** Baking a two-metre lattice over an eighty-metre map costs about
/// a millisecond — the same measurement that chose the cell size in the first
/// place — and a building is placed by a player once in a while rather than
/// sixty times a second. The alternative, a set of blockers the flow field
/// consults on every cell it sweeps, would put a test in the hottest loop the
/// genre has to save a millisecond nobody spends.
library;

import 'package:vector_math/vector_math.dart';

/// A building standing on the map.
final class Building {
  /// Builds one centred at [centre], [width] by [depth] metres.
  Building({
    required Vector3 centre,
    required this.width,
    required this.depth,
    this.name = 'building',
  }) : centre = centre.clone(),
       assert(
         width > 0.0 && depth > 0.0,
         'a building of no size takes no ground',
       );

  /// Where it stands. The Y is the ground it was placed on.
  final Vector3 centre;

  /// How far it reaches along X and Z, in metres.
  final double width;
  final double depth;

  /// What it is, for a game that has more than one kind.
  final String name;

  /// Whether `(x, z)` is under this building.
  bool covers(double x, double z) =>
      (x - centre.x).abs() <= width / 2.0 &&
      (z - centre.z).abs() <= depth / 2.0;
}
