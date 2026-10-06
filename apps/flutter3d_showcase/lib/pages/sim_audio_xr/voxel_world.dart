/// A world of blocks drawn from a seed, dug into and built on while the page
/// runs: each edit meshes its chunk again, replaces that chunk's collision
/// boxes, and is kept as a delta against the terrain, which is all a save
/// holds.
///
/// Quoted by `voxel_world.md` and shown whole in the Source tab.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:flutter3d_showcase/src/demo/run_physics.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

final class VoxelWorldDemo extends ShowcaseDemo {
  bool digging = true;

  late final GraphicsDevice _device;
  late final Scene _scene;
  late final VoxelWorld _voxels;
  late final CollisionWorld _world;
  late final VoxelCollision _collision;
  late final Map<String, Object?> _save;
  final Map<ChunkKey, List<MeshNode>> _nodes = <ChunkKey, List<MeshNode>>{};

  /// The edits the page makes one at a time: a pit dug in the middle, then a
  /// tower of a material the terrain never lays.
  late final List<(int, int, int, int)> _plan;
  int _next = 0;
  double _clock = 0.0;

  static const double _tick = 0.15;

  @override
  void configureView(DemoContext context) {
    context.orbit
      ..distance = 44.0
      ..pitch = 0.75
      ..yaw = 0.6;
    context.orbit.target.setValues(16.0, 6.0, 16.0);
  }

  @override
  Scene build(DemoContext context) {
    _device = context.device;
    // #region world
    // Two chunks by one by two: 32 by 16 by 32 voxels of rolling ground,
    // drawn from seed 7 and nothing else.
    _voxels = VoxelWorld(
      chunksX: 2,
      chunksY: 1,
      chunksZ: 2,
      terrain: const VoxelTerrain(seed: 7),
    );
    // Taken before any edit: the terrain's few numbers and no edits at all.
    _save = _voxels.toJson();
    // #endregion world

    // #region collision
    // The chunks as boxes in an ordinary collision world, on the run's
    // physics.
    _world = onRunPhysics(CollisionWorld());
    _collision = VoxelCollision(_voxels, _world);
    _world.update();
    // #endregion collision

    _plan = <(int, int, int, int)>[
      for (var depth = 0; depth < 4; depth++)
        for (var x = 14; x <= 18; x++)
          for (var z = 14; z <= 18; z++)
            (x, _top(x, z) - 1 - depth, z, Voxels.empty),
      for (var y = 0; y < 6; y++) (8, _top(8, 8) + y, 8, Voxels.firstPlaced),
    ];

    _scene = Scene()
      ..ambientColor = Vector3(0.55, 0.62, 0.75)
      ..ambientIntensity = 0.35
      ..add(
        LightNode(name: 'sun', intensity: 2.6)
          ..setLocalForward(Vector3(-0.4, -1.0, -0.25)),
      );
    for (final ChunkKey chunk in _voxels.chunks) {
      _mesh(chunk);
    }
    return _scene;
  }

  /// The height of the first air above the column at [x], [z].
  int _top(int x, int z) {
    var y = 0;
    while (_voxels.isSolid(x, y, z)) {
      y++;
    }
    return y;
  }

  static Vector4 _colourOf(int material) => switch (material) {
    Voxels.stone => Vector4(0.5, 0.5, 0.52, 1.0),
    Voxels.dirt => Vector4(0.45, 0.32, 0.2, 1.0),
    Voxels.grass => Vector4(0.35, 0.62, 0.28, 1.0),
    Voxels.sand => Vector4(0.86, 0.78, 0.55, 1.0),
    _ => Vector4(0.8, 0.36, 0.22, 1.0),
  };

  // #region mesh
  /// [chunk]'s faces, a greedy mesh per material, in place of what it had.
  void _mesh(ChunkKey chunk) {
    for (final MeshNode old in _nodes.remove(chunk) ?? const <MeshNode>[]) {
      _scene.remove(old);
    }
    final List<MeshNode> nodes = <MeshNode>[
      for (final MapEntry(key: material, value: data) in meshChunk(
        _voxels,
        chunk,
      ).entries)
        MeshNode(
          DeviceMesh.upload(_device, data),
          Material(
            name: 'voxel $material',
            baseColor: _colourOf(material),
            roughness: 0.9,
          ),
          name: 'chunk ${chunk.x} ${chunk.z} material $material',
        ),
    ];
    nodes.forEach(_scene.add);
    _nodes[chunk] = nodes;
  }
  // #endregion mesh

