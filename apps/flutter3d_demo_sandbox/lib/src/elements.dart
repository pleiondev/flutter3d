/// Water, fire and falling blocks over the sandbox's world, on the physics
/// core: water poured on a column runs over the tops of the blocks and
/// pools where they hollow; planks set alight burn, light the planks beside
/// them and are gone when burnt through, and water puts them out; a block
/// left with nothing under it or beside it falls as a body and, come to
/// rest, is a block again where it lies.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_voxel/flutter3d_voxel.dart';
import 'package:vector_math/vector_math.dart';

import 'block_surfaces.dart';
import 'palette.dart';

/// A block on fire, or a block falling.
final class _Body {
  _Body(this.body, this.material, [this.nodes = const <MeshNode>[]]);

  final NativeBody body;
  final int material;

  /// What draws a falling block: a node a surface it shows.
  final List<MeshNode> nodes;
  double still = 0.0;
}

/// The elements over [blocks], drawn into a scene through a renderer.
final class Elements {
  Elements({
    required this.blocks,
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required LiquidLook water,
    required this.setBlock,
    BlockSurfaces? surfaces,
  }) : _scene = scene,
       _device = device,
       _surfaces = surfaces ?? BlockSurfaces.flat() {
    _ground = <double>[
      for (var z = 0; z < blocks.sizeZ; z++)
        for (var x = 0; x < blocks.sizeX; x++) _top(x, z),
    ];
    pool = world.createShallowLiquid(
      nx: blocks.sizeX,
      nz: blocks.sizeZ,
      cell: 1.0,
      origin: Vector3.zero(),
      ground: _ground,
    );
    world.setShallowBed(pool, roughness: 0.03, openEdges: true);
    _water = water;
    _view = LiquidView(
      world: world,
      liquid: pool,
      ground: _ground,
      device: device,
      scene: scene,
      look: water.material,
      detail: LiquidDetail.light,
    );
    _fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.7,
    );
  }

  final VoxelWorld blocks;

  /// A block of planks, kg, and the share of its fuel it holds together
  /// with: past half burnt, it falls apart.
  static const double _plankMass = 60.0, _holds = 0.4;

  /// Puts [material] at a block, as an edit of the world: what burns out
  /// and what falls changes the world through this.
  final bool Function(int x, int y, int z, int material) setBlock;

  final NativeWorld world = NativeWorld();
  late final NativeShallowLiquid pool;
  final Scene _scene;
  final GraphicsDevice _device;
  final BlockSurfaces _surfaces;
  late final List<double> _ground;
  late final LiquidLook _water;
  late final LiquidView _view;
  late final FireView _fire;

  /// A whole block of each kind that has fallen, uploaded the first time
  /// one does and kept for the next: a mesh and its material a surface.
  final Map<int, List<(DeviceMesh, Material)>> _blocks =
      <int, List<(DeviceMesh, Material)>>{};
  double _clock = 0.0;

  /// The planks that have a body to burn in, by their block, and the blocks
  /// falling.
  final Map<(int, int, int), _Body> _wood = <(int, int, int), _Body>{};
  final List<_Body> _falling = <_Body>[];

  /// Solid blocks standing in for the world round a falling one, so it has
  /// something to land on: built where one falls, by block.
  final Map<(int, int, int), NativeBody> _solid =
      <(int, int, int), NativeBody>{};

  /// Whether any planks are burning now.
  bool get burning => _wood.values.any((w) => world.isBurning(w.body));

  /// The top of the column at (x, z): how high its highest block reaches.
  double _top(int x, int z) {
    for (var y = blocks.sizeY - 1; y >= 0; y--) {
      if (blocks.isSolid(x, y, z)) return y + 1.0;
    }
    return 0.0;
  }

  /// A bucket of water — half a cubic metre — tipped onto column (x, z).
  void pour(int x, int z) =>
      world.pourShallowLiquid(pool, x + 0.5, z + 0.5, radius: 0.5, volume: 0.5);

  /// Flint struck at block (x, y, z): it catches if it is planks.
  bool ignite(int x, int y, int z) {
    if (blocks.at(x, y, z) != planks) return false;
    final wood = _woodAt(x, y, z);
    world.setTemperature(wood.body, 700.0);
    return true;
  }

  _Body _woodAt(int x, int y, int z) => _wood.putIfAbsent((x, y, z), () {
    final body = world.addBody(
      position: Vector3(x + 0.5, y + 0.5, z + 0.5),
      type: NativeBodyType.fixed,
      // A block of planks: boards stacked with air between them, a
      // cubic metre of which weighs little more than a tenth of solid pine.
      mass: _plankMass,
    );
    world
      ..setShape(body, NativeShape.box(Vector3.all(0.5)))
      ..setMaterial(body, NativeMaterial.wood());
    return _Body(body, planks);
  });

  /// The world changed at block (x, y, z): the water's floor follows it,
  /// and what it held up may fall.
  void changed(int x, int y, int z) {
    final top = _top(x, z);
    final i = x + z * blocks.sizeX;
    if (_ground[i] != top) {
      _ground[i] = top;
      world.setShallowGround(pool, _ground);
    }
    final wood = _wood.remove((x, y, z));
    if (wood != null) world.removeBody(wood.body);
    final solid = _solid.remove((x, y, z));
    if (solid != null) world.removeBody(solid);
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
    final body = world.addBody(
      position: Vector3(x + 0.5, y + 0.5, z + 0.5),
      mass: material == planks ? _plankMass : 2000.0,
    );
    world.setShape(body, NativeShape.box(Vector3.all(0.49)));
    // Drawn as it is drawn lying in the world: the same pictures, the same
    // way up.
    final nodes = <MeshNode>[
      for (final (mesh, look) in _blocks.putIfAbsent(
        material,
        () => <(DeviceMesh, Material)>[
          for (final MapEntry(key: name, value: data) in blockMeshes(
            kindOf(material),
          ).entries)
            (DeviceMesh.upload(_device, data), _surfaces.of(name)),
        ],
      ))
        MeshNode(mesh, look, name: 'falling block'),
    ];
    nodes.forEach(_scene.add);
    _falling.add(_Body(body, material, nodes));
    // Out of the world as a block, which tells what stood on it in turn.
    setBlock(x, y, z, Voxels.empty);
    _ground3x3(x, z);
  }

  /// The blocks round column (x, z) as bodies, for what falls there to
  /// land on: the highest solid one of each column and its neighbours.
  void _ground3x3(int x, int z) {
    for (var dz = -1; dz <= 1; dz++) {
      for (var dx = -1; dx <= 1; dx++) {
        final cx = x + dx, cz = z + dz;
        if (cx < 0 || cz < 0 || cx >= blocks.sizeX || cz >= blocks.sizeZ) {
          continue;
        }
        final top = _top(cx, cz).toInt() - 1;
        if (top < 0 || _solid.containsKey((cx, top, cz))) continue;
        final body = world.addBody(
          position: Vector3(cx + 0.5, top + 0.5, cz + 0.5),
          type: NativeBodyType.fixed,
          mass: 0.0,
        );
        world.setShape(body, NativeShape.box(Vector3.all(0.5)));
        _solid[(cx, top, cz)] = body;
      }
    }
  }

  /// A frame: the water, the fires and the falling blocks on by [dt], seen
  /// from [eye].
  void step(double dt, Vector3 eye) {
    _clock += dt;
    // Planks next to burning planks get a body of their own, to be warmed
    // by the fire and catch from it.
    for (final key in _wood.keys.toList()) {
      final w = _wood[key]!;
      if (!world.isBurning(w.body)) continue;
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
      // Under water, it goes out.
      final here = world.sampleShallow(pool, x + 0.5, z + 0.5);
      if (here != null && here.depth > 0.05 && here.surface > y) {
        world.addWater(w.body, 20.0 * dt);
      }
    }
    world.step(dt);
    // Burnt through: the block is gone, and what it held may fall.
    for (final key in _wood.keys.toList()) {
      final w = _wood[key]!;
      // Charred half through, the boards no longer hold: the block is
      // gone before the last of it has burnt.
      if (world.fuelOf(w.body) > _plankMass * _holds) continue;
      final (x, y, z) = key;
      setBlock(x, y, z, Voxels.empty);
    }
    for (final f in _falling.toList()) {
      final p = world.positionOf(f.body);
      final turn = world.orientationOf(f.body);
      for (final node in f.nodes) {
        node
          ..setPosition(p.x, p.y, p.z)
          ..setRotation(turn);
      }
      f.still = world.velocityOf(f.body).length < 0.05 ? f.still + dt : 0.0;
      if (f.still < 0.5 && p.y > -8.0) continue;
      // At rest: a block again, in the cell it lies in, if that is free.
      _falling.remove(f);
      world.removeBody(f.body);
      f.nodes.forEach(_scene.remove);
      final x = p.x.floor(), y = math.max(p.y.floor(), 0), z = p.z.floor();
      if (blocks.contains(x, y, z) && !blocks.isSolid(x, y, z)) {
        setBlock(x, y, z, f.material);
      }
    }
    _view.update();
    _fire.update(dt);
    _water.update(seconds: _clock, eye: eye);
  }

  void dispose() => world.dispose();
}
