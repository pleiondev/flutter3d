/// The first crypt's vault, flooded: a hand's depth of black water held in
/// by a stone sill at its door, fed by a culvert that spills down the far
/// wall and drained under the sill, so it is never quite still.
///
/// Drawn and heard only. The run's own floor is the dry floor it always was;
/// what wades here is a body in the effects world following the player, and
/// the wakes are that body's.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show CollisionWorld, ColliderKind, RayHit;
import 'package:vector_math/vector_math.dart';

import 'wooden_props.dart';

/// Where a level floods: a room's floor, from ([x0], [z0]) to ([x1], [z1]),
/// filled to [level]; the doorway the water is held back at, along the
/// room's west wall from [doorZ0] to [doorZ1]; and the culvert in the east
/// wall the water comes from, at [culvertZ].
final class FloodPlan {
  const FloodPlan({
    required this.x0,
    required this.z0,
    required this.x1,
    required this.z1,
    required this.level,
    required this.doorZ0,
    required this.doorZ1,
    required this.culvertZ,
  });

  final double x0, z0, x1, z1, level, doorZ0, doorZ1, culvertZ;

  /// The vault of the first crypt, east of the guard room, where the iron
  /// key lies.
  static const FloodPlan cryptVault = FloodPlan(
    x0: 9.0,
    z0: -13.0,
    x1: 19.0,
    z1: -3.0,
    level: 0.24,
    doorZ0: -9.5,
    doorZ1: -6.5,
    culvertZ: -8.0,
  );

  /// The plans by level name: only the first crypt floods.
  static const Map<String, FloodPlan> byLevel = <String, FloodPlan>{
    'The Crypt': cryptVault,
  };
}

/// One flooded room in the effects world, drawn into a level's scene.
final class FloodedVault {
  FloodedVault({
    required this.world,
    required this.plan,
    required CollisionWorld collision,
    required GraphicsDevice device,
    required Scene scene,
    required LiquidLook look,
    required Material stone,
    required bool light,
  }) : _device = device,
       _scene = scene,
       _look = look {
    nx = ((plan.x1 - plan.x0) / cell).round();
    nz = ((plan.z1 - plan.z0) / cell).round();
    final ground = <double>[
      for (var j = 0; j < nz; j++)
        for (var i = 0; i < nx; i++)
          _groundAt(
            collision,
            plan.x0 + (i + 0.5) * cell,
            plan.z0 + (j + 0.5) * cell,
          ),
    ];
    liquid = world.createShallowLiquid(
      nx: nx,
      nz: nz,
      cell: cell,
      origin: Vector3(plan.x0, 0.0, plan.z0),
      ground: ground,
    );
    world
      ..setShallowBed(liquid, roughness: 0.02)
      ..fillShallowLiquid(
        liquid,
        x0: plan.x0,
        z0: plan.z0,
        x1: plan.x1,
        z1: plan.z1,
        level: plan.level,
      )
      // The culvert's water wells up on its ledge and runs off its lip; as
      // much again is drawn off under the sill, so the level holds and a
      // slow current crosses the room.
      ..setShallowSource(
        liquid,
        0,
        x: plan.x1 - 0.2,
        z: plan.culvertZ,
        radius: 0.3,
        rate: _flow,
      )
      ..setShallowSource(
        liquid,
        1,
        x: plan.x0 + 0.3,
        z: (plan.doorZ0 + plan.doorZ1) / 2,
        radius: 0.6,
        rate: -_flow,
      );
    final before = scene.meshes.toSet();
    view = LiquidView(
      world: world,
      liquid: liquid,
      ground: ground,
      device: device,
      scene: scene,
      look: look.material,
      detail: light ? _phoneDetail : _detail,
    );
    _drawn.addAll(scene.meshes.where((m) => !before.contains(m)));
    // No mist over the culvert's foot: see [_detail].
    for (final node in _drawn) {
      if (node.name == 'mist') node.visible = false;
    }
    _build(stone);
  }

  /// The world the water is in.
  final NativeWorld world;
  final FloodPlan plan;
  final GraphicsDevice _device;
  final Scene _scene;
  final LiquidLook _look;

