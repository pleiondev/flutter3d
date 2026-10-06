import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

/// One kind of block: what it is called and what colour it is drawn.
typedef BlockKind = ({String name, Vector4 colour, double roughness});

/// Bricks, the first of this game's own blocks.
const int brick = Voxels.firstPlaced;

/// Planks.
const int planks = Voxels.firstPlaced + 1;

/// Gold, the one block that shines.
const int gold = Voxels.firstPlaced + 2;

/// Every block this game draws, by its id in the world.
///
/// **The terrain's ids and this game's together**, since the terrain only
/// promises its first few and a game names everything past them.
final Map<int, BlockKind> blockKinds = <int, BlockKind>{
  Voxels.stone: (
    name: 'stone',
    colour: Vector4(0.48, 0.49, 0.5, 1.0),
    roughness: 0.9,
  ),
  Voxels.dirt: (
    name: 'dirt',
    colour: Vector4(0.42, 0.29, 0.18, 1.0),
    roughness: 1.0,
  ),
  Voxels.grass: (
    name: 'grass',
    colour: Vector4(0.33, 0.58, 0.22, 1.0),
    roughness: 0.95,
  ),
  Voxels.sand: (
    name: 'sand',
    colour: Vector4(0.86, 0.79, 0.55, 1.0),
    roughness: 1.0,
  ),
  brick: (
    name: 'brick',
    colour: Vector4(0.66, 0.24, 0.18, 1.0),
    roughness: 0.8,
  ),
  planks: (
    name: 'planks',
    colour: Vector4(0.72, 0.53, 0.3, 1.0),
    roughness: 0.7,
  ),
  gold: (name: 'gold', colour: Vector4(0.95, 0.76, 0.25, 1.0), roughness: 0.3),
};

/// What the number keys put down, in order.
const List<int> hotbar = <int>[Voxels.stone, planks, brick, gold, Voxels.dirt];
