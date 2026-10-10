import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';

import 'block_surfaces.dart';
import 'palette.dart';

/// A [VoxelWorld]'s chunks in a [Scene]: a node per chunk per surface,
/// drawn again chunk by chunk as the blocks change.
///
/// The world never sees the device or the scene; this is where the two
/// meet, and the only place a chunk's `MeshData` is uploaded or let go.
final class ChunkMeshes {
  /// Draws every chunk of [blocks] into [scene] through [device], with
  /// [surfaces]' materials — flat colours when none are given.
  ChunkMeshes(this.device, this.scene, this.blocks, {BlockSurfaces? surfaces})
    : surfaces = surfaces ?? BlockSurfaces.flat() {
    refresh(blocks.chunks);
  }

  /// What the meshes are uploaded to.
  final GraphicsDevice device;

  /// Where their nodes are.
  final Scene scene;

  /// What they draw.
  final VoxelWorld blocks;

  /// What each face is drawn with.
  final BlockSurfaces surfaces;

  final Map<ChunkKey, List<MeshNode>> _nodes = <ChunkKey, List<MeshNode>>{};

  /// How many nodes draw the world: for a test, and a debug line.
  int get nodeCount => _nodes.values.fold(
    0,
    (int sum, List<MeshNode> nodes) => sum + nodes.length,
  );

  /// [chunk]'s nodes, one a surface it shows.
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
      final meshes = shadeChunk(blocks, chunk);
      if (meshes.isEmpty) continue;
      _nodes[chunk] = <MeshNode>[
        for (final MapEntry(key: name, value: data) in meshes.entries)
          MeshNode(
            DeviceMesh.upload(device, data, keepSourceData: false),
            surfaces.of(name),
            name: 'chunk ${chunk.x},${chunk.y},${chunk.z} $name',
          ),
      ];
      _nodes[chunk]!.forEach(scene.add);
    }
  }
}

/// How light a face's corner is, by how many of the three blocks round it
/// in front of the face are solid: none, one, two — or both sides, which
/// close the corner whatever the third is.
const List<double> _cornerShade = <double>[1.0, 0.74, 0.56, 0.42];

/// [chunk]'s visible faces, a mesh a surface they show, each face a block's
/// picture once and its corners darkened where it meets other blocks.
///
/// **Which faces are seen is the voxel package's to say**: `meshChunk`
/// with merging off gives every one as its own quad, and this reads where
/// each is and which way it looks from that, then lays it down again with
/// its picture the right way up ([FaceMesh]) and its corners shaded. The
/// merged mesh would be fewer triangles, but a quad spanning many blocks
/// has corners only at its ends, and there is nowhere in it to put the
/// shade of a corner halfway along.
Map<String, MeshData> shadeChunk(VoxelWorld blocks, ChunkKey chunk) {
  final faces = <String, FaceMesh>{};
  final stride = VertexLayout.standard.floatsPerVertex;
  for (final MapEntry(key: id, value: data) in meshChunk(
    blocks,
    chunk,
    merge: false,
  ).entries) {
    final kind = kindOf(id);
    final v = data.vertices;
    for (var q = 0; q < v.length ~/ (stride * 4); q++) {
      final first = q * stride * 4;
      // The normal, and the middle of the quad from two opposite corners.
      final facing = (
        x: v[first + 3].round(),
        y: v[first + 4].round(),
        z: v[first + 5].round(),
      );
      final (cx, cy, cz) = (
        (v[first] + v[first + stride * 2]) / 2,
        (v[first + 1] + v[first + stride * 2 + 1]) / 2,
        (v[first + 2] + v[first + stride * 2 + 2]) / 2,
      );
      // The block the face is of, half a block behind its middle.
      final (bx, by, bz) = (
        (cx - facing.x * 0.5).floor(),
        (cy - facing.y * 0.5).floor(),
        (cz - facing.z * 0.5).floor(),
      );
      final surface = surfaceOf(kind, facing);
      final look = surfaces[surface];
      final turns = (look?.turns ?? false) ? turnsAt(bx, by, bz, facing) : 0;
      final mottle = look?.mottle ?? 0.0;
      faces
          .putIfAbsent(surface, FaceMesh.new)
          .face(
            bx + 0.5,
            by + 0.5,
            bz + 0.5,
            facing,
            turns: turns,
            shade: _shade(blocks, bx, by, bz, facing, turns),
            tint: mottle > 0.0 ? (corner) => _mottle(corner, mottle) : null,
          );
    }
  }
  return <String, MeshData>{
    for (final name in faces.keys.toList()..sort()) name: faces[name]!.build(),
  };
}

