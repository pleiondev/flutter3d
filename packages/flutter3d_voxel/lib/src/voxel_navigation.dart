import 'package:flutter3d_sim/flutter3d_sim.dart'
    show Brush, NavLattice, NavMesh, NavMeshConfig;
import 'package:vector_math/vector_math.dart';

import 'voxel_boxes.dart';
import 'voxel_world.dart';

/// The lattice and tiles a voxel world's navigation mesh is baked on: half a
/// metre a cell, so a one-voxel corridor is two cells wide, and four-metre
/// tiles, so an edit bakes again a few tiles round it and not the world.
const NavMeshConfig voxelNavConfig = NavMeshConfig(
  tileSize: 8,
  maxEdgeError: 0.45,
);

/// [box] as a level brush: what the navigation mesh is baked from.
Brush brushOf(VoxelBox box) => Brush(
  centre: Vector3(
    (box.minX + box.maxX) / 2.0,
    (box.minY + box.maxY) / 2.0,
    (box.minZ + box.maxZ) / 2.0,
  ),
  size: Vector3(
    (box.maxX - box.minX).toDouble(),
    (box.maxY - box.minY).toDouble(),
    (box.maxZ - box.minZ).toDouble(),
  ),
  material: 'voxel',
);

/// A navigation mesh over a [VoxelWorld], kept on the blocks as they are
/// edited.
///
/// **Baked from the world's greedy boxes as brushes**, so the bake is the
/// one every level is baked with and its digest means what a level's does.
/// **On the world's whole footprint as a lattice**, fixed at the start: a
/// tiled mesh may only be baked again on the lattice it was baked on, and
/// one taken from the blocks would move the day somebody dug out the
/// world's lowest corner.
///
/// [follow] bakes again only the tiles an edit reaches — the same mesh as
/// baking the edited world whole, digest for digest, which is what the
/// tests hold it to.
final class VoxelNavigation {
  /// Bakes [voxels] whole on [config], which must have tiles.
  VoxelNavigation(this.voxels, {this.config = voxelNavConfig})
    : assert(config.tileSize > 0, 'an untiled mesh cannot follow an edit') {
    for (final chunk in voxels.chunks) {
      _brushes[chunk] = <Brush>[
        for (final box in boxesOf(voxels, chunk)) brushOf(box),
      ];
    }
    _mesh = bakeWhole();
  }

  /// The blocks walked on.
  final VoxelWorld voxels;

  /// What the mesh is baked to.
  final NavMeshConfig config;

  final Map<ChunkKey, List<Brush>> _brushes = <ChunkKey, List<Brush>>{};

  /// The mesh as the world now is.
  NavMesh get mesh => _mesh;
  late NavMesh _mesh;

  /// The lattice every bake of this world is on: its footprint, from the
  /// corner at the origin.
  NavLattice get lattice => NavLattice(
    originX: 0.0,
    originY: 0.0,
    originZ: 0.0,
    columns: (voxels.sizeX / config.cellSize).ceil(),
    rows: (voxels.sizeZ / config.cellSize).ceil(),
  );

  /// The world as brushes, chunk by chunk in [VoxelWorld.chunks]' order.
  List<Brush> get brushes => <Brush>[
    for (final chunk in voxels.chunks) ...?_brushes[chunk],
  ];

  /// The world baked whole, as it now is: the reference [follow] answers to.
  NavMesh bakeWhole() =>
      NavMesh.bake(brushes, config: config, lattice: lattice);

  /// Brings the mesh up to [changes]: the changed chunks' brushes rebuilt,
  /// and the tiles over [VoxelChanges.bounds], widened by the agent's
  /// erosion, baked again.
  void follow(VoxelChanges changes) {
    final bounds = changes.bounds;
    if (bounds == null) return;
    for (final chunk in changes.chunks) {
      _brushes[chunk] = <Brush>[
        for (final box in boxesOf(voxels, chunk)) brushOf(box),
      ];
    }
    _mesh = _mesh.rebake(
      brushes,
      minX: bounds.minX.toDouble(),
      minZ: bounds.minZ.toDouble(),
      maxX: bounds.maxX.toDouble(),
      maxZ: bounds.maxZ.toDouble(),
    );
  }
}
