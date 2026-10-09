/// Water, fire and falling blocks over the sandbox's world, on the physics
/// core: water poured on a column runs over the tops of the blocks and
/// pools where they hollow; planks set alight burn, light the planks beside
/// them and are gone when burnt through, and water puts them out; a block
/// left with nothing under it or beside it falls as a body and, come to
/// rest, is a block again where it lies.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_elements/flutter3d_elements.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show BodyPose;
import 'package:flutter3d_voxel/flutter3d_voxel.dart';

import 'block_surfaces.dart';
import 'palette.dart';

/// A block falling, and what it is.
final class _Falling {
  _Falling(this.body, this.material);

  final TrackedBody body;
  final int material;
  double still = 0.0;
}

/// The elements over [blocks]: [elements] holds the water, the fires and
/// the falling blocks, and this keeps them to the blocks.
final class BlockElements {
  BlockElements({
    required this.blocks,
    required this.elements,
    required this._device,
    required this.setBlock,
    BlockSurfaces? surfaces,
  }) : _surfaces = surfaces ?? BlockSurfaces.flat() {
    _ground = <double>[
      for (var z = 0; z < blocks.sizeZ; z++)
        for (var x = 0; x < blocks.sizeX; x++) _top(x, z),
    ];
    pool = elements.addWater(
      ground: ElementHeightfield.list(
        origin: Vector3.zero(),
        cell: 1.0,
        nx: blocks.sizeX,
        nz: blocks.sizeZ,
        heights: _ground,
      ),
      liquid: Liquid.water(),
      // A bed of blocks: as rough as a straight earth channel.
      bed: const Bed(roughness: Bed.earthChannel),
    );
    // What reaches the edge of the world runs off it.
    for (final side in <GridSide>[
      GridSide.west,
      GridSide.east,
      GridSide.south,
      GridSide.north,
    ]) {
      pool.setEdge(side, NativeEdgeFlow.free);
    }
  }

  final VoxelWorld blocks;

  /// The water, the fires and the falling blocks.
  final Elements elements;

  /// A block of planks, kg/m³ — boards stacked with air between them, a cubic
  /// metre of which weighs little more than a tenth of solid pine — and the
  /// share of its fuel it holds together with: past it, it falls apart.
  static const double _plankDensity = 60.0, _holds = 0.4;

  /// A block of stone or earth, kg/m³.
  static const double _blockDensity = 2000.0;

  /// A torch held to planks: about fifty kilowatts a square metre over a
  /// hand's width from a flame at 1300 K, held for ten seconds.
  static const Igniter _torch = Igniter(
    flux: 5e4,
    area: 0.01,
    temperature: 1300.0,
    seconds: 10.0,
  );

  /// Puts [material] at a block, as an edit of the world: what burns out
  /// and what falls changes the world through this.
  final bool Function(int x, int y, int z, int material) setBlock;

  NativeWorld get world => elements.world;
  late final WaterBody pool;
  final GraphicsDevice _device;
  final BlockSurfaces _surfaces;
  late final List<double> _ground;

  /// A whole block of each kind that has fallen, uploaded the first time
  /// one does and kept for the next: a mesh and its material a surface.
  final Map<int, List<(DeviceMesh, RenderMaterial)>> _blocks =
      <int, List<(DeviceMesh, RenderMaterial)>>{};

  /// The planks that have a body to burn in, by their block, and the blocks
  /// falling.
  final Map<(int, int, int), TrackedBody> _wood =
      <(int, int, int), TrackedBody>{};
  final List<_Falling> _falling = <_Falling>[];

  /// Solid blocks standing in for the world round a falling one, so it has
  /// something to land on: built where one falls, by block.
  final Map<(int, int, int), TrackedBody> _solid =
      <(int, int, int), TrackedBody>{};

  /// Whether any planks are burning now.
  bool get burning => _wood.values.any((w) => world.isBurning(w.native));

  /// The top of the column at (x, z): how high its highest block reaches.
  double _top(int x, int z) {
    for (var y = blocks.sizeY - 1; y >= 0; y--) {
      if (blocks.isSolid(x, y, z)) return y + 1.0;
    }
    return 0.0;
  }

  /// A bucket of water — half a cubic metre — tipped onto column (x, z).
  void pour(int x, int z) =>
      pool.pour(Vector3(x + 0.5, 0.0, z + 0.5), volume: 0.5, radius: 0.5);