/// The tint at [corner] of a surface whose colour wanders by [amount]
/// (`Surface.mottle`): lighter or darker by up to that share, and warmer or
/// cooler by half of it, each drifting over patches some seven blocks
/// across.
///
/// Read at the corners rather than once a block, so the drift runs smoothly
/// across the faces it crosses instead of stepping from block to block, and
/// two faces meeting at a corner agree on it.
Vector3 _mottle(Vector3 corner, double amount) {
  final light = _drift(corner, 0) * 2.0 - 1.0;
  final warm = _drift(corner, 1) * 2.0 - 1.0;
  final b = 1.0 + amount * light, w = amount * 0.5 * warm;
  return Vector3(b * (1.0 + w), b, b * (1.0 - w));
}

/// Smooth value noise in nought to one at [p], over a lattice seven blocks
/// apart with a second, finer one at a third of the weight; [seed] gives an
/// unrelated field from the same lattice.
double _drift(Vector3 p, int seed) =>
    (_lattice(p / 7.0, seed) * 2.0 + _lattice(p / 2.5, seed + 7)) / 3.0;

double _lattice(Vector3 p, int seed) {
  final (fx, fy, fz) = (p.x.floor(), p.y.floor(), p.z.floor());
  double ease(double t) => t * t * (3.0 - 2.0 * t);
  final (tx, ty, tz) = (ease(p.x - fx), ease(p.y - fy), ease(p.z - fz));
  double at(int x, int y, int z) {
    final h =
        ((x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761))
            .toUnsigned(32);
    final m = (h ^ (h >> 15)) * 0x2c1b3c6d;
    return ((m ^ (m >> 12)).toUnsigned(32) & 0xffff) / 0xffff;
  }

  double lerp(double a, double b, double t) => a + (b - a) * t;
  double plane(int y) => lerp(
    lerp(at(fx, y, fz), at(fx + 1, y, fz), tx),
    lerp(at(fx, y, fz + 1), at(fx + 1, y, fz + 1), tx),
    tz,
  );
  return lerp(plane(fy), plane(fy + 1), ty);
}

/// The shade at each corner of the face of block ([x], [y], [z]) looking
/// along [facing], its picture given [turns] quarter turns, in the order
/// [FaceMesh.face] takes them.
///
/// A corner is read from the layer of blocks the face looks into: the two
/// beside the air in front of it that share the corner's edges, and the one
/// across its diagonal.
List<double> _shade(
  VoxelWorld blocks,
  int x,
  int y,
  int z,
  Facing facing,
  int turns,
) {
  final (right, down) = pictureAxes(facing, turns: turns);
  // The block [across] pictures right and [along] pictures down from the
  // air in front of the face.
  bool solid(double across, double along) {
    final step = right * across + down * along;
    return blocks.isSolid(
      x + facing.x + step.x.round(),
      y + facing.y + step.y.round(),
      z + facing.z + step.z.round(),
    );
  }

  double corner(double u, double v) {
    final (beside, below) = (solid(u, 0.0), solid(0.0, v));
    final closed = beside && below
        ? 3
        : <bool>[beside, below, solid(u, v)].where((bool s) => s).length;
    return _cornerShade[closed];
  }

  return <double>[
    corner(-1.0, -1.0),
    corner(-1.0, 1.0),
    corner(1.0, 1.0),
    corner(1.0, -1.0),
  ];
}
