import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'voxel_format_exception.dart';
import 'voxel_terrain.dart';

/// Which chunk, counted in chunks from the world's corner.
typedef ChunkKey = ({int x, int y, int z});

/// A box of voxels, from its least corner up to but not including
/// [maxX]/[maxY]/[maxZ] — the corners in metres, since a voxel is a metre.
typedef VoxelBox = ({
  int minX,
  int minY,
  int minZ,
  int maxX,
  int maxY,
  int maxZ,
});

/// What changed since the last [VoxelWorld.drainChanges], for whatever keeps
/// a copy of the world in another shape.
final class VoxelChanges {
  /// Gathers [chunks], [surfaces] and [bounds].
  const VoxelChanges({
    required this.chunks,
    required this.surfaces,
    required this.bounds,
  });

  /// Nothing changed.
  static const VoxelChanges none = VoxelChanges(
    chunks: <ChunkKey>{},
    surfaces: <ChunkKey>{},
    bounds: null,
  );

  /// The chunks one of whose own voxels changed: their boxes, colliders and
  /// brushes are stale.
  final Set<ChunkKey> chunks;

  /// The chunks whose faces may have changed — [chunks], and a neighbour
  /// across whichever border a changed voxel lies on, since a face there is
  /// drawn or culled by what is on the far side.
  final Set<ChunkKey> surfaces;

  /// One box around every voxel that changed, or null when none did: the
  /// region a navigation mesh is baked again over.
  final VoxelBox? bounds;

  /// Whether nothing changed.
  bool get isEmpty => chunks.isEmpty;
}

/// A bounded world of blocks, a byte each, in chunks of [chunkSize] cubed.
///
/// **One metre a voxel, and the world's corner at the origin**: voxel
/// `(x, y, z)` fills `[x, x + 1)` along each axis. Every consumer — the
/// meshes, the boxes, the navigation and the rays — agrees on that, so none
/// of them carries a scale to get wrong.
///
/// **The blocks are the terrain plus the edits.** [terrain] draws the base
/// from a seed, and every [edit] since is kept as a delta against it: [toJson]
/// writes the seed and the delta, never the blocks, and a voxel edited back
/// to what the terrain had drops out of the delta rather than being kept as
/// a change that changes nothing.
///
/// Bounded rather than endless, because a navigation mesh is baked on a
/// lattice that may not grow, and a world that pages chunks in from the
/// distance is a different game from a sandbox a level is played in.
final class VoxelWorld {
  /// A world [chunksX] by [chunksY] by [chunksZ] chunks, filled from
  /// [terrain].
  VoxelWorld({
    required this.chunksX,
    required this.chunksY,
    required this.chunksZ,
    this.terrain = const VoxelTerrain(),
  }) : assert(chunksX > 0 && chunksY > 0 && chunksZ > 0, 'an empty world'),
       _chunks = List<Uint8List?>.filled(chunksX * chunksY * chunksZ, null),
       _heights = terrain.heights(
         chunksX * chunkSize,
         chunksZ * chunkSize,
         maxHeight: chunksY * chunkSize - 1,
       ) {
    _fill();
  }