  /// A torch's flame as the water's sun: its colour times its brightness,
  /// enough for its image in the water to burn as the flame does while the
  /// light it throws into the water's body stays a glimmer.
  static Vector3 get flameLight => Vector3(1.3, 0.62, 0.22);

  /// A quarter of a metre a cell: a stride crosses three, and the room is
  /// forty by forty.
  static const double cell = 0.25;

  /// The culvert's ledge: how far it stands out from the east wall, how
  /// wide it is, and how high, m.
  static const double _ledgeOut = 0.6, _ledgeHalfWide = 0.7, _ledgeTop = 1.1;

  /// The sill across the doorway, m: a little over the water.
  static const double _sillTop = 0.32;

  /// What the culvert brings in and the sill lets out, m³/s: a steady
  /// spill of thirty litres a second, enough to keep a current across the
  /// room and a falls to hear, not a torrent throwing spray across it.
  static const double _flow = 0.03;

  /// How much of the culvert's spill is drawn. A falls' detail is sized
  /// for a falls: thousands of drops, and a puff of mist for every third
  /// that lands, each swelling to near two metres across, all of them
  /// see-through and drawn over one another. Under a culvert that spills a
  /// metre into a pool that was a glowing fog filling the vault, which drew
  /// at a third of the frame rate of the rooms round it.
  ///
  /// **A hundred drops, not hundreds.** Where the spill lands it throws its
  /// drops along the same few arcs step after step, and with three hundred
  /// and sixty drawn they hung about the culvert's foot as strings of white
  /// beads a metre long; a hundred is the splash, and what is past them is
  /// still simulated.
  ///
  /// **And no mist at all.** A puff is drawn with the water's own look,
  /// lit by the torch the look's sun is, and a few dozen of them over the
  /// culvert's foot showed as tan, glowing clouds standing on the water.
  /// Thirty litres a second falling a metre throws spray, not a cloud; the
  /// drops and the froth at its foot are the falls. Not for the frame rate:
  /// measured in a profile build, the vault draws as fast as the hall with
  /// the mist hidden, and a few frames a second slower with it shown.
  static const LiquidDetail _detail = LiquidDetail(
    sheet: 1500,
    drops: 100,
    bubbles: 1200,
  );

  /// The same on a phone.
  static const LiquidDetail _phoneDetail = LiquidDetail(
    sheet: 800,
    drops: 50,
    bubbles: 400,
  );

  late final int nx, nz;
  late final NativeShallowLiquid liquid;
  late final LiquidView view;

  /// What this vault put into the scene, to be taken out with it.
  final List<MeshNode> _drawn = <MeshNode>[];

  /// The sill's and the ledge's bodies, for what is thrown about the room.
  final List<NativeBody> _stones = <NativeBody>[];

  final RayHit _hit = RayHit();

  /// The floor under the middle of a cell, as the run's own walls and floor
  /// have it: the first thing straight down from shoulder height that faces
  /// up. A wall, or anything the ray starts inside, stands above the water.
  /// The culvert's ledge is the vault's own.
  double _groundAt(CollisionWorld collision, double x, double z) {
    if ((x - plan.x1).abs() < _ledgeOut &&
        (z - plan.culvertZ).abs() < _ledgeHalfWide) {
      return _ledgeTop;
    }
    final found = collision.raycast(
      Vector3(x, 1.5, z),
      Vector3(0.0, -1.0, 0.0),
      3.0,
      _hit,
    );
    if (!found ||
        _hit.collider?.kind != ColliderKind.static ||
        _hit.normal.y < 0.8 ||
        _hit.distance < 0.01) {
      return 3.0;
    }
    return _hit.point.y;
  }

