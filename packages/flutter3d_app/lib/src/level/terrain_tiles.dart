/// A heightfield drawn as tiles whose level of detail follows the camera —
/// `gfx-87n`.
///
/// **The scene half of `heightfield_tiles.dart`.** That file knows which
/// samples a tile keeps at each level and how deep a skirt has to hang; this
/// one owns a [MeshNode] per tile and, once a frame, points it at the mesh for
/// the level its distance calls for. Here because this is the package that
/// sees both the simulation's heights and the engine's meshes — the same reason
/// `meshDataOf` is here.
///
/// **A level's mesh is uploaded the first time a tile needs it and kept.** A
/// camera sweeping back and forth across a threshold would otherwise upload
/// the same four meshes over and over; kept, a change of level is a pointer
/// moved, which is what makes it cheap enough to do per frame.
///
/// **One material for the whole field.** How ground looks — height bands, a
/// cover map, a slope — belongs in its material, and since `gfx-84n` a material
/// can say that in source: `world` for the height, `sample` for a cover
/// texture, compiled for every backend. A shader written for one scene's
/// terrain is what this is here to make unnecessary.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'surface_mesh.dart';

/// Every tile of [tiles] as a node, and the levels they draw at.
final class TerrainTiles {
  /// Builds one node per tile, each at the coarsest level until [update] is
  /// first called — a field added to a scene and drawn before anything asked
  /// where the camera is should cost the least it can.
  TerrainTiles({
    required this.device,
    required this.tiles,
    required this.material,
    required this.chooser,
    this.metresPerTexture = 8.0,
    this.skirts = true,
  }) {
    for (var z = 0; z < tiles.tilesZ; z++) {
      for (var x = 0; x < tiles.tilesX; x++) {
        final coarsest = tiles.levels - 1;
        _levels.add(null);
        _bounds.add(tiles.bounds(x, z));
        nodes.add(
          MeshNode(_mesh(x, z, coarsest), material, name: 'terrain $x,$z'),
        );
      }
    }
  }

  final GraphicsDevice device;
  final HeightfieldTiles tiles;
  final Material material;
  final TileLevelChooser chooser;
  final double metresPerTexture;

  /// Off only for a field drawn at one level everywhere — see
  /// `HeightfieldTiles.build`.
  final bool skirts;

  /// One per tile, row by row along X. Add them to a scene.
  final List<MeshNode> nodes = <MeshNode>[];

  final List<int?> _levels = <int?>[];
  final List<Aabb3> _bounds = <Aabb3>[];
  final Map<(int, int, int), DeviceMesh> _uploaded =
      <(int, int, int), DeviceMesh>{};

  /// How many tile meshes have been uploaded so far — a level is uploaded once
  /// per tile, however often the tile returns to it.
  int get uploads => _uploaded.length;

  /// The level tile [x], [z] draws at, or null before the first [update].
  int? levelOf(int x, int z) => _levels[z * tiles.tilesX + x];

  /// Points every tile at the level its distance from [eye] calls for.
  ///
  /// The distance is to the tile's box — its highest and lowest ground
  /// included — rather than to its centre: a camera standing on the edge of a
  /// big tile is centimetres from it, and a centre distance would draw the
  /// ground under its feet as if it were half a tile away.
  void update(Vector3 eye) {
    for (var z = 0; z < tiles.tilesZ; z++) {
      for (var x = 0; x < tiles.tilesX; x++) {
        final index = z * tiles.tilesX + x;
        final level = chooser.choose(
          _distanceTo(_bounds[index], eye),
          _levels[index],
        );
        if (level != _levels[index]) {
          _levels[index] = level;
          nodes[index].mesh = _mesh(x, z, level);
        }
      }
    }
  }

  DeviceMesh _mesh(int x, int z, int level) =>
      _uploaded.putIfAbsent((x, z, level), () {
        final surface = tiles.build(
          x,
          z,
          level: level,
          material: material.name ?? 'terrain',
          metresPerTexture: metresPerTexture,
          skirts: skirts,
        );
        return DeviceMesh.upload(device, meshDataOf(surface));
      });

  static double _distanceTo(Aabb3 box, Vector3 eye) {
    final closest = Vector3(
      eye.x.clamp(box.min.x, box.max.x),
      eye.y.clamp(box.min.y, box.max.y),
      eye.z.clamp(box.min.z, box.max.z),
    );
    return closest.distanceTo(eye);
  }
}