  /// Reads what [toJson] wrote: the terrain drawn again, the edits on it.
  ///
  /// Throws a [VoxelFormatException] for a document that is not a voxel
  /// world or is newer than [formatVersion]. A world saved before the
  /// envelope (no `format`) reads as version 1, and keys this build does not
  /// know are kept and written back by [toJson].
  factory VoxelWorld.fromJson(Map<String, Object?> json) {
    final opened = format.open(json, refuse: VoxelFormatException.new);
    final size = opened['chunks'];
    final terrain = opened['terrain'];
    if (size is! List ||
        size.length != 3 ||
        size.any((Object? n) => n is! num) ||
        terrain is! Map) {
      throw const VoxelFormatException(
        'not a voxel world: no chunks or terrain',
      );
    }
    final world = VoxelWorld(
      chunksX: (size[0] as num).toInt(),
      chunksY: (size[1] as num).toInt(),
      chunksZ: (size[2] as num).toInt(),
      terrain: VoxelTerrain.fromJson(terrain.cast<String, Object?>()),
    );
    world
      .._unknown = Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final MapEntry(:key, :value) in opened.entries)
          if (!FormatSpec.envelopeKeys.contains(key) && !_known.contains(key))
            key: value,
      })
      ..restoreEdits(opened)
      ..drainChanges();
    return world;
  }

  /// The version of the document [toJson] writes, and the newest
  /// [VoxelWorld.fromJson] reads.
  static const int formatVersion = 1;

  /// A saved voxel world for a `FormatRegistry`: the envelope, the size in
  /// chunks, the terrain's parameters with its generator version, and the
  /// edits. Usually inside a save rather than a file of its own; the suffix
  /// is for a world kept alone.
  static const FormatSpec format = FormatSpec(
    id: 'f3d.voxelWorld',
    version: formatVersion,
    suffixes: <String>['.voxels.json'],
    fixture: 'test/fixtures/v<N>/sandbox.voxels.json',
  );

  static const Set<String> _known = <String>{'chunks', 'terrain', 'edits'};

  /// Keys a later build wrote that this one does not read, written back as
  /// they came.
  Map<String, Object?> _unknown = const <String, Object?>{};

  /// Voxels along each side of a chunk.
  static const int chunkSize = 16;

  static const int _chunkVolume = chunkSize * chunkSize * chunkSize;

  /// The world's size in chunks.
  final int chunksX, chunksY, chunksZ;

  /// What the base is drawn from.
  final VoxelTerrain terrain;

  /// The world's size in voxels along x.
  int get sizeX => chunksX * chunkSize;

  /// The world's size in voxels along y.
  int get sizeY => chunksY * chunkSize;

  /// The world's size in voxels along z.
  int get sizeZ => chunksZ * chunkSize;

  /// Each chunk's voxels, null while the chunk is all air.
  final List<Uint8List?> _chunks;

  /// The terrain's column heights, the base [edit] compares against.
  final Int32List _heights;

  /// Every voxel that differs from the terrain, by [_indexOf], and what it
  /// is now.
  final Map<int, int> _edits = <int, int>{};

  final Set<ChunkKey> _changed = <ChunkKey>{};
  final Set<ChunkKey> _surfaces = <ChunkKey>{};
  VoxelBox? _bounds;

  /// Every chunk, in the order every consumer walks them: x fastest, then z,
  /// then y.
  Iterable<ChunkKey> get chunks sync* {
    for (var y = 0; y < chunksY; y++) {
      for (var z = 0; z < chunksZ; z++) {
        for (var x = 0; x < chunksX; x++) {
          yield (x: x, y: y, z: z);
        }
      }
    }
  }

  /// How many voxels differ from the terrain.
  int get editCount => _edits.length;

  /// Whether `(x, y, z)` is inside the world.
  bool contains(int x, int y, int z) =>
      x >= 0 && y >= 0 && z >= 0 && x < sizeX && y < sizeY && z < sizeZ;

  /// The material at `(x, y, z)`; [Voxels.empty] outside the world.
  int at(int x, int y, int z) {
    if (!contains(x, y, z)) return Voxels.empty;
    final chunk =
        _chunks[_chunkIndex(x ~/ chunkSize, y ~/ chunkSize, z ~/ chunkSize)];
    return chunk == null
        ? Voxels.empty
        : chunk[_local(x % chunkSize, y % chunkSize, z % chunkSize)];
  }

  /// Whether a block stands at `(x, y, z)`.
  bool isSolid(int x, int y, int z) => at(x, y, z) != Voxels.empty;

  /// What the terrain alone has at `(x, y, z)`.
  int baseAt(int x, int y, int z) => contains(x, y, z)
      ? terrain.materialAt(y, _heights[z * sizeX + x])
      : Voxels.empty;

  /// Puts [material] at `(x, y, z)` — [Voxels.empty] removes the block — and
  /// says whether anything changed. Outside the world, nothing does.
  bool edit(int x, int y, int z, int material) {
    if (!contains(x, y, z) || material < 0 || material > 255) return false;
    if (at(x, y, z) == material) return false;
    _put(x, y, z, material);
    final index = _indexOf(x, y, z);
    if (material == baseAt(x, y, z)) {
      _edits.remove(index);
    } else {
      _edits[index] = material;
    }
    _note(x, y, z);
    return true;
  }

  /// The chunks, surfaces and region changed since the last call, and
  /// forgets them.
  VoxelChanges drainChanges() {
    if (_changed.isEmpty) return VoxelChanges.none;
    final changes = VoxelChanges(
      chunks: Set<ChunkKey>.of(_changed),
      surfaces: Set<ChunkKey>.of(_surfaces),
      bounds: _bounds,
    );
    _changed.clear();
    _surfaces.clear();
    _bounds = null;
    return changes;
  }

  /// The world as a save keeps it: its size, the terrain's parameters and
  /// every edit, in the order of their place in the world so two saves of
  /// one world are one document.
  ///
  /// Plain numbers, lists and maps, so it goes into a `Snapshot` as it is.
  Map<String, Object?> toJson() => <String, Object?>{
    ...format.envelope(),
    'chunks': <int>[chunksX, chunksY, chunksZ],
    'terrain': terrain.toJson(),
    'edits': <List<int>>[
      for (final index in _edits.keys.toList()..sort())
        <int>[..._coordinatesOf(index), _edits[index]!],
    ],
    for (final MapEntry(:key, :value) in _unknown.entries) key: value,
  };

  /// Puts the world back to the terrain with [json]'s edits on it, touching
  /// only the voxels that differ — a restore costs what it changes, not
  /// what the world holds.
  ///
  /// Refused when [json] was saved over other terrain or another size: its
  /// edits are deltas against blocks this world does not have.
  void restoreEdits(Map<String, Object?> json) {
    final opened = format.open(json, refuse: VoxelFormatException.new);
    final terrain = opened['terrain'];
    final size = opened['chunks'];
    if (terrain is Map &&
        VoxelTerrain.fromJson(terrain.cast<String, Object?>()) !=
            this.terrain) {
      throw const VoxelFormatException('edits saved over other terrain');
    }
    if (size is List &&
        (size.length != 3 ||
            size[0] != chunksX ||
            size[1] != chunksY ||
            size[2] != chunksZ)) {
      throw const VoxelFormatException(
        'edits saved in a world of another size',
      );
    }
    final wanted = <int, int>{};
    for (final row in (opened['edits'] as List?) ?? const <Object?>[]) {
      if (row is! List || row.length != 4 || row.any((v) => v is! num)) {
        throw VoxelFormatException(
          'an edit that is not [x, y, z, material]: $row',
        );
      }
      final [x, y, z, material] = <int>[
        for (final v in row) (v as num).toInt(),
      ];
      if (!contains(x, y, z)) {
        throw VoxelFormatException('an edit outside the world: $row');
      }
      wanted[_indexOf(x, y, z)] = material;
    }
    for (final index in _edits.keys.toList()) {
      if (wanted.containsKey(index)) continue;
      final [x, y, z] = _coordinatesOf(index);
      edit(x, y, z, baseAt(x, y, z));
    }
    for (final MapEntry(key: index, value: material) in wanted.entries) {
      final [x, y, z] = _coordinatesOf(index);
      edit(x, y, z, material);
    }
  }

  /// One number for every block in the world, for a test or a replay to
  /// compare two worlds by: FNV-1a over each chunk's bytes, air chunks as a
  /// marker of their own — whether the chunk was never filled or was dug
  /// out to nothing, which are the same blocks.
  int get digest {
    var hash = 0x811C9DC5;
    int fold(int hash, int byte) => ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    for (final chunk in _chunks) {
      if (chunk == null || chunk.every((int v) => v == Voxels.empty)) {
        hash = fold(hash, 0xFF);
        continue;
      }
      for (final byte in chunk) {
        hash = fold(hash, byte);
      }
    }
    return hash;
  }

  /// How many solid voxels the world holds.
  int get solidCount => _chunks.fold(
    0,
    (int sum, Uint8List? chunk) =>
        sum + (chunk?.where((int v) => v != Voxels.empty).length ?? 0),
  );

  void _fill() {
    for (var z = 0; z < sizeZ; z++) {
      for (var x = 0; x < sizeX; x++) {
        final height = _heights[z * sizeX + x];
        for (var y = 0; y < height; y++) {
          _put(x, y, z, terrain.materialAt(y, height));
        }
      }
    }
  }

  void _put(int x, int y, int z, int material) {
    final index = _chunkIndex(x ~/ chunkSize, y ~/ chunkSize, z ~/ chunkSize);
    final chunk = _chunks[index] ??= Uint8List(_chunkVolume);
    chunk[_local(x % chunkSize, y % chunkSize, z % chunkSize)] = material;
  }

  /// Marks `(x, y, z)`'s chunk changed, the chunk across any border it lies
  /// on as needing its faces again, and the region grown to cover it.
  void _note(int x, int y, int z) {
    final key = (x: x ~/ chunkSize, y: y ~/ chunkSize, z: z ~/ chunkSize);
    _changed.add(key);
    _surfaces.add(key);
    void across(int dx, int dy, int dz) {
      final next = (x: key.x + dx, y: key.y + dy, z: key.z + dz);
      if (next.x >= 0 &&
          next.y >= 0 &&
          next.z >= 0 &&
          next.x < chunksX &&
          next.y < chunksY &&
          next.z < chunksZ) {
        _surfaces.add(next);
      }
    }

    if (x % chunkSize == 0) across(-1, 0, 0);
    if (x % chunkSize == chunkSize - 1) across(1, 0, 0);
    if (y % chunkSize == 0) across(0, -1, 0);
    if (y % chunkSize == chunkSize - 1) across(0, 1, 0);
    if (z % chunkSize == 0) across(0, 0, -1);
    if (z % chunkSize == chunkSize - 1) across(0, 0, 1);

    final was = _bounds;
    _bounds = was == null
        ? (minX: x, minY: y, minZ: z, maxX: x + 1, maxY: y + 1, maxZ: z + 1)
        : (
            minX: x < was.minX ? x : was.minX,
            minY: y < was.minY ? y : was.minY,
            minZ: z < was.minZ ? z : was.minZ,
            maxX: x + 1 > was.maxX ? x + 1 : was.maxX,
            maxY: y + 1 > was.maxY ? y + 1 : was.maxY,
            maxZ: z + 1 > was.maxZ ? z + 1 : was.maxZ,
          );
  }

  int _chunkIndex(int cx, int cy, int cz) => (cy * chunksZ + cz) * chunksX + cx;

  static int _local(int x, int y, int z) => (y * chunkSize + z) * chunkSize + x;

  int _indexOf(int x, int y, int z) => (y * sizeZ + z) * sizeX + x;

  List<int> _coordinatesOf(int index) => <int>[
    index % sizeX,
    index ~/ (sizeX * sizeZ),
    index ~/ sizeX % sizeZ,
  ];
}
