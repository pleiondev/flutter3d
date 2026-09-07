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

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// A building standing on the map.
final class Building {
  /// Builds one centred at [centre], [width] by [depth] metres.
  Building({
    required Vector3 centre,
    required this.width,
    required this.depth,
    this.name = 'building',
    this.side = 0,
    this.sight = 30.0,
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

  /// Whose it is.
  final int side;

  /// How far it uncovers the map around itself, in metres.
  ///
  /// Further than a unit, which is the whole reason a side's first building is
  /// worth putting somewhere rather than anywhere: a hall is what a side can
  /// see from while its crowd is away digging.
  final double sight;

  /// Whether `(x, z)` is under this building.
  bool covers(double x, double z) =>
      (x - centre.x).abs() <= width / 2.0 &&
      (z - centre.z).abs() <= depth / 2.0;

  /// How far `(x, z)` is from the nearest part of the footprint, in metres.
  ///
  /// **Distance to the building, not to its middle**, and the difference is not
  /// pedantry: placing a building takes its cells out of the navigation grid,
  /// so the nearest place a unit can stand is already outside the footprint by
  /// most of a cell. A worker measured against the centre of a six-metre hall
  /// stopped six and a half metres away, was told it had not arrived, and stood
  /// there holding its load for ever. Against the edge it is a metre and a half
  /// away and home.
  double distanceTo(double x, double z) {
    final double dx = (x - centre.x).abs() - width / 2.0;
    final double dz = (z - centre.z).abs() - depth / 2.0;
    final double outX = dx > 0.0 ? dx : 0.0;
    final double outZ = dz > 0.0 ? dz : 0.0;
    return math.sqrt(outX * outX + outZ * outZ);
  }
}