  void _build(Material stone) {
    final doorMiddle = (plan.doorZ0 + plan.doorZ1) / 2;
    final doorHalf = (plan.doorZ1 - plan.doorZ0) / 2;
    final sillHalf = Vector3(0.5, _sillTop / 2, doorHalf);
    final sillAt = Vector3(plan.x0 - 0.5, _sillTop / 2, doorMiddle);
    final ledgeHalf = Vector3(_ledgeOut / 2, _ledgeTop / 2, _ledgeHalfWide);
    final ledgeAt = Vector3(
      plan.x1 - _ledgeOut / 2,
      _ledgeTop / 2,
      plan.culvertZ,
    );
    for (final (at, half) in <(Vector3, Vector3)>[
      (sillAt, sillHalf),
      (ledgeAt, ledgeHalf),
    ]) {
      final node = MeshNode(
        DeviceMesh.upload(_device, blockMesh(at, half, every: 1.2)),
        stone,
        name: 'vault stone',
      );
      _scene.add(node);
      _drawn.add(node);
      final body = world.addBody(
        position: at,
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      world
        ..setShape(body, NativeShape.box(half))
        ..setMaterial(body, NativeMaterial.stone());
      _stones.add(body);
    }
    // The culvert's mouth: a dark opening in the wall over the ledge.
    final mouth = MeshNode(
      DeviceMesh.upload(
        _device,
        blockMesh(
          Vector3(plan.x1 - 0.01, _ledgeTop + 0.22, plan.culvertZ),
          Vector3(0.02, 0.2, 0.32),
        ),
      ),
      Material(
        name: 'culvert',
        baseColor: Vector4(0.015, 0.014, 0.013, 1.0),
        roughness: 1.0,
      ),
      name: 'culvert mouth',
    );
    _scene.add(mouth);
    _drawn.add(mouth);
  }

  /// The water at ([x], [z]), or null off its grid.
  NativeShallowSample? at(double x, double z) =>
      world.sampleShallow(liquid, x, z);

  /// Whether ([x], [z]) is over the vault's floor.
  bool covers(double x, double z) =>
      x > plan.x0 && x < plan.x1 && z > plan.z0 && z < plan.z1;

  /// The surface drawn as the world has it, [dt] seconds after the last
  /// time, as seen from [eye] with the torch [flames] about the level lit.
  void update(
    double dt, {
    required Vector3 eye,
    required Iterable<Vector3> flames,
  }) {
    view.update(dt);
    _mirror(eye, flames);
  }

  /// The look's one sun shone from the flame whose image the water shows
  /// [eye], onto the point of the surface the image is at.
  ///
  /// The material mirrors a sky and a sun, not the room; a sun fixed in
  /// one direction put its glint wherever that direction happened to fall,
  /// mostly nowhere the eye was looking. Aimed from the flame at its own
  /// image, the glint is drawn where the flame's reflection is, and the
  /// ripples break it into the trembling streak a torch makes on water.
  /// Of the flames in the vault itself, the nearest whose image lies on the
  /// water: the guard room's torch, behind the vault's west wall, is nearer
  /// the doorway than the vault's own, and the glint it was aimed from lay
  /// off to the side of the room where no torch could be mirrored.
  void _mirror(Vector3 eye, Iterable<Vector3> flames) {
    final over = eye.y - plan.level;
    if (over <= 0.0) return;
    final image = Vector3.zero();
    Vector3? shone;
    var nearest = double.infinity;
    for (final flame in flames) {
      final under = flame.y - plan.level;
      if (under <= 0.0 || !covers(flame.x, flame.z)) continue;
      // Where the line from the eye to the flame mirrored under the
      // surface crosses it: as far along as the eye's height is of the
      // two heights together.
      final t = over / (over + under);
      final x = eye.x + (flame.x - eye.x) * t;
      final z = eye.z + (flame.z - eye.z) * t;
      final far = flame.distanceToSquared(eye);
      if (!covers(x, z) || far >= nearest) continue;
      nearest = far;
      shone = flame;
      image.setValues(x, plan.level, z);
    }
    if (shone == null) return;
    _look.sun(along: image - shone, light: flameLight);
  }

  /// Out of the world and the scene, its meshes given back.
  void dispose() {
    for (final node in _drawn) {
      node.removeFromParent();
      final mesh = node.mesh;
      if (mesh is DeviceMesh) {
        _device
          ..releaseGeometry(mesh.vertices)
          ..releaseGeometry(mesh.indices);
      }
    }
    _drawn.clear();
    for (final body in _stones) {
      world.removeBody(body);
    }
    _stones.clear();
    world.removeShallowLiquid(liquid);
  }
}
