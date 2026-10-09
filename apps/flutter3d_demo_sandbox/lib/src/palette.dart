import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

/// One kind of block: what it is called, the colour it stands for where
/// there is no picture of it, and the surface each of its faces shows — a
/// name in [surfaces], and a picture in `assets/blocks/`.
typedef BlockKind = ({
  String name,
  Vector4 color,
  String top,
  String side,
  String bottom,
});

/// What a face is drawn with: the colour it falls back to without its
/// picture, how the light takes it, how deep the bumps of its normal map
/// are drawn, whether its picture may be given quarter turns block by
/// block — true of a picture with no up to it, which then stops repeating
/// the same metre across a field of it — and how far its colour wanders
/// across the world.
///
/// **The wander is what a field of one block needs from a distance.** Seen
/// from a hill, a metre's picture is a few pixels and its mip levels average
/// it to one flat colour, so a meadow of grass blocks is a green sheet. With
/// [Surface.mottle] above nought the shade drifts lighter and darker, warmer
/// and cooler, in patches several blocks across, the way a meadow dries in
/// places and a beach is wetter in others: a share of the colour, nought for
/// what people made and lay in rows.
typedef Surface = ({
  Vector4 color,
  double roughness,
  double metallic,
  double bumps,
  bool turns,
  double mottle,
});

/// Bricks, the first of this game's own blocks.
const int brick = Voxels.firstPlaced;

/// Planks.
const int planks = Voxels.firstPlaced + 1;

/// Gold, the one block that shines.
const int gold = Voxels.firstPlaced + 2;

/// Every surface a block's face can show, by name: the name is also the
/// pictures', `assets/blocks/<name>.jpg` and `<name>_normal.jpg`.
///
/// **Grass is three of them.** Its top is turf, its sides earth under a
/// fringe of turf, and its underside plain earth — the dirt block's own, so
/// a chunk draws the two in one.
final Map<String, Surface> surfaces = <String, Surface>{
  'stone': (
    color: Vector4(0.4, 0.39, 0.36, 1.0),
    roughness: 0.9,
    metallic: 0.0,
    // The rock's own map is a cliff's, deep for a metre of it.
    bumps: 0.6,
    turns: true,
    mottle: 0.2,
  ),
  'dirt': (
    color: Vector4(0.46, 0.38, 0.28, 1.0),
    roughness: 1.0,
    metallic: 0.0,
    bumps: 1.0,
    turns: true,
    mottle: 0.2,
  ),
  'grass_top': (
    color: Vector4(0.38, 0.43, 0.19, 1.0),
    roughness: 0.95,
    metallic: 0.0,
    bumps: 1.0,
    turns: true,
    mottle: 0.35,
  ),
  'grass_side': (
    color: Vector4(0.44, 0.38, 0.26, 1.0),
    roughness: 1.0,
    metallic: 0.0,
    bumps: 1.0,
    turns: false,
    mottle: 0.2,
  ),
  'sand': (
    color: Vector4(0.7, 0.64, 0.51, 1.0),
    roughness: 1.0,
    metallic: 0.0,
    bumps: 1.0,
    turns: true,
    mottle: 0.22,
  ),
  'brick': (
    color: Vector4(0.59, 0.46, 0.39, 1.0),
    roughness: 0.85,
    metallic: 0.0,
    bumps: 1.0,
    turns: false,
    mottle: 0.0,
  ),
  'planks': (
    color: Vector4(0.41, 0.31, 0.23, 1.0),
    roughness: 0.75,
    metallic: 0.0,
    bumps: 1.0,
    turns: false,
    mottle: 0.0,
  ),
  // Not wholly metal: with no sky reflected in it, a pure metal is lit by
  // its highlight alone, and gold in shade went the brown of old bronze.
  'gold': (
    color: Vector4(0.91, 0.78, 0.46, 1.0),
    roughness: 0.35,
    metallic: 0.6,
    bumps: 1.0,
    turns: false,
    mottle: 0.0,
  ),
};

/// A block that shows [surface] on every face.
BlockKind _plain(String name, String surface) => (
  name: name,
  color: surfaces[surface]!.color,
  top: surface,
  side: surface,
  bottom: surface,
);

/// Every block this game draws, by its id in the world.
///
/// **The terrain's ids and this game's together**, since the terrain only
/// promises its first few and a game names everything past them.
final Map<int, BlockKind> blockKinds = <int, BlockKind>{
  Voxels.stone: _plain('stone', 'stone'),
  Voxels.dirt: _plain('dirt', 'dirt'),
  Voxels.grass: (
    name: 'grass',
    color: surfaces['grass_top']!.color,
    top: 'grass_top',
    side: 'grass_side',
    bottom: 'dirt',
  ),
  Voxels.sand: _plain('sand', 'sand'),
  brick: _plain('brick', 'brick'),
  planks: _plain('planks', 'planks'),
  gold: _plain('gold', 'gold'),
};

/// The kind a block id draws as: stone for an id this game never named.
BlockKind kindOf(int id) => blockKinds[id] ?? blockKinds[Voxels.stone]!;

/// What the number keys put down, in order.
const List<int> hotbar = <int>[Voxels.stone, planks, brick, gold, Voxels.dirt];