  /// A torch held to block (x, y, z): it catches if it is planks, in the
  /// time the wood takes to reach its ignition temperature.
  bool ignite(int x, int y, int z) {
    if (blocks.at(x, y, z) != planks) return false;
    elements.fires.ignite(
      _woodAt(x, y, z),
      by: _torch,
      at: Vector3(x + 0.5, y + 1.0, z + 0.5),
    );
    return true;
  }

  TrackedBody _woodAt(int x, int y, int z) => _wood.putIfAbsent(
    (x, y, z),
    () => elements.addBody(
      Solid.box(
        Vector3.all(0.5),
        material: NativeMaterial.wood(),
        density: _plankDensity,
      ),
      at: Vector3(x + 0.5, y + 0.5, z + 0.5),
      type: NativeBodyType.fixed,
    ),
  );

  /// The world changed at block (x, y, z): the water's floor follows it,
  /// and what it held up may fall.
  void changed(int x, int y, int z) {
    final top = _top(x, z);
    final i = x + z * blocks.sizeX;
    if (_ground[i] != top) {
      _ground[i] = top;
      pool.setGround(_ground);
    }
    final wood = _wood.remove((x, y, z));
    if (wood != null) elements.remove(wood);
    final solid = _solid.remove((x, y, z));
    if (solid != null) elements.remove(solid);
    if (!blocks.isSolid(x, y, z)) _unsupported(x, y + 1, z);
  }

  /// The block at (x, y, z), and the column over it, falls if nothing holds
  /// it: no block under it and none beside it.
  void _unsupported(int x, int y, int z) {
    if (!blocks.contains(x, y, z) || !blocks.isSolid(x, y, z)) return;
    if (blocks.isSolid(x, y - 1, z)) return;
    for (final (dx, dz) in <(int, int)>[(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      if (blocks.isSolid(x + dx, y, z + dz)) return;
    }
    final material = blocks.at(x, y, z);
    final look = _fallingLook(material);
    final body = elements.addBody(
      Solid.box(
        Vector3.all(0.49),
        material: material == planks
            ? NativeMaterial.wood()
            : NativeMaterial.stone(),
        density: material == planks ? _plankDensity : _blockDensity,
      ),
      at: Vector3(x + 0.5, y + 0.5, z + 0.5),
      look: look,
    );
    elements.fireView.scene.add(look);
    _falling.add(_Falling(body, material));
    // Out of the world as a block, which tells what stood on it in turn.
    setBlock(x, y, z, Voxels.empty);
    _ground3x3(x, z);
  }

  /// The blocks round column (x, z) as bodies, for what falls there to
  /// land on: the highest solid one of each column and its neighbours.
  /// A falling block of [material], drawn as it is drawn lying in the
  /// world: the same pictures, the same way up.
  SceneNode _fallingLook(int material) {
    final look = SceneNode(name: 'falling block');
    for (final (mesh, surface) in _blocks.putIfAbsent(
      material,
      () => <(DeviceMesh, RenderMaterial)>[
        for (final MapEntry(key: name, value: data) in blockMeshes(
          kindOf(material),
        ).entries)
          (DeviceMesh.upload(_device, data), _surfaces.of(name)),
      ],
    )) {
      look.add(MeshNode(mesh, surface, name: 'falling block'));
    }
    return look;
  }

  void _ground3x3(int x, int z) {
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final cx = x + dx, cz = z + dz;
        if (cx < 0 || cz < 0 || cx >= blocks.sizeX || cz >= blocks.sizeZ) {
          continue;
        }
        final top = _top(cx, cz).toInt() - 1;
        if (top < 0 || _solid.containsKey((cx, top, cz))) continue;
        _solid[(cx, top, cz)] = elements.addBody(
          Solid.box(
            Vector3.all(0.5),
            material: NativeMaterial.stone(),
            density: _blockDensity,
          ),
          at: Vector3(cx + 0.5, top + 0.5, cz + 0.5),
          type: NativeBodyType.fixed,
        );
      }
    }
  }

