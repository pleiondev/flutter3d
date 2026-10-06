import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';

import 'palette.dart';

/// A [VoxelWorld]'s chunks in a [Scene]: a node per chunk per material,
/// drawn again chunk by chunk as the blocks change.
///
/// The world never sees the device or the scene; this is where the two
/// meet, and the only place a chunk's `MeshData` is uploaded or let go.
final class ChunkMeshes {
  /// Draws every chunk of [blocks] into [scene] through [device].
  ChunkMeshes(this.device, this.scene, this.blocks) {
    refresh(blocks.chunks);
  }

  /// What the meshes are uploaded to.
  final GraphicsDevice device;

  /// Where their nodes are.
  final Scene scene;

  /// What they draw.
  final VoxelWorld blocks;

  /// One material a block kind, shared by every chunk's node of that kind.
  late final Map<int, Material> _materials = <int, Material>{
    for (final MapEntry(key: id, value: kind) in blockKinds.entries)
      id: Material(
        name: kind.name,
        baseColor: kind.colour,
        roughness: kind.roughness,
        metallic: id == gold ? 1.0 : 0.0,
      ),
  };

  final Map<ChunkKey, List<MeshNode>> _nodes = <ChunkKey, List<MeshNode>>{};

  /// How many nodes draw the world: for a test, and a debug line.
  int get nodeCount => _nodes.values.fold(
    0,
    (int sum, List<MeshNode> nodes) => sum + nodes.length,
  );

  /// [chunk]'s nodes, one a material it shows.
  List<MeshNode> nodesOf(ChunkKey chunk) =>
      List<MeshNode>.unmodifiable(_nodes[chunk] ?? const <MeshNode>[]);

  /// Draws [chunks] again from the blocks as they are, letting go of the
  /// meshes they were drawn with.
  void refresh(Iterable<ChunkKey> chunks) {
    for (final chunk in chunks) {
      for (final node in _nodes.remove(chunk) ?? const <MeshNode>[]) {
        scene.remove(node);
        final mesh = node.mesh;
        if (mesh is DeviceMesh) {
          device
            ..releaseGeometry(mesh.vertices)
            ..releaseGeometry(mesh.indices);
        }
      }
      final meshes = meshChunk(blocks, chunk);
      if (meshes.isEmpty) continue;
      _nodes[chunk] = <MeshNode>[
        for (final MapEntry(key: id, value: data) in meshes.entries)
          MeshNode(
            DeviceMesh.upload(device, data, keepSourceData: false),
            _materials[id] ?? _materials[Voxels.stone]!,
            name:
                'chunk ${chunk.x},${chunk.y},${chunk.z} ${blockKinds[id]?.name ?? id}',
          ),
      ];
      _nodes[chunk]!.forEach(scene.add);
    }
  }
}