  // #region edit
  /// What an edit costs: the chunks whose faces it touched are meshed again,
  /// and the chunks it changed get new boxes.
  void _apply() {
    final VoxelChanges changes = _voxels.takeChanges();
    if (changes.isEmpty) return;
    changes.surfaces.forEach(_mesh);
    _collision.refresh(changes.chunks);
    _world.update();
  }
  // #endregion edit

  @override
  void update(DemoContext context, double dt) {
    if (!digging) return;
    _clock += dt;
    if (_clock < _tick) return;
    _clock = 0.0;
    if (_next < _plan.length) {
      final (int x, int y, int z, int material) = _plan[_next++];
      _voxels.edit(x, y, z, material);
    } else {
      _restore();
    }
    _apply();
  }

  // #region restore
  /// Back to the save taken at the start: only the voxels that differ from
  /// it are touched.
  void _restore() {
    _voxels.restoreEdits(_save);
    _next = 0;
  }
  // #endregion restore

  @override
  List<DemoControl> controls(DemoContext context) => <DemoControl>[
    ToggleControl(
      'Dig and build',
      value: () => digging,
      onChanged: (bool v) => digging = v,
    ),
    ToggleControl(
      'Put back the save',
      value: () => false,
      onChanged: (bool v) {
        if (!v) return;
        _restore();
        _apply();
      },
    ),
  ];

  /// How high the collision boxes stand under [x], [z], by a ray straight
  /// down.
  double _groundAt(int x, int z) {
    final RayHit hit = RayHit();
    _world.raycast(
      Vector3(x + 0.5, 40.0, z + 0.5),
      Vector3(0.0, -1.0, 0.0),
      60.0,
      hit,
    );
    if (!hit.hit) throw StateError('no ground under $x, $z');
    return hit.point.y;
  }

  int _triangles(ChunkKey chunk) => meshChunk(
    _voxels,
    chunk,
  ).values.fold(0, (int sum, MeshData data) => sum + data.indices.length ~/ 3);

  @override
  void verify(Scene scene, FrameResult frame) {
    if (frame.drawCalls < 1) {
      throw StateError('no chunk of the world reached the frame');
    }
    // #region check
    // A column well away from the pit: dig its top block out.
    const int x = 4, z = 26;
    const ChunkKey chunk = (x: 0, y: 0, z: 1);
    final int top = _top(x, z);
    final int edits = _voxels.editCount;
    final int before = _triangles(chunk);
    if ((_groundAt(x, z) - top).abs() > 1e-3) {
      throw StateError('the boxes should stand as high as the blocks');
    }
    _voxels.edit(x, top - 1, z, Voxels.empty);
    _apply();
    if ((_groundAt(x, z) - (top - 1)).abs() > 1e-3) {
      throw StateError('the dug block should be gone from the collision too');
    }
    if (_triangles(chunk) == before) {
      throw StateError('the dug block should change the chunk\'s mesh');
    }
    // Put back what the terrain had, and it is no edit at all.
    _voxels.edit(x, top - 1, z, _voxels.baseAt(x, top - 1, z));
    _apply();
    if (_voxels.editCount != edits) {
      throw StateError('a block edited back to the terrain is still an edit');
    }

    // A save is the terrain and the edits; read back, it is the same world.
    _voxels.edit(x, top, z, Voxels.firstPlaced);
    final VoxelWorld copy = VoxelWorld.fromJson(_voxels.toJson());
    if (copy.digest != _voxels.digest) {
      throw StateError('the world read back from its save is another world');
    }
    _restore();
    _apply();
    if (_voxels.editCount != 0 ||
        _voxels.digest !=
            VoxelWorld(
              chunksX: 2,
              chunksY: 1,
              chunksZ: 2,
              terrain: const VoxelTerrain(seed: 7),
            ).digest) {
      throw StateError('restoring the first save should leave the terrain');
    }
    // #endregion check
  }
}