  /// A frame: the water, the fires and the falling blocks on by [dt], seen
  /// from [eye].
  void step(double dt, Vector3 eye) {
    // Planks next to burning planks get a body of their own, to be warmed
    // by the fire and catch from it.
    for (final key in _wood.keys.toList()) {
      if (!world.isBurning(_wood[key]!.native)) continue;
      final (x, y, z) = key;
      for (final (dx, dy, dz) in <(int, int, int)>[
        (1, 0, 0),
        (-1, 0, 0),
        (0, 1, 0),
        (0, -1, 0),
        (0, 0, 1),
        (0, 0, -1),
      ]) {
        if (blocks.at(x + dx, y + dy, z + dz) == planks) {
          _woodAt(x + dx, y + dy, z + dz);
        }
      }
    }
    elements.update(dt, eye: eye);
    // Burnt through: the block is gone, and what it held may fall.
    for (final key in _wood.keys.toList()) {
      // Charred past what holds the boards together, the block — a cubic
      // metre — is gone before the last of it has burnt.
      if (world.fuelOf(_wood[key]!.native) > _plankDensity * _holds) continue;
      final (x, y, z) = key;
      setBlock(x, y, z, Voxels.empty);
    }
    for (final f in _falling.toList()) {
      final p = world.localPositionOf(f.body.native);
      f.still = world.velocityOf(f.body.native).length < 0.05
          ? f.still + dt
          : 0.0;
      if (f.still < 0.5 && p.y > -8.0) continue;
      // At rest: a block again, in the cell it lies in, if that is free.
      _falling.remove(f);
      elements.lookOf(f.body)?.removeFromParent();
      elements.remove(f.body);
      final x = p.x.floor(), y = math.max(p.y.floor(), 0), z = p.z.floor();
      if (blocks.contains(x, y, z) && !blocks.isSolid(x, y, z)) {
        setBlock(x, y, z, f.material);
      }
    }
  }

  /// The elements' part of the sandbox's state: the core's world — the
  /// water over the blocks, every body and its heat — as the core writes it,
  /// the flames held, and which of the core's bodies are which block's.
  Map<String, Object?> save() => <String, Object?>{
    'world': base64Encode(world.snapshot()),
    'elements': elements.saveElements(),
    'wood': <Object?>[
      for (final MapEntry(key: (x, y, z), value: body) in _wood.entries)
        <int>[x, y, z, body.native.raw],
    ],
    'solid': <Object?>[
      for (final MapEntry(key: (x, y, z), value: body) in _solid.entries)
        <int>[x, y, z, body.native.raw],
    ],
    'falling': <Object?>[
      for (final f in _falling)
        <Object?>[f.body.native.raw, f.material, f.still],
    ],
  };

  /// Back to what [save] wrote, over blocks already put back: the bodies
  /// made since taken out with their looks, the core's world as it was, the
  /// ground the water runs over measured again from the blocks, and the
  /// bodies the save names given to their blocks again. Null — a state
  /// taken before the elements were up — leaves the world with none of
  /// the blocks' bodies in it.
  void restore(Map<String, Object?>? saved) {
    for (final body in <TrackedBody>[..._wood.values, ..._solid.values]) {
      elements.remove(body);
    }
    for (final f in _falling) {
      elements.lookOf(f.body)?.removeFromParent();
      elements.remove(f.body);
    }
    _wood.clear();
    _solid.clear();
    _falling.clear();
    if (saved != null) {
      world.restore(base64Decode(saved['world']! as String));
    }
    for (var z = 0; z < blocks.sizeZ; z++) {
      for (var x = 0; x < blocks.sizeX; x++) {
        _ground[x + z * blocks.sizeX] = _top(x, z);
      }
    }
    pool.setGround(_ground);
    if (saved == null) return;
    for (final row in (saved['wood'] as List<Object?>?) ?? const <Object?>[]) {
      if (row case [final int x, final int y, final int z, final int raw]) {
        _wood[(x, y, z)] = elements.track(NativeBody(raw));
      }
    }
    for (final row in (saved['solid'] as List<Object?>?) ?? const <Object?>[]) {
      if (row case [final int x, final int y, final int z, final int raw]) {
        _solid[(x, y, z)] = elements.track(NativeBody(raw));
      }
    }
    for (final row
        in (saved['falling'] as List<Object?>?) ?? const <Object?>[]) {
      if (row case [final int raw, final int material, final num still]) {
        final look = _fallingLook(material);
        elements.fireView.scene.add(look);
        _falling.add(
          _Falling(elements.track(NativeBody(raw), look: look), material)
            ..still = still.toDouble(),
        );
      }
    }
    final held = saved['elements'];
    elements.restoreElements(
      held is Map ? held.cast<String, Object?>() : const <String, Object?>{},
    );
  }

  /// Where each falling block is, by the order they fell in.
  List<BodyPose> poses() => <BodyPose>[
    for (final (i, f) in _falling.indexed)
      BodyPose(
        'falling#$i',
        world.localPositionOf(f.body.native),
        world.orientationOf(f.body.native),
      ),
  ];

  void dispose() => elements.dispose();
}
