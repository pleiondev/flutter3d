import 'dart:typed_data';

import 'package:flutter3d_sim/flutter3d_sim.dart' show GameRandom;

import 'voxel_format_exception.dart';

/// The material ids the terrain lays down, and the one that means nothing is
/// there.
///
/// **Numbers rather than an enum**, because a world is a byte per voxel and a
/// game adds its own materials past these: a palette is the game's, and the
/// terrain only needs to agree with it about the first few.
abstract final class Voxels {
  /// No block: air, and what an edit that removes a block writes.
  static const int empty = 0;

  /// Rock, under everything.
  static const int stone = 1;

  /// The layers between the rock and the surface.
  static const int dirt = 2;

  /// The top of a column that stands above [VoxelTerrain.shoreLevel].
  static const int grass = 3;

  /// The top of a column low enough to be a shore.
  static const int sand = 4;

  /// The first id the terrain never lays: a game's own materials start here.
  static const int firstPlaced = 5;
}

/// Rolling ground drawn from a seed: the base every edit is a delta against.
///
/// **A function of the seed and the world's size, and nothing else.** A save
/// keeps these few numbers and the edits, never the blocks: the blocks are
/// drawn again from the seed on the way back in, and two machines given the
/// same seed draw the same ground bit for bit. That is why the heights come
/// from a [GameRandom] stream read in a fixed order and are mixed with nothing
/// but `+`, `-` and `*` — a transcendental is answered by the host's libm
/// natively and by the engine in a browser, and the two disagree.
final class VoxelTerrain {
  /// Ground around [groundLevel], rising and falling by up to [amplitude]
  /// over hills [scale] voxels across.
  const VoxelTerrain({
    this.seed = 1,
    this.groundLevel = 8,
    this.amplitude = 5,
    this.scale = 16,
  }) : assert(scale >= 2, 'hills narrower than two voxels are noise');

  /// Level ground [height] voxels deep, for a test or a building plot.
  const VoxelTerrain.flat(int height)
    : seed = 0,
      groundLevel = height,
      amplitude = 0,
      scale = 16;

  /// Reads what [toJson] wrote.
  ///
  /// Throws a [VoxelFormatException] for a missing number, and for terrain
  /// drawn by a newer [generatorVersion]: the seed alone does not say what
  /// ground a later drawing made, so its edits would land on other blocks.
  /// Terrain saved before the number existed reads as version 1.
  factory VoxelTerrain.fromJson(Map<String, Object?> json) {
    int read(String key) => switch (json[key]) {
      final num value => value.toInt(),
      _ => throw VoxelFormatException('a terrain with no "$key"'),
    };
    final drawnBy = switch (json['generatorVersion']) {
      null => 1,
      final num value => value.toInt(),
      final other => throw VoxelFormatException(
        'a terrain whose "generatorVersion" is $other, not a number',
      ),
    };
    if (drawnBy > generatorVersion) {
      throw VoxelFormatException(
        'terrain drawn by generator version $drawnBy, and this build draws '
        'version $generatorVersion: update flutter3d_voxel to open it',
      );
    }
    return VoxelTerrain(
      seed: read('seed'),
      groundLevel: read('groundLevel'),
      amplitude: read('amplitude'),
      scale: read('scale'),
    );
  }

  /// The version of the drawing [heights] does, saved beside the seed.
  ///
  /// **The seed is half of what a save keeps; this is the other half.** Two
  /// machines draw the same ground from one seed only while they run the
  /// same drawing, and a save keeps the edits as deltas against that ground.
  /// A change to [heights], [materialAt] or the lattice that moves a single
  /// block is a new version, and the old drawing stays reachable for the
  /// saves that name it.
  static const int generatorVersion = 1;

  /// What the heights are drawn from.
  final int seed;

  /// The height, in voxels, the ground rolls about.
  final int groundLevel;

  /// How far above and below [groundLevel] a hill reaches.
  final int amplitude;

  /// How many voxels apart the broad hills are; a second, finer octave is
  /// half that.
  final int scale;

  /// The highest a column may top out and still be sand rather than grass.
  int get shoreLevel => groundLevel - 2;

  /// The parameters, for a save — the blocks are drawn again from them.
  Map<String, Object?> toJson() => <String, Object?>{
    'generatorVersion': generatorVersion,
    'seed': seed,
    'groundLevel': groundLevel,
    'amplitude': amplitude,
    'scale': scale,
  };

  /// How many solid voxels stand in every column of a world [sizeX] by
  /// [sizeZ], at most [maxHeight], in rows of x.
  ///
  /// Value noise: a lattice of random heights, read from one [GameRandom] in
  /// row order, blended between lattice points by a smoothstep — a
  /// polynomial — in two octaves.
  Int32List heights(int sizeX, int sizeZ, {required int maxHeight}) {
    final dice = GameRandom(seed);
    final broad = _Lattice(dice, sizeX, sizeZ, scale);
    final fine = _Lattice(dice, sizeX, sizeZ, scale ~/ 2);
    final out = Int32List(sizeX * sizeZ);
    for (var z = 0; z < sizeZ; z++) {
      for (var x = 0; x < sizeX; x++) {
        final noise = broad.at(x, z) * 0.7 + fine.at(x, z) * 0.3;
        final height = groundLevel + (noise * 2.0 - 1.0) * amplitude;
        out[z * sizeX + x] = height.floor().clamp(0, maxHeight);
      }
    }
    return out;
  }

  /// The material at height [y] of a column [height] voxels tall.
  int materialAt(int y, int height) {
    if (y >= height) return Voxels.empty;
    if (y == height - 1) {
      return height - 1 <= shoreLevel ? Voxels.sand : Voxels.grass;
    }
    if (y >= height - 3) return Voxels.dirt;
    return Voxels.stone;
  }

  @override
  bool operator ==(Object other) =>
      other is VoxelTerrain &&
      other.seed == seed &&
      other.groundLevel == groundLevel &&
      other.amplitude == amplitude &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(seed, groundLevel, amplitude, scale);
}

/// Random values at every [spacing]-th voxel, and the smooth blend between.
final class _Lattice {
  _Lattice(GameRandom dice, int sizeX, int sizeZ, this.spacing)
    : across = sizeX ~/ spacing + 2,
      values = Float64List((sizeX ~/ spacing + 2) * (sizeZ ~/ spacing + 2)) {
    for (var i = 0; i < values.length; i++) {
      values[i] = dice.nextDouble();
    }
  }

  final int spacing;
  final int across;
  final Float64List values;

  double at(int x, int z) {
    final ix = x ~/ spacing;
    final iz = z ~/ spacing;
    final fx = _smooth((x - ix * spacing) / spacing);
    final fz = _smooth((z - iz * spacing) / spacing);
    double v(int i, int k) => values[(iz + k) * across + ix + i];
    final near = v(0, 0) + (v(1, 0) - v(0, 0)) * fx;
    final far = v(0, 1) + (v(1, 1) - v(0, 1)) * fx;
    return near + (far - near) * fz;
  }

  static double _smooth(double t) => t * t * (3.0 - 2.0 * t);
}
