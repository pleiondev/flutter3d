/// Fire, water and loose wood over the crypt, on the physics core: every
/// torch a small fire of the core's own, crates and barrels standing about
/// the rooms that a rocket's blast throws, breaks and sets alight, that
/// light one another and char and fall apart as they burn, and the first
/// crypt's flooded vault.
///
/// **A layer over the run, never part of it.** It has worlds of its own,
/// built from what the run already shows — the level's brushes, its
/// collision world asked by rays where the floor is and where the corners
/// are, the torches the fixtures hold — and fed each frame with what the
/// run did: where the player and the monsters are, which rockets went off,
/// which shots landed. Nothing here writes to the simulation, so a crate in
/// the way is shoved aside by the player rather than stopping them, a fire
/// burns nobody, and a replay or a test of the run cannot tell the layer is
/// there.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game/flutter3d_game.dart'
    show FixtureVisuals, TorchFire;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    hide ParticleSystem;
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Actor,
        Brush,
        CollisionWorld,
        ColliderKind,
        EntityDef,
        LightFixture,
        RayHit;
import 'package:vector_math/vector_math.dart';

import 'flooded_vault.dart';
import 'wooden_props.dart';

/// What the layer's bodies are, as its collision filters see them.
abstract final class _Layer {
  /// The level's walls and floors, and the vault's stones.
  static const int stone = 1;

  /// Crates, barrels and what is left of them.
  static const int wood = 2;

  /// The bodies standing in for the player and the monsters: they shove the
  /// wood and wade the water, and pass through the walls, which the run
  /// already keeps them out of.
  static const int walker = 4;
}

/// A crate or a barrel, or a piece of one.
final class _Wood {
  _Wood(
    this.body,
    this.nodes, {
    required this.fuel,
    required this.barrel,
    required this.reach,
  }) : fresh = nodes.first.material.baseColor.clone();

  final NativeBody body;
  final List<MeshNode> nodes;

  /// The fuel it started with, kg.
  final double fuel;
  final bool barrel;

  /// How far its faces stand from its middle, m, near enough: half a
  /// crate's side, a barrel's girth, a board's half-length.
  final double reach;

  /// Its boards' colour before any fire reached them.
  final Vector4 fresh;

  /// How long it has been burnt out, s, for a piece to be swept away.
  double cold = 0.0;

  /// The heat a torch's flame has put into one face of it, J.
  double licked = 0.0;

  /// The heat the flames of burning wood beside it have put into the face
  /// it turns to them, J, cooling off as the skin does once they are gone.
  double flanked = 0.0;
}

/// A torch: the fixture, its flame, and the core's fire at it.
final class _Torch {
  _Torch(this.fixture, this.flame);

  final LightFixture fixture;
  final TorchFire flame;
  NativeBody? fire;
}

/// A body following something of the run's, and how far it has waded.
final class _Walker {
  _Walker(this.body, this.at);

  final NativeBody body;
  final Vector3 at;
  bool wet = false;
  double stride = 0.0;
}

