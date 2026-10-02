import 'dart:math' as math;

import '../../math/tolerances.dart';

/// The numbers a navigation mesh is baked to, in metres and radians.
///
/// **Turned into whole voxels once, here, and never again.** Every stage after
/// the voxeliser compares integers: a floor is so many voxels up, a step is so
/// many voxels tall. Two platforms that agree on the conversion therefore agree
/// on everything downstream, and the conversion is one division and one
/// rounding apiece — operations IEEE 754 pins — so they do agree.
final class NavMeshConfig {
  const NavMeshConfig({
    this.cellSize = 0.5,
    this.cellHeight = 0.1,
    this.agentHeight = 1.7,
    this.stepHeight = 0.4,
    this.agentRadius = 0.3,
    this.maxSlope = 0.698,
    this.maxEdgeError = 1.3,
    this.maxVerticesPerPolygon = 6,
    this.minIslandArea = 0.0,
  }) : assert(cellSize > 0.0, 'a cell of no width has no place to stand'),
       assert(
         cellHeight > 0.0,
         'a voxel of no height cannot tell floors apart',
       ),
       assert(
         maxVerticesPerPolygon >= 3,
         'a polygon has three corners at least',
       );

  /// The horizontal lattice, in metres. Half a metre by default, the same as
  /// `NavGrid`, so the two bakes of one level stand on the same cells and a
  /// test can hold one against the other.
  final double cellSize;

  /// The vertical lattice, in metres. A tenth of a metre resolves every step a
  /// level is built with and keeps a forty-metre level under four hundred
  /// voxels tall.
  final double cellHeight;

  /// Room an agent needs above a floor for the floor to count.
  final double agentHeight;

  /// The tallest ledge an agent walks up. Matches `CharacterTuning.stepHeight`
  /// for the reason `NavGrid.stepHeight` gives: a mesh that promises a step
  /// the controller will not take sends agents into walls for ever.
  ///
  /// On terrain, `cellSize * tan(maxSlope)` has to stay under this, or the
  /// rise between two neighbouring cells of a walkable hillside reads as a
  /// ledge and the hill is cut into terraces.
  final double stepHeight;

  /// How far the mesh keeps away from walls and edges. A body of this radius
  /// standing anywhere on the mesh does not overlap anything.
  final double agentRadius;

  /// The steepest ground that is still ground, in radians from flat. Forty
  /// degrees, as in `NavGrid.bakeHeightfield`.
  final double maxSlope;

  /// How far a simplified outline may stray from the voxel edge it replaces,
  /// in cells. Corners of anything built on the lattice deviate by a whole
  /// cell or more, so they survive; the staircase a diagonal edge makes on the
  /// lattice does not.
  final double maxEdgeError;

  /// The most corners a polygon may have after triangles are merged.
  final int maxVerticesPerPolygon;

  /// An island of walkable ground smaller than this, in square metres, is
  /// dropped. Zero keeps everything, which is the default because the top of
  /// a crate is a place to stand and only the game knows whether it matters.
  final double minIslandArea;

  /// [agentHeight] in voxels, rounded up: a ceiling one voxel short of the
  /// agent's head is a ceiling the agent does not fit under.
  int get walkableHeight => _up(agentHeight / cellHeight);

  /// [stepHeight] in voxels, rounded down: a step a hair taller than the
  /// agent climbs is a wall.
  int get walkableClimb => _down(stepHeight / cellHeight);

  /// The clearance in cells an eroded span needs, by `NavGrid`'s own rule —
  /// `NavGrid.clearanceForRadius` — so that the mesh covers exactly the cells
  /// a flow field for a body of [agentRadius] would accept.
  int get erosion => math.max(1, (agentRadius / cellSize + 0.5).ceil());

  /// [minIslandArea] in cells.
  int get minIslandCells => _up(minIslandArea / (cellSize * cellSize));

  static int _up(double voxels) => (voxels - Tolerance.gridBias).ceil();
  static int _down(double voxels) => (voxels + Tolerance.gridBias).floor();

  /// The numbers themselves, in a fixed order, for a digest.
  List<double> get values => <double>[
    cellSize,
    cellHeight,
    agentHeight,
    stepHeight,
    agentRadius,
    maxSlope,
    maxEdgeError,
    maxVerticesPerPolygon.toDouble(),
    minIslandArea,
  ];
}