/// The layer, drawn into each level's scene through one renderer.
final class CryptElements {
  CryptElements({
    required GraphicsDevice device,
    required Renderer renderer,
    required Scene scene,
    required this.props,
    required this.water,
    required this.particles,
    this.light = false,
  }) : _device = device,
       _scene = scene {
    _fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      // A board's width rather than a crate's: the flames are seen close,
      // in rooms a few metres across, and a tongue as wide as the crate
      // reads as a glowing cloud.
      baseWidth: 0.2,
      detail: light ? FireDetail.light : FireDetail.full,
    );
    _fire.light
      ..range = 9.0
      ..color.setValues(1.0, 0.5, 0.18);
    // A torch's flame is a hand across, and burns all night: its own view,
    // sized for it, over a world that holds nothing else.
    _torchFire = FireView(
      world: torchWorld,
      device: device,
      scene: scene,
      renderer: renderer,
      baseWidth: 0.07,
      detail: light
          ? const FireDetail(flames: 150, embers: 40, smoke: 40, smokeCell: 16)
          : const FireDetail(
              flames: 400,
              embers: 120,
              smoke: 120,
              smokeCell: 24,
            ),
    );
    // A crypt has no sky: the water mirrors a dark vault, its one sun the
    // torch on the vault's north wall, and is clear over the flags but
    // black-green where it stands deeper. What it mirrors low down, at the
    // grazing angles most of the room is seen at, is torchlit stone, warm
    // and a few times brighter than the vault's black ceiling; mirroring
    // the ceiling's dark there too left the water a flat grey sheet.
    water
      ..sun(along: Vector3(0.0, -0.5, 0.85), light: Vector3(0.5, 0.3, 0.15))
      ..sky(
        zenith: Vector3(0.02, 0.016, 0.013),
        horizon: Vector3(0.08, 0.056, 0.034),
      )
      ..tint(
        shallow: Vector3(0.05, 0.06, 0.045),
        deep: Vector3(0.01, 0.015, 0.012),
        clearness: 0.3,
      )
      ..chop = 0.45;
  }

  final GraphicsDevice _device;
  Scene _scene;

  /// The crates' and barrels' meshes and pictures.
  final WoodenProps props;

  /// What the flooded vault's water is drawn with.
  final LiquidLook water;

  /// The game's own particles, which the splashes and the splinters join.
  final ParticleSystem particles;

  /// Whether to draw less of the fire and the water, for a phone.
  final bool light;

  /// The world the wood, the water and the walkers are in, with gravity.
  final NativeWorld world = NativeWorld();

  /// The torches' fires, on their own: a torch's flame drawn at a crate
  /// fire's size would be a bonfire on the wall.
  final NativeWorld torchWorld = NativeWorld();

  late final FireView _fire, _torchFire;

  /// What the fires and the water sound like this frame.
  late final PhysicsHearing hearing = PhysicsHearing(world);

  /// The strides through the water since the last frame, each a splash.
  final List<Audible> wading = <Audible>[];

  final List<NativeBody> _stone = <NativeBody>[];
  final List<_Torch> _torches = <_Torch>[];
  final List<_Wood> _wood = <_Wood>[];
  final List<_Wood> _pieces = <_Wood>[];
  _Walker? _player;
  final Map<Actor, _Walker> _monsters = <Actor, _Walker>{};
  FloodedVault? _vault;
  Material? _stoneLook;
  int _breaches = -1;
  double _clock = 0.0;

  /// Blasts and shots heard from the run since the last frame.
  final List<(Vector3, double)> _blasts = <(Vector3, double)>[];
  final List<(Vector3, Vector3, double)> _shots =
      <(Vector3, Vector3, double)>[];

  final RayHit _hit = RayHit();
  final math.Random _random = math.Random(17);

  /// A crate's and a barrel's mass, kg: boards of pine with air inside, and
  /// staves round an empty barrel.
  static const double _crateMass = 26.0, _barrelMass = 32.0;

  /// A board or a stave, kg.
  static const double _pieceMass = 2.2;

  /// How many crates and barrels a level stands, and how many pieces of
  /// broken ones lie about before the oldest are swept away.
  static const int _mostWood = 22, _mostPieces = 36;

  /// How many broken boards burn with a flame of their own at once.
  static const int _mostFlames = 8;

  /// The share of its fuel a crate holds together with: burnt past it, its
  /// boards come apart. A crate is thin boards and battens, and its joints
  /// go long before the wood does.
  static const double _holds = 0.85;

  /// Old dry boards with air between them: wood as the core has it, but
  /// burning at a little over half its rate — a crate's fire is the boards'
  /// faces, not the solid block of pine its box shape would otherwise be
  /// burnt as, which roared at four hundred kilowatts.
  static final NativeMaterial _boards = () {
    final w = NativeMaterial.wood();
    return NativeMaterial(
      specificHeat: w.specificHeat,
      emissivity: w.emissivity,
      ignitionTemperature: w.ignitionTemperature,
      heatOfCombustion: w.heatOfCombustion,
      burnRate: w.burnRate * 0.55,
      fuelFraction: w.fuelFraction,
      flameFeedback: w.flameFeedback,
      conductivity: w.conductivity,
      flameTemperature: w.flameTemperature,
      flameConvection: w.flameConvection,
      flameRadiant: w.flameRadiant,
      flameAbsorption: w.flameAbsorption,
    );
  }();

  /// The firelight over the crates at its brightest: about a torch's, so a
  /// burning crate lights its room as the torches do and does not wash the
  /// crypt out.
  static const double _brightest = 7.0;

  /// A rocket's blast throws wood within this many of its radii, lights what
  /// is within half of one, and splits what is within a third.
  static const double _throws = 1.6, _lights = 0.6, _splits = 0.35;

  // ---------------------------------------------------------------- level

  /// Everything of the last level let go, and [scene]'s level stood in:
  /// its walls and floors as stone, its torches lit, its wood placed where
  /// the rays find room for it, and its water if it floods. [player] is
  /// where the run has the player standing, which a save may have put
  /// anywhere: no crate is stood on them.
  void enter({
    required Scene scene,
    required String name,
    required List<Brush> brushes,
    required List<EntityDef> entities,
    required CollisionWorld collision,
    required FixtureVisuals fixtures,
    required Map<String, TextureHandle?> textures,
    required Vector3 player,
  }) {
    _clear();
    if (!identical(scene, _scene)) {
      for (final node in <SceneNode>[_fire.light, _torchFire.light]) {
        node.removeFromParent();
        scene.add(node);
      }
      _scene = scene;
    }
    _stoneLook = Material(
      name: 'vault stone',
      albedo: textures['assets/textures/stone_albedo.jpg'],
      normal: textures['assets/textures/stone_normal.png'],
      baseColor: Vector4(0.7, 0.66, 0.6, 1.0),
      roughness: 0.9,
    );
    _walls(brushes);
    for (final MapEntry(key: fixture, value: flame)
        in fixtures.flames.entries) {
      _torches.add(_Torch(fixture, flame));
    }
    final plan = FloodPlan.byLevel[name];
    if (plan != null) {
      _vault = FloodedVault(
        world: world,
        plan: plan,
        collision: collision,
        device: _device,
        scene: scene,
        look: water,
        stone: _stoneLook!,
        light: light,
      );
      hearing.listen(_vault!.liquid);
    }
    _place(name, entities, collision, fixtures, player);
  }

  void _clear() {
    for (final body in <NativeBody>[
      ..._stone,
      for (final w in _wood) w.body,
      for (final p in _pieces) p.body,
      for (final m in _monsters.values) m.body,
      ?_player?.body,
    ]) {
      world.removeBody(body);
      _fire.forget(body);
      hearing.forget(body);
    }
    for (final t in _torches) {
      final fire = t.fire;
      if (fire != null) torchWorld.removeBody(fire);
    }
    _stone.clear();
    _wood.clear();
    _pieces.clear();
    _monsters.clear();
    _torches.clear();
    _player = null;
    _vault?.dispose();
    _vault = null;
    _blasts.clear();
    _shots.clear();
    _breaches = -1;
  }

  /// The level's brushes as fixed boxes, for the wood to stand and land on.
  void _walls(List<Brush> brushes) {
    for (final body in _stone) {
      world.removeBody(body);
    }
    _stone.clear();
    for (final brush in brushes) {
      final body = world.addBody(
        position: brush.centre,
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      world
        ..setShape(body, NativeShape.box(brush.size / 2))
        ..setMaterial(body, NativeMaterial.stone())
        ..setCollisionFilter(body, layer: _Layer.stone, mask: _Layer.wood);
      _stone.add(body);
    }
  }

  // ------------------------------------------------------------ placement

  /// The first thing a ray from [from] along [along] meets within [far]
  /// that is the level's own stone, and how far off; [far] if nothing, and
  /// nought if it starts inside something.
  double _ray(
    CollisionWorld collision,
    Vector3 from,
    Vector3 along,
    double far,
  ) {
    if (!collision.raycast(from, along, far, _hit)) return far;
    return _hit.collider?.kind == ColliderKind.static ? _hit.distance : 0.0;
  }

  /// The floor straight under [at], if the ray finds one facing up.
  double? _floor(CollisionWorld collision, Vector3 at) {
    if (!collision.raycast(at, Vector3(0.0, -1.0, 0.0), 4.0, _hit)) {
      return null;
    }
    if (_hit.collider?.kind != ColliderKind.static || _hit.normal.y < 0.8) {
      return null;
    }
    return _hit.point.y;
  }

  static final List<Vector3> _round = <Vector3>[
    Vector3(1.0, 0.0, 0.0),
    Vector3(-1.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 1.0),
    Vector3(0.0, 0.0, -1.0),
  ];

  /// Whether a crate of half-side [half] fits standing on the floor at [at]:
  /// floor under its corners at the same height, nothing within its sides,
  /// and room over it.
  bool _fits(CollisionWorld collision, Vector3 at, double half) {
    for (final (dx, dz) in const <(double, double)>[
      (1.0, 1.0),
      (1.0, -1.0),
      (-1.0, 1.0),
      (-1.0, -1.0),
    ]) {
      final y = _floor(
        collision,
        Vector3(at.x + dx * half * 0.9, at.y + 1.0, at.z + dz * half * 0.9),
      );
      if (y == null || (y - at.y).abs() > 0.03) return false;
    }
    final middle = Vector3(at.x, at.y + 0.4, at.z);
    for (final d in _round) {
      if (_ray(collision, middle, d, half + 0.02) < half + 0.02) return false;
    }
    return _ray(collision, middle, Vector3(0.0, 1.0, 0.0), 2.0) >= 2.0;
  }

  /// Places the level's wood: by every other torch, a crate against the
  /// wall under it with a barrel on its other side; then into the room
  /// corners the rays find, a crate or two in each, well away from where
  /// anything the run places stands or opens; and two afloat in a flooded
  /// vault.
  void _place(
    String name,
    List<EntityDef> entities,
    CollisionWorld collision,
    FixtureVisuals fixtures,
    Vector3 player,
  ) {
    // The same every time a level is entered: placed by its name.
    final random = math.Random(name.hashCode);
    final keepOff = <Vector3>[
      player,
      for (final e in entities)
        if (const <String>{
          'player_spawn',
          'pickup',
          'key',
          'exit',
          'door',
          'trigger',
          'lift',
          'monster',
          'switch',
          'button',
          'widget_surface',
          'secret',
        }.contains(e.type))
          e.position,
    ];
    final taken = <Vector3>[];
    bool clearOf(Vector3 at, double near) =>
        keepOff.every((p) => _flat(p, at) > 2.4) &&
        taken.every((p) => _flat(p, at) > near) &&
        !(_vault?.covers(at.x, at.z) ?? false);

    // By the torches.
    for (final (i, flame) in fixtures.flames.values.indexed) {
      if (i.isOdd) continue;
      final head = flame.originInto(Vector3.zero());
      // The wall behind it: the nearest of four rays.
      final (wall, d) = _round
          .map((dir) => (dir, _ray(collision, head, dir, 1.0)))
          .reduce((a, b) => a.$2 <= b.$2 ? a : b);
      if (d >= 1.0 || d <= 0.0) continue;
      final floor = _floor(collision, head);
      if (floor == null) continue;
      final side = Vector3(-wall.z, 0.0, wall.x);
      final atWall = Vector3(head.x, floor, head.z) + wall * (d - 0.44);
      final crate = atWall + side * 0.95;
      final barrel = atWall - side * 0.9 + wall * 0.1;
      if (_fits(collision, crate, 0.4) && clearOf(crate, 1.5)) {
        _crate(crate, turn: random.nextDouble() * 0.2 - 0.1);
        taken.add(crate);
      }
      if (_fits(collision, barrel, 0.33) && clearOf(barrel, 0.9)) {
        _barrel(barrel);
        taken.add(barrel);
      }
    }

    // Into the corners: a grid over every floor the brushes hold up, each
    // point a corner where a wall stands close on one side along x and on
    // one along z, and runs on past the crate on both.
    final corners = <(Vector3, Vector3, Vector3)>[];
    final lo = Vector3.all(1e9), hi = Vector3.all(-1e9);
    for (final e in entities) {
      Vector3.min(lo, e.position, lo);
      Vector3.max(hi, e.position, hi);
    }
    for (var x = lo.x - 6.0; x <= hi.x + 6.0; x += 1.0) {
      for (var z = lo.z - 6.0; z <= hi.z + 6.0; z += 1.0) {
        // Searched down from a little over each floor something stands
        // on near here, so a level of several storeys is searched on each.
        for (final y in <double>{
          for (final e in entities)
            if (_standsOnFloor.contains(e.type) &&
                _flat(e.position, Vector3(x, 0, z)) < 14.0)
              e.position.y.floorToDouble(),
        }) {
          final floor = _floor(collision, Vector3(x, y + 1.2, z));
          if (floor == null) continue;
          final at = Vector3(x, floor + 0.4, z);
          if (_ray(collision, at, Vector3(0.0, 1.0, 0.0), 2.0) < 2.0) {
            continue;
          }
          final dx = <(Vector3, double)>[
            for (final dir in _round.take(2))
              (dir, _ray(collision, at, dir, 1.3)),
          ].reduce((a, b) => a.$2 <= b.$2 ? a : b);
          final dz = <(Vector3, double)>[
            for (final dir in _round.skip(2))
              (dir, _ray(collision, at, dir, 1.3)),
          ].reduce((a, b) => a.$2 <= b.$2 ? a : b);
          if (dx.$2 >= 1.3 || dz.$2 >= 1.3 || dx.$2 <= 0 || dz.$2 <= 0) {
            continue;
          }
          final spot = Vector3(
            x + dx.$1.x * (dx.$2 - 0.44),
            floor,
            z + dz.$1.z * (dz.$2 - 0.44),
          );
          // The walls run on: half a metre past the crate along each, the
          // other wall still stands as close.
          final up = Vector3(0.0, 0.4, 0.0);
          final alongX = spot + up - dz.$1 * 1.0;
          final alongZ = spot + up - dx.$1 * 1.0;
          if (_ray(collision, alongX, dx.$1, 0.6) >= 0.6 ||
              _ray(collision, alongZ, dz.$1, 0.6) >= 0.6) {
            continue;
          }
          if (!_fits(collision, spot, 0.4)) continue;
          corners.add((spot, dx.$1, dz.$1));
        }
      }
    }
    corners.shuffle(random);
    var clusters = 0;
    for (final (spot, wx, wz) in corners) {
      if (clusters >= 5 || _wood.length >= _mostWood - 3) break;
      if (!clearOf(spot, 4.0)) continue;
      clusters++;
      taken.add(spot);
      _crate(spot, turn: random.nextDouble() * 0.3 - 0.15);
      // A second on it, now and then, and a barrel or a smaller crate
      // along one of the walls.
      if (random.nextBool()) {
        _crate(
          spot + Vector3(0.03, WoodenProps.crateSize, -0.02),
          turn: random.nextDouble() * 0.6 - 0.3,
        );
      }
      final along = random.nextBool() ? -wx : -wz;
      final next = spot + along * 0.85;
      if (_fits(collision, next, 0.33)) {
        if (random.nextBool()) {
          _barrel(next + (along.x != 0 ? wz : wx) * 0.08);
        } else {
          _crate(next, turn: random.nextDouble() * 0.4, size: 0.75);
        }
        taken.add(next);
      }
    }

    // Afloat in the vault: a crate and a barrel that came in with the water.
    final vault = _vault;
    if (vault != null) {
      final p = vault.plan;
      _crate(Vector3(p.x0 + 6.5, p.level + 0.1, p.z0 + 2.4), turn: 0.5);
      _barrel(Vector3(p.x0 + 3.2, p.level + 0.05, p.z1 - 2.0), lying: true);
    }
  }

  /// What a level stands on its floors, and so says where they are.
  static const Set<String> _standsOnFloor = <String>{
    'player_spawn',
    'monster',
    'pickup',
    'key',
    'exit',
  };

  static double _flat(Vector3 a, Vector3 b) {
    final dx = a.x - b.x, dz = a.z - b.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  /// A crate standing on the floor at [at] (its foot), turned [turn] about
  /// the vertical; a little smaller for [size] under one.
  void _crate(Vector3 at, {double turn = 0.0, double size = 1.0}) {
    final half = WoodenProps.crateSize / 2 * size;
    final body = world.addBody(
      position: Vector3(at.x, at.y + half, at.z),
      mass: _crateMass * size * size * size,
    );
    world
      ..setShape(body, NativeShape.box(Vector3.all(half)))
      ..setOrientation(body, Quaternion.axisAngle(Vector3(0, 1, 0), turn));
    final node = MeshNode(
      props.crate,
      props.wood(
        tint: Vector4(
          1.0,
          0.84 + 0.06 * _random.nextDouble(),
          0.66 + 0.08 * _random.nextDouble(),
          1.0,
        ),
      ),
      name: 'crate',
    )..setScale(size, size, size);
    _add(body, <MeshNode>[node], barrel: false, reach: half);
  }

  /// A barrel standing at [at], or on its side.
  void _barrel(Vector3 at, {bool lying = false}) {
    const half = WoodenProps.barrelHeight / 2;
    final body = world.addBody(
      position: Vector3(
        at.x,
        at.y + (lying ? WoodenProps.barrelRadius + 0.04 : half),
        at.z,
      ),
      mass: _barrelMass,
    );
    world.setShape(
      body,
      const NativeShape.cylinder(WoodenProps.barrelRadius + 0.03, half),
    );
    if (lying) {
      world.setOrientation(
        body,
        Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
      );
    }
    final nodes = <MeshNode>[
      MeshNode(props.barrel, props.wood(), name: 'barrel'),
      MeshNode(props.hoops, props.iron, name: 'hoops'),
    ];
    _add(body, nodes, barrel: true, reach: WoodenProps.barrelRadius + 0.05);
  }

  void _add(
    NativeBody body,
    List<MeshNode> nodes, {
    required bool barrel,
    required double reach,
  }) {
    world
      ..setMaterial(body, _boards)
      ..setFriction(body, 0.7)
      ..setCollisionFilter(
        body,
        layer: _Layer.wood,
        mask: _Layer.stone | _Layer.wood | _Layer.walker,
      );
    nodes.forEach(_scene.add);
    final wood = _Wood(
      body,
      nodes,
      fuel: world.fuelOf(body),
      barrel: barrel,
      reach: reach,
    );
    _wood.add(wood);
    _fire.watch(body, nodes.first);
    final vault = _vault;
    if (vault != null) hearing.watch(body, vault.liquid);
    _sync(wood);
  }

  // ---------------------------------------------------------- what the run did

  /// A rocket went off at [at], its blast reaching [radius].
  void blast(Vector3 at, double radius) => _blasts.add((at.clone(), radius));

  /// A shot from [from] landed at [to]; [push] is the push its round gives
  /// what it meets on the way, N·s.
  void shot(Vector3 from, Vector3 to, double push) =>
      _shots.add((from.clone(), to.clone(), push));

  void _applyBlast(Vector3 at, double radius) {
    for (final w in _wood.toList()) {
      final p = world.positionOf(w.body);
      final off = p - at;
      final d = off.length;
      if (d > radius * _throws) continue;
      final near = 1.0 - d / (radius * _throws);
      if (d < radius * _lights) {
        // Set alight: its surface past what lights wood, and more the
        // nearer it stood.
        world.setTemperature(
          w.body,
          math.max(world.surfaceTemperatureOf(w.body), 640.0 + 200.0 * near),
        );
      } else {
        world.addHeat(w.body, 4e5 * near);
      }
      final out = (d > 1e-3 ? off / d : Vector3(0.0, 1.0, 0.0))
        ..y += 0.6
        ..normalize();
      if (d < radius * _splits) {
        _split(w, out * (9.0 * near + 3.0));
      } else {
        world
          ..applyImpulse(
            w.body,
            out * (world.massOf(w.body) * 9.0 * near),
            at: p + Vector3(0.0, 0.15, 0.0),
          )
          ..wake(w.body);
      }
    }
    for (final piece in _pieces) {
      final p = world.positionOf(piece.body);
      final off = p - at;
      final d = off.length;
      if (d > radius * _throws) continue;
      final out = (off..y += 0.5).normalized();
      world
        ..applyImpulse(
          piece.body,
          out * (_pieceMass * 10.0 * (1.0 - d / (radius * _throws))),
        )
        ..wake(piece.body);
    }
  }

  void _applyShot(Vector3 from, Vector3 to, double push) {
    final along = to - from;
    final far = along.length;
    if (far < 1e-3) return;
    along.scale(1.0 / far);
    final hit = world.rayCast(from, along, far, mask: _Layer.wood);
    if (hit == null) return;
    world
      ..applyImpulse(hit.body, along * push, at: hit.point)
      ..wake(hit.body);
    particles.burst(_splinters, hit.point, direction: hit.normal);
  }

  /// A crate or a barrel in pieces: its boards or staves flying out along
  /// [throw], as hot as it was.
  void _split(_Wood w, Vector3 throw_) {
    final p = world.positionOf(w.body);
    final turn = world.orientationOf(w.body);
    // The surface is as of the last step; a blast's heat this frame is
    // in the mean already.
    final kelvin = math.max(
      world.surfaceTemperatureOf(w.body),
      world.temperatureOf(w.body),
    );
    // Burning, or set alight by the blast that splits it, which the next
    // step would have found it to be.
    final burning =
        world.isBurning(w.body) || kelvin >= _boards.ignitionTemperature;
    final charred = w.nodes.first.material.baseColor.clone();
    _remove(w);
    _wood.remove(w);
    final count = w.barrel ? 7 : 6;
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count + _random.nextDouble() * 0.5;
      final spread = Vector3(
        math.cos(a),
        0.4 + _random.nextDouble(),
        math.sin(a),
      );
      final at = p + spread * 0.25;
      final half = w.barrel ? WoodenProps.staveHalf : WoodenProps.plankHalf;
      final body = world.addBody(position: at, mass: _pieceMass);
      world
        ..setShape(body, NativeShape.box(half))
        ..setOrientation(
          body,
          turn *
              Quaternion.axisAngle(
                Vector3(_random.nextDouble(), 1.0, _random.nextDouble())
                  ..normalize(),
                _random.nextDouble() * math.pi,
              ),
        )
        ..setMaterial(body, _boards)
        ..setFriction(body, 0.8)
        ..setCollisionFilter(
          body,
          layer: _Layer.wood,
          mask: _Layer.stone | _Layer.wood | _Layer.walker,
        )
        ..setVelocity(body, throw_ + spread * 2.5)
        ..setAngularVelocity(
          body,
          Vector3(
            _random.nextDouble() * 12 - 6,
            _random.nextDouble() * 12 - 6,
            _random.nextDouble() * 12 - 6,
          ),
        );
      // Half the boards of a burning crate go on burning, the rest fall
      // smouldering, below what keeps a flame; a cold crate's are as
      // charred as it had got.
      if (burning) {
        world.setTemperature(body, i.isEven ? math.max(kelvin, 700.0) : 520.0);
      }
      final material = props.wood()..baseColor.setFrom(charred);
      final node = MeshNode(
        w.barrel ? props.stave : props.plank,
        material,
        name: 'piece',
      );
      _scene.add(node);
      final piece = _Wood(
        body,
        <MeshNode>[node],
        fuel: world.fuelOf(body),
        barrel: w.barrel,
        reach: _pieceReach,
      );
      _pieces.add(piece);
      _fire.watch(body, node, fresh: charred);
      final vault = _vault;
      if (vault != null) hearing.watch(body, vault.liquid);
      _sync(piece);
    }
    while (_pieces.length > _mostPieces) {
      final old = _pieces.removeAt(0);
      _remove(old);
    }
  }

  void _remove(_Wood w) {
    world.removeBody(w.body);
    _fire.forget(w.body);
    hearing.forget(w.body);
    for (final node in w.nodes) {
      node.removeFromParent();
    }
  }

  /// Wood splinters off where a round strikes it.
  static final ParticleEffect _splinters = ParticleEffect(
    count: 8,
    emitter: const ConeEmitter(speed: Range(1.5, 4.5), halfAngleDegrees: 35.0),
    lifetime: const Range(0.25, 0.6),
    size: const Range(0.03, 0.07),
    color: Vector4(0.42, 0.33, 0.22, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(-9.8),
      const ParticleFade(startsAt: 0.5),
    ],
  );

  /// Water thrown up by a stride or a body falling in.
  static final ParticleEffect _splash = ParticleEffect(
    count: 16,
    emitter: const ConeEmitter(speed: Range(1.2, 2.8), halfAngleDegrees: 40.0),
    lifetime: const Range(0.3, 0.6),
    size: const Range(0.025, 0.055),
    color: Vector4(0.32, 0.34, 0.33, 1.0),
    affectors: <ParticleAffector>[
      const ParticleGravity(-9.8),
      const ParticleFade(startsAt: 0.4),
    ],
  );

  // ----------------------------------------------------------------- frame

  /// One frame, [dt] seconds on: the run's [player] (the middle of their
  /// body) and its living [monsters] followed, what it did since the last
  /// frame acted on, the worlds stepped and drawn as they stand, seen from
  /// [eye]. [brushes] are the level's walls as the run has them now, with
  /// [breachVersion] counting the rockets that have cut them.
  void update(
    double dt, {
    required Vector3 eye,
    required Vector3 player,
    required Iterable<Actor> monsters,
    List<Brush>? brushes,
    int breachVersion = 0,
  }) {
    dt = math.min(dt, 1 / 30);
    _clock += dt;
    if (brushes != null && breachVersion != _breaches) {
      _breaches = breachVersion;
      _walls(brushes);
    }
    for (final (at, radius) in _blasts) {
      _applyBlast(at, radius);
    }
    _blasts.clear();
    for (final (from, to, push) in _shots) {
      _applyShot(from, to, push);
    }
    _shots.clear();
    wading.clear();
    _player = _follow(_player, player, dt, radius: 0.3, key: 1);
    final seen = <Actor>{};
    for (final actor in monsters) {
      final at = actor.position;
      if (at == null || !actor.isAlive) continue;
      seen.add(actor);
      _monsters[actor] = _follow(
        _monsters[actor],
        at,
        dt,
        radius: 0.4,
        key: 2 + identityHashCode(actor),
      );
    }
    _monsters.removeWhere((actor, walker) {
      if (seen.contains(actor)) return false;
      world.removeBody(walker.body);
      return true;
    });
    _tendTorches();
    _torchHeat(dt);
    _flank(dt);
    _douse(dt);
    world.step(dt);
    torchWorld.step(dt);
    for (final w in _wood) {
      _sync(w);
    }
    for (final p in _pieces) {
      _sync(p);
    }
    _burnOut(dt);
    _vault?.update(dt);
    water.update(seconds: _clock, eye: eye);
    _fire.update(dt);
    _char();
    _torchFire.update(dt);
    // The fixtures already light the torches; the firelight here is the
    // crates', hung over the one burning nearest the eye.
    _torchFire.light.intensity = 0.0;
    _lightNearest(eye);
    hearing.update(dt);
  }

  /// A walker kept on [at]: driven there at whatever speed that takes, put
  /// there outright if it has fallen far behind, and splashing for each
  /// stride it takes through water.
  _Walker _follow(
    _Walker? walker,
    Vector3 at,
    double dt, {
    required double radius,
    required int key,
  }) {
    final w =
        walker ??
        () {
          final body = world.addBody(position: at, mass: 80.0);
          world
            ..setShape(body, NativeShape.capsule(radius, 0.55))
            ..lockRotation(body)
            ..setCollisionFilter(body, layer: _Layer.walker, mask: _Layer.wood);
          return _Walker(body, at.clone());
        }();
    final now = world.positionOf(w.body);
    final gap = at - now;
    if (gap.length > 1.0) {
      world
        ..setPosition(w.body, at)
        ..setVelocity(w.body, Vector3.zero());
    } else {
      world.setVelocity(w.body, gap / math.max(dt, 1e-3));
    }
    final moved = _flat(at, w.at);
    w.at.setFrom(at);
    final vault = _vault;
    if (vault == null || !vault.covers(at.x, at.z)) {
      w.wet = false;
      return w;
    }
    final here = vault.at(at.x, at.z);
    final wet = here != null && here.depth > 0.05;
    final speed = moved / math.max(dt, 1e-3);
    if (wet) {
      w.stride += moved;
      final entering = !w.wet && speed > 0.4;
      if (entering || w.stride > 0.8) {
        w.stride = 0.0;
        final feet = Vector3(at.x, here.surface, at.z);
        final loudness = (entering ? 0.9 : speed / 5.0).clamp(0.25, 0.9);
        wading.add(
          Audible(
            key,
            feet,
            loudness * math.min(1.0, here.depth / 0.2),
            0.88 + 0.24 * _random.nextDouble(),
          ),
        );
        particles.burst(_splash, feet, direction: Vector3(0.0, 1.0, 0.0));
      }
    }
    w.wet = wet;
    return w;
  }

  /// Every torch's fire kept burning while its fixture is lit, fuelled
  /// again as it burns down, and out while it is not.
  void _tendTorches() {
    for (final t in _torches) {
      var fire = t.fire;
      if (fire == null) {
        final head = t.flame.originInto(Vector3.zero());
        // Not placed until the scene has put its fixture somewhere.
        if (head.length2 < 1e-6) continue;
        fire = torchWorld.addBody(
          position: head + Vector3(0.0, 0.05, 0.0),
          type: NativeBodyType.fixed,
          mass: 0.8,
        );
        torchWorld
          ..setShape(fire, const NativeShape.cylinder(0.045, 0.06))
          ..setMaterial(fire, NativeMaterial.wood())
          ..setTemperature(fire, 900.0);
        t.fire = fire;
      }
      // Kept on the flame, which is where its fixture's node was last
      // drawn: on the frame the level arrives that is not yet out on the
      // torch's bracket.
      final head = t.flame.originInto(_head);
      torchWorld.setPosition(fire, head + Vector3(0.0, 0.05, 0.0));
      final burning = torchWorld.isBurning(fire);
      if (t.fixture.enabled) {
        // Pitch and rag enough for a night: topped up as it burns down.
        if (torchWorld.fuelOf(fire) < 0.05) {
          torchWorld.setMaterial(fire, NativeMaterial.wood());
        }
        if (!burning) torchWorld.setTemperature(fire, 900.0);
      } else if (burning) {
        torchWorld.addWater(fire, 0.2);
      }
    }
  }

  final Vector3 _head = Vector3.zero();

  /// How far from a torch's flame wood is in it, m: the tongues' reach
  /// round the head, past the wood's own faces.
  static const double _licks = 0.4;

  /// The torches' heat into the wood standing in their flames.
  ///
  /// The two fires are in two worlds, so the core cannot pass it: what a
  /// torch's fire gives off, as its world measures it, is handed to a crate
  /// or a board whose faces are within the flame's reach, as much of it as
  /// the flame wraps round — most of it, touching it — at the point the flame
  /// meets it. Wood further off feels nothing a torch could give it, which
  /// is true of real ones too.
  ///
  /// Handed in from outside, heat goes into the whole body, where a flame
  /// licking one face would have heated that face's skin; so the heat a
  /// face takes is counted too, and once it is what brings the skin of a
  /// board's face to burning — [_kindles] — the wood is alight. A crate
  /// held in a torch's flame catches in some twenty seconds.
  void _torchHeat(double dt) {
    for (final t in _torches) {
      final fire = t.fire;
      if (fire == null || !torchWorld.isBurning(fire)) continue;
      final flame = torchWorld.positionOf(fire)..y += 0.1;
      final watts = torchWorld.heatReleaseOf(fire);
      for (final w in _wood.followedBy(_pieces)) {
        final at = world.positionOf(w.body);
        final gap = (at - flame).length - w.reach;
        if (gap > _licks) continue;
        final joules = watts * 0.6 * (1.0 - math.max(gap, 0.0) / _licks) * dt;
        world.addHeatAt(w.body, flame, joules);
        w.licked += joules;
        if (w.licked > _kindles && !world.isBurning(w.body)) {
          w.licked = 0.0;
          world.setTemperature(w.body, _boards.ignitionTemperature + 60.0);
        }
      }
    }
  }

  /// Joules a torch's flame puts into a board's face before it burns: the
  /// skin of a hand's breadth of pine, a few millimetres deep, brought from
  /// the room's warmth to burning, and what it loses meanwhile.
  static const double _kindles = 2.0e4;

  /// How far a broken board's faces stand from its middle, on the whole: it
  /// is long and thin, and lies at any angle to what is beside it.
  static const double _pieceReach = 0.2;

  /// How far out from burning wood its flames lick the faces of wood
  /// beside it, m: a hand's breadth, about where a crate's flame leans out
  /// of its sides as it draws in air.
  static const double _flankReach = 0.3;

  /// The share of a fire's heat that goes into a face of wood touching it:
  /// a third of a flame's heat leaves as radiation, and a face beside it
  /// takes a third of that, with the hot gas the flame leans onto it.
  static const double _flankShare = 0.1;

  /// Joules the face a crate turns to a fire takes before it is burning:
  /// the first few millimetres of a crate's side brought to burning, and
  /// what it loses meanwhile. A smaller face takes less, as its area.
  static const double _flankCatches = 2.5e5;

  /// The flames of burning wood into the wood beside it.
  ///
  /// The core heats wood beside a fire by what the flame radiates from its
  /// middle, and a flame standing up out of a crate leaves a crate beside
  /// it, a hand's breadth off, warm a long while short of burning: it held
  /// at two hundred and fifty degrees through two minutes of a crate on
  /// fire beside it. A real crate's flames lean out of its sides and lick
  /// up what stands against them, which catches within a minute. So a
  /// share of each fire's heat goes into the face of each piece of wood
  /// within [_flankReach] of it, at that face, and once a face has taken
  /// what brings its skin to burning the wood is alight. A crate beside a
  /// burning one catches in about half a minute, a barrel in some forty
  /// seconds; what was not reached cools off as a skin does.
  void _flank(double dt) {
    final all = <_Wood>[..._wood, ..._pieces];
    final at = <Vector3>[for (final w in all) world.positionOf(w.body)];
    final burning = <bool>[for (final w in all) world.isBurning(w.body)];
    for (var j = 0; j < all.length; j++) {
      final to = all[j];
      to.flanked *= 1.0 - dt / 30.0;
      if (burning[j]) continue;
      for (var i = 0; i < all.length; i++) {
        if (i == j || !burning[i]) continue;
        final from = all[i];
        final off = at[i] - at[j];
        final d = off.length;
        final gap = d - from.reach - to.reach;
        if (gap > _flankReach || d < 1e-3) continue;
        final joules =
            world.heatReleaseOf(from.body) *
            _flankShare *
            (1.0 - math.max(gap, 0.0) / _flankReach) *
            dt;
        world.addHeatAt(to.body, at[j] + off * (to.reach / d), joules);
        to.flanked += joules;
      }
      final needs = _flankCatches * math.pow(to.reach / 0.4, 2);
      if (to.flanked > needs) {
        to.flanked = 0.0;
        world.setTemperature(to.body, _boards.ignitionTemperature + 60.0);
      }
    }
  }

  /// Wood standing in the vault's water is wet through, and a fire on it
  /// goes out.
  void _douse(double dt) {
    final vault = _vault;
    if (vault == null) return;
    for (final w in _wood.followedBy(_pieces)) {
      final p = world.positionOf(w.body);
      if (!vault.covers(p.x, p.z)) continue;
      final here = vault.at(p.x, p.z);
      if (here != null && here.depth > 0.05 && p.y - 0.3 < here.surface) {
        world.addWater(w.body, 4.0 * dt);
      }
    }
  }

  /// A crate burnt past what holds it together comes apart, still
  /// burning; a piece burnt out and cold is swept away after a while.
  void _burnOut(double dt) {
    for (final w in _wood.toList()) {
      if (world.fuelOf(w.body) > w.fuel * _holds) continue;
      if (!world.isBurning(w.body)) continue;
      _split(w, Vector3(0.0, 0.8, 0.0));
    }
    // A heap of boards burns as a few flames, not one a board: past
    // [_mostFlames], the oldest go down to embers.
    final alight = <_Wood>[
      for (final p in _pieces)
        if (world.isBurning(p.body)) p,
    ];
    for (final p in alight.take(math.max(0, alight.length - _mostFlames))) {
      world.addWater(p.body, 0.5 * dt);
    }
    for (final p in _pieces.toList()) {
      final out =
          !world.isBurning(p.body) && world.fuelOf(p.body) < p.fuel * 0.08;
      p.cold = out ? p.cold + dt : 0.0;
      if (p.cold > 20.0) {
        _pieces.remove(p);
        _remove(p);
      }
    }
  }

  void _sync(_Wood w) {
    final at = world.positionOf(w.body);
    final turn = world.orientationOf(w.body);
    for (final node in w.nodes) {
      node
        ..setPosition(at.x, at.y, at.z)
        ..setRotation(turn);
    }
  }

  static Vector4 get _charcoal => Vector4(0.05, 0.045, 0.04, 1.0);

  /// Each board's colour as far burnt as it is. The fire view chars a look
  /// by the share of the whole fuel gone, which a crate never reaches: it
  /// is apart long before. Charred here by the share of what holds it
  /// together, black by the time it gives.
  ///
  /// And glowing only where it has charred, through the grain of its boards
  /// — the look's glow is its picture — rather than the whole box lit
  /// orange as the fire view would have it.
  void _char() {
    for (final w in _wood.followedBy(_pieces)) {
      final burnt = w.fuel > 0 ? 1.0 - world.fuelOf(w.body) / w.fuel : 0.0;
      final share = math.min(1.0, burnt / (1.0 - _holds) * 1.1);
      final material = w.nodes.first.material
        ..baseColor.setFrom(w.fresh + (_charcoal - w.fresh) * share);
      final glow = world.isBurning(w.body)
          ? (0.15 + 0.85 * share) * (0.7 + 0.3 * _random.nextDouble())
          : 0.0;
      material.emissive.setValues(0.9 * glow, 0.22 * glow, 0.03 * glow);
    }
  }

  void _lightNearest(Vector3 eye) {
    NativeBody? nearest;
    var best = double.infinity;
    for (final w in _wood.followedBy(_pieces)) {
      if (!world.isBurning(w.body)) continue;
      final d = (world.positionOf(w.body) - eye).length2;
      if (d < best) {
        best = d;
        nearest = w.body;
      }
    }
    if (nearest == null) {
      _fire.light.intensity = 0.0;
      return;
    }
    final at = world.positionOf(nearest);
    _fire.light
      ..setPosition(at.x, at.y + 0.9, at.z)
      ..intensity = math.min(_fire.light.intensity, _brightest);
  }

  void dispose() {
    _clear();
    world.dispose();
    torchWorld.dispose();
  }
}
