/// Fire, water and loose wood in the shipped crypt, **as part of the run**:
/// every torch a burner the physics core feeds, crates and barrels standing
/// about the rooms that a rocket's blast throws, breaks and sets alight, that
/// light one another and char and fall apart as they burn, and the first
/// crypt's flooded vault — stepped in the simulation's own fixed step, from
/// what the step did, and saved with it.
///
/// **A library of its own beside `staging.dart`, and here rather than in the
/// application that draws it.** It was the dungeon's, and so the one run that
/// had it was the one on screen: [stage]'s headless runs, a tool playing the
/// crypt blind and the `.f3drun` verifier stood the level without it, and a
/// run recorded with the elements did not retrace there. Built here, the game
/// and every headless tool stand the same world from the same level, and a run
/// recorded in one replays in the other bit for bit. What draws it stays with
/// the game: it reads [CryptWorld.world] and writes nothing.
///
/// **It used to be a layer over the run that the run could not feel.** The
/// world was stepped on the frame's clock and fed with where the run had left
/// everybody, so a replay or a test could not tell it was there — and so the
/// water did not slow anyone and the fires burned nobody. Now the water at the
/// player's feet holds them back by what wading is measured to cost, and a
/// fire near them hurts by the heat it sends them. That makes it the run's:
/// [CryptWorld] is stepped by `GameSimulation.systems`, reads only what the
/// step did, and rides in the run's own snapshot as an entity of its
/// `EcsWorld` — so a rewind, a kill camera, a restore and a replay all put the
/// crates, the fires and the water back where they were, bit for bit.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_shooter/flutter3d_game_shooter.dart'
    show GameSimulation, ShotFired, ShotLanded, ShooterPhases;
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    show
        Actor,
        Brush,
        CollisionLayers,
        EntityDef,
        Fixture,
        GameAction,
        GameEvent,
        GameRandom,
        Level,
        LightFixture,
        StepPhase;
import 'package:vector_math/vector_math.dart';

import 'shooter_sample.dart' show SampleEntities;

/// What the crypt world's bodies are, as its collision filters see them.
abstract final class CryptLayer {
  /// The level's walls and floors, the vault's stones and the torches.
  static const int stone = 1;

  /// Crates, barrels and what is left of them.
  static const int wood = 2;

  /// The bodies standing in for the player and the monsters: they shove the
  /// wood and wade the water, and pass through the walls, which the run
  /// already keeps them out of.
  static const int walker = 4;
}

/// What a piece of wood in the crypt is: a crate or a barrel whole, or a
/// board or a stave of a broken one.
///
/// **Not an enum**, because this package is published and a closed list is a
/// promise somebody else's `switch` is written against: what draws the wood
/// asks which of these a piece is and keeps a look for anything else.
final class WoodKind {
  const WoodKind._(this.index, this.name);

  /// Where it is in [values]: what a save writes for it.
  final int index;

  /// What it is called in a sentence.
  final String name;

  static const WoodKind crate = WoodKind._(0, 'crate');
  static const WoodKind barrel = WoodKind._(1, 'barrel');
  static const WoodKind plank = WoodKind._(2, 'plank');
  static const WoodKind stave = WoodKind._(3, 'stave');

  /// Every kind, in the order a save numbers them.
  static const List<WoodKind> values = <WoodKind>[crate, barrel, plank, stave];

  @override
  String toString() => name;
}

/// A crate or a barrel, or a piece of one, in the crypt world.
final class CryptWood {
  CryptWood({
    required this.serial,
    required this.body,
    required this.kind,
    required this.size,
    required this.fuel,
    this.cold = 0.0,
  });

  /// A crate's side, m.
  static const double crateSize = 0.8;

  /// A barrel's radius at its ends and its height, m.
  static const double barrelRadius = 0.3, barrelHeight = 0.9;

  /// A broken crate's board and a broken barrel's stave, as boxes: their
  /// half-sizes, m. Fresh each time, so nobody scaling one moves the other.
  static Vector3 get plankHalf => Vector3(0.38, 0.06, 0.016);
  static Vector3 get staveHalf => Vector3(0.05, 0.44, 0.016);

  /// Its number in the crypt, never given twice in a level: what the look
  /// that draws it is kept by, since a body's handle can be handed out again
  /// after a rewind.
  final int serial;
  final NativeBody body;
  final WoodKind kind;

  /// How large a crate is beside a full one; one for anything else.
  final double size;

  /// The fuel it started with, kg.
  final double fuel;

  /// How long it has been burnt out, s, for a piece to be swept away.
  double cold;

  bool get barrel => kind == WoodKind.barrel || kind == WoodKind.stave;
  bool get piece => kind == WoodKind.plank || kind == WoodKind.stave;

  List<Object> _save() => <Object>[
    serial,
    body.raw,
    kind.index,
    size,
    fuel,
    cold,
  ];

  static CryptWood? _read(Object? row) {
    if (row is! List || row.length < 6) return null;
    final [serial, raw, kind, size, fuel, cold, ...] = row;
    if (serial is! num || raw is! num || kind is! num) return null;
    if (size is! num || fuel is! num || cold is! num) return null;
    final k = kind.toInt();
    if (k < 0 || k >= WoodKind.values.length) return null;
    return CryptWood(
      serial: serial.toInt(),
      body: NativeBody(raw.toInt()),
      kind: WoodKind.values[k],
      size: size.toDouble(),
      fuel: fuel.toDouble(),
      cold: cold.toDouble(),
    );
  }
}

/// A torch: the fixture, where its flame is, and the burner's body there.
final class CryptTorch {
  CryptTorch(this.fixture, this.head, this.at);

  final LightFixture fixture;
  final NativeBody head;
  final Vector3 at;

  /// Where the cup a torch's flame rises from sits on its bracket, in the
  /// fixture's own frame — local +z into the wall, turned by the entity's
  /// yaw — and how far over the cup the flame starts, m. The game's look
  /// hangs its cup here, so the flame it draws and the burner the core feeds
  /// are in one place.
  static Vector3 get cup => Vector3(0.0, 0.08, -0.24);
  static const double rise = 0.07;

  /// Where [fixture]'s flame is, if it is a torch's: [cup] turned by the
  /// entity's yaw about its position, and [rise] over it. Null for a lamp, a
  /// window, or anything that is not a light.
  ///
  /// **Worked out from the level, not read off the scene.** It was the drawn
  /// flame's world position, which a headless run has no scene to read; the
  /// sine and cosine are [Portable]'s, so the burner stands in the same place
  /// on every platform.
  static Vector3? flameOf(Fixture fixture) {
    if (fixture.mechanism is! LightFixture) return null;
    final type = fixture.entity.type;
    if (type == SampleEntities.lamp || type == SampleEntities.window) {
      return null;
    }
    final yaw = fixture.entity.yaw;
    final c = cup;
    final s = Portable.sin(yaw), k = Portable.cos(yaw);
    final p = fixture.position;
    return Vector3(
      p.x + c.x * k + c.z * s,
      p.y + c.y + rise,
      p.z - c.x * s + c.z * k,
    );
  }
}

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

/// The flooded vault's water in the crypt world: its plan, the liquid, and
/// the ground under each cell it was made over.
final class CryptVault {
  CryptVault._(this.plan, this.liquid, this.ground, this.stones);

  final FloodPlan plan;
  final NativeShallowLiquid liquid;

  /// The floor under each cell's middle, x fastest, m.
  final List<double> ground;

  /// The sill's and the ledge's bodies.
  final List<NativeBody> stones;

  /// A quarter of a metre a cell: a stride crosses three, and the room is
  /// forty by forty.
  static const double cell = 0.25;

  /// The culvert's ledge: how far it stands out from the east wall, how
  /// wide it is, and how high, m.
  static const double ledgeOut = 0.6, ledgeHalfWide = 0.7, ledgeTop = 1.1;

  /// The sill across the doorway, m: a little over the water.
  static const double sillTop = 0.32;

  /// What the culvert brings in and the sill lets out, m³/s: a steady
  /// spill of thirty litres a second, enough to keep a current across the
  /// room and a falls to hear, not a torrent throwing spray across it.
  static const double flow = 0.03;

  /// The drain under the sill, m²: a grate a hand and a half square, which
  /// passes the culvert's thirty litres a second under a head of about the
  /// water's depth, Q = 0.61·A·√(2gH).
  static const double drain = 0.0225;

  /// Dressed stone flags, Manning's n.
  static const double bed = 0.02;

  /// The sill's box and the ledge's, as (middle, half size).
  List<(Vector3, Vector3)> get blocks => <(Vector3, Vector3)>[
    (
      Vector3(plan.x0 - 0.5, sillTop / 2, (plan.doorZ0 + plan.doorZ1) / 2),
      Vector3(0.5, sillTop / 2, (plan.doorZ1 - plan.doorZ0) / 2),
    ),
    (
      Vector3(plan.x1 - ledgeOut / 2, ledgeTop / 2, plan.culvertZ),
      Vector3(ledgeOut / 2, ledgeTop / 2, ledgeHalfWide),
    ),
  ];

  /// Whether ([x], [z]) is over the vault's floor.
  bool covers(double x, double z) =>
      x > plan.x0 && x < plan.x1 && z > plan.z0 && z < plan.z1;
}

/// How much wading slows a walker, and how much heat hurts one: the two
/// laws the crypt's elements reach the run through, kept apart from the
/// world so each can be read and tested alone.
abstract final class CryptHarm {
  /// The fastest a walker gets through still or running water [depth] m
  /// deep moving at [flow] m/s, as a share of their speed on dry floor.
  ///
  /// **Postacchini and colleagues' law**: subjects asked to go as fast as
  /// they could through a laboratory flume managed V = 0.53·M^−0.19 m/s,
  /// where M = v²d/g + d²/2 is the water's specific force per unit width
  /// (Ishigaki and colleagues, 2009) — Postacchini et al., 36th Italian
  /// Congress of Hydraulics, 2018, and Bernardini et al., Energy Procedia
  /// 134, 2017, in the form Shirvani and colleagues use, arXiv:2004.10589,
  /// eq. 1; the same group's later flume runs cover 0.2 to 0.7 m (Bernardini
  /// et al., Safety Science 123, 2020). Against the 1.4 m/s of an ordinary
  /// walk on dry ground (Mohler et al., Exp. Brain Res. 181, 2007),
  /// knee-deep water at 0.35 m leaves 64 % of it; Li and colleagues
  /// measured 61 % for men at the same depth (Acta Polytechnica CTU
  /// Proceedings 57, 2026), which is the check. Shallow enough that the law
  /// gives more than a dry walk — under eleven centimetres of still water —
  /// it does not slow anyone.
  ///
  /// [g] is the gravity of the world the water is in, m/s² — the crypt
  /// passes its world's `gravityMagnitude` — and [standardGravity], the
  /// laboratory's, when a caller has no world to ask.
  static double wadingShare(
    double depth, {
    double flow = 0.0,
    double g = standardGravity,
  }) {
    if (depth <= 0.0) return 1.0;
    final m = flow * flow * depth / g + depth * depth / 2.0;
    // Portable, as everything the step reads is: `dart:math`'s pow differs
    // in its last bits from one platform to the next.
    final v = 0.53 * Portable.pow(m, -0.19);
    return math.min(1.0, v / _dryWalk);
  }

  /// An ordinary walk on dry floor, m/s (Mohler et al. 2007).
  static const double _dryWalk = 1.4;

  /// The heat a fire sends a body [far] m from the middle of its flame,
  /// W/m².
  ///
  /// **Modak's point source** (Combustion and Flame 29, 1977; the SFPE
  /// Handbook's): the radiant share of the power the fire gives off, χ_r·Q,
  /// spread over a sphere about the middle of its flame, χ_rQ/4πR². Close
  /// in the point source overstates without bound, and nothing is heated
  /// past what the flame's own soot radiates, σT⁴ at the [sootTemperature]
  /// the core reports: in the flame, that is the flux. The same law the
  /// platformer and the strategy game burn by: [FireExposure.flux].
  static double flux({
    required double power,
    required double radiantShare,
    required double sootTemperature,
    required double far,
  }) => FireExposure.flux(
    radiant: radiantShare * power,
    sootTemperature: sootTemperature,
    distanceSquared: far * far,
  );

  /// The share of the player's health a second at [flux] W/m² of radiant
  /// heat costs.
  ///
  /// **ISO 13571:2012**: at or under 2.5 kW/m² skin takes no harm however
  /// long (§8.4); over it, the time to a second-degree burn is
  /// t = 6.9·q^−1.56 minutes, q in kW/m² (eq. 7, after Wieczorek and
  /// Dembsey, J. Fire Prot. Eng. 11, 2001). A full dose is the whole of the
  /// player's health, and each second's share is summed, as the standard's
  /// fractional effective dose is. [FireExposure.burnDoseRate].
  static double dosePerSecond(double flux) => FireExposure.burnDoseRate(flux);

  /// The incident radiant flux at or under which skin takes no harm, W/m²
  /// (ISO 13571:2012, §8.4): [FireExposure.harmlessFlux].
  static const double harmless = FireExposure.harmlessFlux;
}

/// The crypt's elements, in the run.
final class CryptWorld {
  CryptWorld._(this.world, this._sim, this._collision, this._random);

  /// The crypt of [level] stood into [world] and hung on [sim]'s step and its
  /// snapshot — the one way the game and every headless tool stand it, so
  /// that both have the same world.
  ///
  /// [world] is first put back to [blank], the world as it was made, when
  /// one is given: a game that keeps one world for the whole run stands each
  /// level into it clean. A fresh world needs none. [collision] is the run's
  /// world the rays find floor and corners in, and [fixtures] what the level
  /// spawned — the torches among them burn, at [CryptTorch.flameOf]. Nothing
  /// is stood where the player starts. [world] is given [collision]'s world
  /// properties (`CollisionWorld.properties`): its gravity, air and wind.
  factory CryptWorld.stage({
    required NativeWorld world,
    required GameSimulation sim,
    required Level level,
    required CollisionWorld collision,
    required Iterable<Fixture> fixtures,
    Uint8List? blank,
  }) {
    if (blank != null) world.restore(blank);
    // The run's world, the level's laid over the game's — the crypt's fire,
    // water and dust fall and rise in the air its runner walks in, not in a
    // standard one of their own.
    world.applyProperties(collision.properties);
    final crypt = CryptWorld._(world, sim, collision, GameRandom(17));
    crypt
      .._dry = sim.player.body.tuning
      .._breaches = sim.breaches?.version ?? 0
      .._walls(sim.breaches?.brushes ?? level.brushes);
    final torches = <(LightFixture, Vector3)>[
      for (final fixture in fixtures)
        if (CryptTorch.flameOf(fixture) case final Vector3 flame)
          (fixture.mechanism! as LightFixture, flame),
    ];
    for (final (fixture, at) in torches) {
      crypt._torch(fixture, at);
    }
    final plan = FloodPlan.byLevel[level.name];
    if (plan != null) crypt.vault = crypt._flood(plan);
    crypt._place(level.name, level.entities, torches, sim.player.body.position);
    crypt._hang();
    return crypt;
  }

  /// The core's world the crypt is in: the run's, read by what draws it.
  final NativeWorld world;

  final GameSimulation _sim;
  final CollisionWorld _collision;

  /// The dice the crypt rolls as it breaks things, saved with it.
  final GameRandom _random;

  /// The player's own tuning on dry floor, which wading scales.
  late final MovementSettings _dry;

  /// The flooded vault, if this level floods.
  CryptVault? vault;

  /// The torches, in the order the level lists them.
  final List<CryptTorch> torches = <CryptTorch>[];

  /// Crates and barrels whole, and the pieces of broken ones.
  final List<CryptWood> wood = <CryptWood>[];
  final List<CryptWood> pieces = <CryptWood>[];

  List<NativeBody> _stone = <NativeBody>[];
  NativeBody? _player;
  final Map<int, NativeBody> _monsters = <int, NativeBody>{};
  int _breaches = 0;

  /// Whether the world has been restored since the last step.
  bool _restored = false;
  int _serial = 0;

  /// What the core said since the last [takeHeard]: splashes, falls. Not
  /// part of the run — what is heard of it — and so not saved.
  final List<NativeEvent> _heard = <NativeEvent>[];

  /// Where rounds struck wood since the last [takeStruck], and which way
  /// the face looked: for the splinters.
  final List<(Vector3, Vector3)> _struck = <(Vector3, Vector3)>[];

  /// The run's player walker, for whoever draws the wading.
  NativeBody? get playerWalker => _player;

  /// The events of the steps since the last call, oldest first.
  List<NativeEvent> takeHeard() {
    final taken = List<NativeEvent>.of(_heard);
    _heard.clear();
    return taken;
  }

  /// Where rounds struck wood since the last call.
  List<(Vector3, Vector3)> takeStruck() {
    final taken = List<(Vector3, Vector3)>.of(_struck);
    _struck.clear();
    return taken;
  }

  /// Kept no longer than this, for a run nobody is drawing.
  static const int _mostHeard = 512;

  // ---------------------------------------------------------- constants

  /// A crate's and a barrel's mass, kg: boards of pine with air inside, and
  /// staves round an empty barrel.
  static const double _crateMass = 26.0, _barrelMass = 32.0;

  /// A board or a stave, kg.
  static const double _pieceMass = 2.2;

  /// How many crates and barrels a level stands, and how many pieces of
  /// broken ones lie about before the oldest are swept away.
  static const int _mostWood = 22, _mostPieces = 36;

  /// The share of its fuel a crate holds together with: burnt past it, its
  /// boards come apart. A crate is thin boards and battens, and its joints
  /// go long before the wood does.
  static const double _holds = 0.85;

  /// What a torch burns: pitch and rag, burnt as wood is, a fifth of a gram
  /// a second — some three kilowatts, a flame a quarter of a metre long.
  static final NativeBurner _torchBurner = NativeBurner(
    fuel: NativeMaterial.wood(),
    rate: 2e-4,
  );

  /// A rocket's charge: half a kilogram of TNT.
  static const NativeExplosion _rocket = NativeExplosion.tnt(0.5);

  /// A rocket splits the wood within this share of its blast's radius: what
  /// stands that close is shattered, not thrown.
  static const double _splits = 0.35;

  /// The push one round gives a crate it passes through on its way, N·s:
  /// a pistol's nudges it, a shotgun's pellets together shove it.
  static const double roundPush = 9.0;

  // -------------------------------------------------------------- staging

  /// The level's brushes as fixed boxes, for the wood to stand and land on.
  void _walls(List<Brush> brushes) {
    for (final body in _stone) {
      world.removeBody(body);
    }
    _stone = <NativeBody>[
      for (final brush in brushes) _fixedBox(brush.center, brush.size / 2),
    ];
  }

  NativeBody _fixedBox(Vector3 at, Vector3 half) {
    final body = world.addBody(
      position: at,
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(body, NativeShape.box(half))
      ..setMaterial(body, NativeMaterial.stone())
      ..setCollisionFilter(
        body,
        layer: CryptLayer.stone,
        mask: CryptLayer.wood,
      );
    return body;
  }

  /// A head of pitch and rag where [fixture]'s flame is.
  void _torch(LightFixture fixture, Vector3 at) {
    if (at.length2 < 1e-6) return;
    final head = world.addBody(
      position: at,
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setShape(head, const NativeShape.cylinder(0.045, 0.06))
      ..setMaterial(head, NativeMaterial.stone())
      ..setCollisionFilter(
        head,
        layer: CryptLayer.stone,
        mask: CryptLayer.wood,
      );
    torches.add(CryptTorch(fixture, head, at.clone()));
  }

  /// [plan]'s room flooded: a hand's depth of water over the floor the
  /// run's own rays find, fed by the culvert and let out under the sill.
  CryptVault _flood(FloodPlan plan) {
    const cell = CryptVault.cell;
    final nx = ((plan.x1 - plan.x0) / cell).round();
    final nz = ((plan.z1 - plan.z0) / cell).round();
    final ground = <double>[
      for (var j = 0; j < nz; j++)
        for (var i = 0; i < nx; i++)
          _groundAt(
            plan,
            plan.x0 + (i + 0.5) * cell,
            plan.z0 + (j + 0.5) * cell,
          ),
    ];
    final liquid = world.createShallowLiquid(
      nx: nx,
      nz: nz,
      cell: cell,
      origin: Vector3(plan.x0, 0.0, plan.z0),
      ground: ground,
    );
    world
      // Fresh water as warm as the crypt's air: how it flows, and what heat
      // sees of it.
      ..setShallowProperties(liquid, _water)
      ..setShallowHeat(
        liquid,
        NativeLiquidHeat.water(temperature: world.airTemperature),
      )
      ..setShallowBed(liquid, roughness: CryptVault.bed)
      ..fillShallowLiquid(
        liquid,
        x0: plan.x0,
        z0: plan.z0,
        x1: plan.x1,
        z1: plan.z1,
        level: plan.level,
      )
      // The culvert's water wells up on its ledge and runs off its lip; a
      // drain under the sill lets out as much as the head over it drives
      // through, so the pool finds the level where the two are equal and a
      // slow current crosses the room.
      ..setShallowSource(
        liquid,
        0,
        x: plan.x1 - 0.2,
        z: plan.culvertZ,
        radius: 0.3,
        rate: CryptVault.flow,
      )
      ..setShallowOutlet(
        liquid,
        0,
        NativeOutlet.drain(
          x: plan.x0 + 0.3,
          z: (plan.doorZ0 + plan.doorZ1) / 2,
          invert: 0.0,
          area: CryptVault.drain,
        ),
      );
    final vault = CryptVault._(plan, liquid, ground, <NativeBody>[]);
    for (final (at, half) in vault.blocks) {
      vault.stones.add(_fixedBox(at, half));
    }
    return vault;
  }

  final RayHit _hit = RayHit();

  /// The floor under the middle of a cell, as the run's own walls and floor
  /// have it: the first thing straight down from shoulder height that faces
  /// up. A wall, or anything the ray starts inside, stands above the water.
  /// The culvert's ledge is the vault's own.
  double _groundAt(FloodPlan plan, double x, double z) {
    if ((x - plan.x1).abs() < CryptVault.ledgeOut &&
        (z - plan.culvertZ).abs() < CryptVault.ledgeHalfWide) {
      return CryptVault.ledgeTop;
    }
    final found = _collision.raycast(
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

  /// The first thing a ray from [from] along [along] meets within [far]
  /// that is the level's own stone, and how far off; [far] if nothing, and
  /// nought if it starts inside something.
  double _ray(Vector3 from, Vector3 along, double far) {
    if (!_collision.raycast(from, along, far, _hit)) return far;
    return _hit.collider?.kind == ColliderKind.static ? _hit.distance : 0.0;
  }

  /// The floor straight under [at], if the ray finds one facing up.
  double? _floor(Vector3 at) {
    if (!_collision.raycast(at, Vector3(0.0, -1.0, 0.0), 4.0, _hit)) {
      return null;
    }
    if (_hit.collider?.kind != ColliderKind.static || _hit.normal.y < 0.8) {
      return null;
    }
    return _hit.point.y;
  }

  static final List<Vector3> _round = List<Vector3>.unmodifiable(<Vector3>[
    Vector3(1.0, 0.0, 0.0),
    Vector3(-1.0, 0.0, 0.0),
    Vector3(0.0, 0.0, 1.0),
    Vector3(0.0, 0.0, -1.0),
  ]);

  /// Whether a crate of half-side [half] fits standing on the floor at [at]:
  /// floor under its corners at the same height, nothing within its sides,
  /// and room over it.
  bool _fits(Vector3 at, double half) {
    for (final (dx, dz) in const <(double, double)>[
      (1.0, 1.0),
      (1.0, -1.0),
      (-1.0, 1.0),
      (-1.0, -1.0),
    ]) {
      final y = _floor(
        Vector3(at.x + dx * half * 0.9, at.y + 1.0, at.z + dz * half * 0.9),
      );
      if (y == null || (y - at.y).abs() > 0.03) return false;
    }
    final middle = Vector3(at.x, at.y + 0.4, at.z);
    for (final d in _round) {
      if (_ray(middle, d, half + 0.02) < half + 0.02) return false;
    }
    return _ray(middle, Vector3(0.0, 1.0, 0.0), 2.0) >= 2.0;
  }

  /// The level's name as a seed the same on every platform: FNV-1a over
  /// its code units. `String.hashCode` is not — the VM's and a browser's
  /// differ — and the crates of a replay have to stand where the run's did.
  static int seedOf(String name) {
    var h = 0x811c9dc5;
    for (final unit in name.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Places the level's wood: by every other torch, a crate against the
  /// wall under it with a barrel on its other side; then into the room
  /// corners the rays find, a crate or two in each, well away from where
  /// anything the run places stands or opens; and two afloat in a flooded
  /// vault.
  void _place(
    String name,
    List<EntityDef> entities,
    List<(LightFixture, Vector3)> torches,
    Vector3 player,
  ) {
    // The same every time a level is entered: placed by its name.
    final random = GameRandom(seedOf(name));
    final keepOff = <Vector3>[
      player,
      for (final e in entities)
        if (_keptClearOf.contains(e.type)) e.position,
    ];
    final taken = <Vector3>[];
    bool clearOf(Vector3 at, double near) =>
        keepOff.every((p) => _flat(p, at) > 2.4) &&
        taken.every((p) => _flat(p, at) > near) &&
        !(vault?.covers(at.x, at.z) ?? false);

    // By the torches.
    for (final (i, (_, head)) in torches.indexed) {
      if (i.isOdd) continue;
      // The wall behind it: the nearest of four rays.
      final (wall, d) = _round
          .map((dir) => (dir, _ray(head, dir, 1.0)))
          .reduce((a, b) => a.$2 <= b.$2 ? a : b);
      if (d >= 1.0 || d <= 0.0) continue;
      final floor = _floor(head);
      if (floor == null) continue;
      final side = Vector3(-wall.z, 0.0, wall.x);
      final atWall = Vector3(head.x, floor, head.z) + wall * (d - 0.44);
      final crate = atWall + side * 0.95;
      final barrel = atWall - side * 0.9 + wall * 0.1;
      if (_fits(crate, 0.4) && clearOf(crate, 1.5)) {
        _crate(crate, turn: random.nextDouble() * 0.2 - 0.1);
        taken.add(crate);
      }
      if (_fits(barrel, 0.33) && clearOf(barrel, 0.9)) {
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
          final floor = _floor(Vector3(x, y + 1.2, z));
          if (floor == null) continue;
          final at = Vector3(x, floor + 0.4, z);
          if (_ray(at, Vector3(0.0, 1.0, 0.0), 2.0) < 2.0) continue;
          final dx = <(Vector3, double)>[
            for (final dir in _round.take(2)) (dir, _ray(at, dir, 1.3)),
          ].reduce((a, b) => a.$2 <= b.$2 ? a : b);
          final dz = <(Vector3, double)>[
            for (final dir in _round.skip(2)) (dir, _ray(at, dir, 1.3)),
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
          if (_ray(alongX, dx.$1, 0.6) >= 0.6 ||
              _ray(alongZ, dz.$1, 0.6) >= 0.6) {
            continue;
          }
          if (!_fits(spot, 0.4)) continue;
          corners.add((spot, dx.$1, dz.$1));
        }
      }
    }
    corners.shuffle(random);
    var clusters = 0;
    for (final (spot, wx, wz) in corners) {
      if (clusters >= 5 || wood.length >= _mostWood - 3) break;
      if (!clearOf(spot, 4.0)) continue;
      clusters++;
      taken.add(spot);
      _crate(spot, turn: random.nextDouble() * 0.3 - 0.15);
      // A second on it, now and then, and a barrel or a smaller crate
      // along one of the walls.
      if (random.nextBool()) {
        _crate(
          spot + Vector3(0.03, CryptWood.crateSize, -0.02),
          turn: random.nextDouble() * 0.6 - 0.3,
        );
      }
      final along = random.nextBool() ? -wx : -wz;
      final next = spot + along * 0.85;
      if (_fits(next, 0.33)) {
        if (random.nextBool()) {
          _barrel(next + (along.x != 0 ? wz : wx) * 0.08);
        } else {
          _crate(next, turn: random.nextDouble() * 0.4, size: 0.75);
        }
        taken.add(next);
      }
    }

    // Afloat in the vault: a crate and a barrel that came in with the water.
    final flooded = vault;
    if (flooded != null) {
      final p = flooded.plan;
      _crate(Vector3(p.x0 + 6.5, p.level + 0.1, p.z0 + 2.4), turn: 0.5);
      _barrel(Vector3(p.x0 + 3.2, p.level + 0.05, p.z1 - 2.0), lying: true);
    }
  }

  /// What the run places that no crate is stood near.
  static const Set<String> _keptClearOf = <String>{
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
  };

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
    const side = CryptWood.crateSize;
    final half = side / 2 * size;
    final extent = Vector3.all(half);
    _add(
      NativeShape.box(extent),
      mass:
          8.0 *
          extent.x *
          extent.y *
          extent.z *
          (_crateMass / (side * side * side)),
      kind: WoodKind.crate,
      size: size,
      at: Vector3(at.x, at.y + half, at.z),
      turn: _turn(Vector3(0, 1, 0), turn),
    );
  }

  /// A turn of [angle] about the unit [axis], with the sine and cosine the
  /// same on every platform — `Quaternion.axisAngle` asks `dart:math`, whose
  /// last bits differ between the VM and a browser, and a crate turned by a
  /// hair lands elsewhere when it falls.
  static Quaternion _turn(Vector3 axis, double angle) {
    final s = Portable.sin(angle / 2.0);
    return Quaternion(
      axis.x * s,
      axis.y * s,
      axis.z * s,
      Portable.cos(angle / 2.0),
    );
  }

  /// A barrel standing at [at], or on its side.
  void _barrel(Vector3 at, {bool lying = false}) {
    const half = CryptWood.barrelHeight / 2;
    const radius = CryptWood.barrelRadius + 0.03;
    const volume = math.pi * radius * radius * 2.0 * half;
    _add(
      const NativeShape.cylinder(radius, half),
      mass: volume * (_barrelMass / volume),
      kind: WoodKind.barrel,
      at: Vector3(
        at.x,
        at.y + (lying ? CryptWood.barrelRadius + 0.04 : half),
        at.z,
      ),
      turn: lying ? _turn(Vector3(1, 0, 0), math.pi / 2) : null,
    );
  }

  /// A body of [shape] and [mass] at [at], moving at [velocity], as wood of
  /// [kind].
  CryptWood _add(
    NativeShape shape, {
    required double mass,
    required WoodKind kind,
    required Vector3 at,
    double size = 1.0,
    Quaternion? turn,
    Vector3? velocity,
  }) {
    final body = world.addBody(position: at, mass: mass);
    world
      ..setShape(body, shape)
      ..setMaterial(body, NativeMaterial.wood())
      ..setFriction(
        body,
        kind == WoodKind.plank || kind == WoodKind.stave ? 0.8 : 0.7,
      )
      ..setCollisionFilter(
        body,
        layer: CryptLayer.wood,
        mask: CryptLayer.stone | CryptLayer.wood | CryptLayer.walker,
      );
    if (turn != null) world.setOrientation(body, turn);
    if (velocity != null) world.setVelocity(body, velocity);
    final made = CryptWood(
      serial: _serial++,
      body: body,
      kind: kind,
      size: size,
      fuel: world.fuelOf(body),
    );
    (made.piece ? pieces : wood).add(made);
    return made;
  }

  // ----------------------------------------------------------- the step

  /// Hung on the run: the wading's drag read before the player moves, the
  /// heat's harm after the monsters have had their turn, and the world
  /// stepped at the end with everything the step did; saved and restored
  /// with the run's own entities.
  void _hang() {
    final systems = _sim.systems;
    systems
      ..add(StepPhase.begin, (step) => _wade(step.dt), label: 'crypt: wading')
      ..add(
        ShooterPhases.afterActors,
        (step) => _burn(step.dt),
        label: 'crypt: heat',
      )
      ..add(StepPhase.end, (step) => _step(step.dt), label: 'crypt: world');
    final entities = _sim.entities;
    if (entities == null) return;
    entities.components.register<CryptWorld>(
      InPlaceCodec<CryptWorld>.of(
        id: 'crypt',
        encode: (crypt) => crypt._save(),
        restore: (crypt, data, _) => crypt._restore(data),
      ),
    );
    entities.set(entities.spawn(), this);
  }

  /// The water where [x], [z] is, or null where there is none.
  NativeShallowSample? waterAt(double x, double z) {
    final flooded = vault;
    if (flooded == null || !flooded.covers(x, z)) return null;
    return world.sampleShallow(flooded.liquid, x, z);
  }

  /// How deep the water stands over the player's feet, m, and how fast it
  /// runs past them.
  ///
  /// **The surface over the feet, not the column's depth.** Where a body
  /// stands in the water the core's column holds only the water beside it,
  /// half the depth round it as measured walking through the vault, while
  /// the surface stands where the water round the shins does; and where it
  /// is dry the surface is the floor, so nothing is waded.
  ({double depth, double flow}) wadingOf(Vector3 center, double halfHeight) {
    final here = waterAt(center.x, center.z);
    if (here == null) return (depth: 0.0, flow: 0.0);
    final feet = center.y - halfHeight;
    final over = math.max(0.0, here.surface - feet);
    final flow = math.sqrt(here.flowX * here.flowX + here.flowZ * here.flowZ);
    return (depth: over, flow: flow);
  }

  /// The player's speed on the floor held back by the water they stand in.
  ///
  /// The tuning's top speeds are what the controller accelerates towards,
  /// and it never brakes a body already going faster while it is asked to
  /// go on — so a player who runs in from the dry floor would keep their
  /// dry speed through the whole vault. What takes the excess off is the
  /// water's drag on the shins: two cylinders [_shin] across, as deep in it
  /// as the water is, ½ρC_dAv² with C_d = 1.1 for a cylinder across the
  /// flow (Hoerner, Fluid-Dynamic Drag, 1965), on a body of [_walkerMass].
  /// At six metres a second in a hand of water that is about a kilonewton,
  /// and the walker is down to the water's pace in a tenth of a second.
  void _wade(double dt) {
    final body = _sim.player.body;
    final (:depth, :flow) = wadingOf(body.position, body.halfExtents.y);
    final share = CryptHarm.wadingShare(
      depth,
      flow: flow,
      g: world.gravityMagnitude,
    );
    final tuning = share >= 1.0
        ? _dry
        : _dry.copyWith(
            walkSpeed: _dry.walkSpeed * share,
            sprintSpeed: _dry.sprintSpeed * share,
          );
    body.tuning = tuning;
    if (share >= 1.0 || !body.isGrounded) return;
    final top = _sim.input.held(GameAction.sprint)
        ? tuning.sprintSpeed
        : tuning.walkSpeed;
    final v = body.velocity;
    final speed = math.sqrt(v.x * v.x + v.z * v.z);
    if (speed <= top) return;
    final drag =
        _water.density *
        _shinDrag *
        _shin *
        depth *
        speed *
        speed /
        _walkerMass;
    final slowed = math.max(top, speed - drag * dt);
    v
      ..x *= slowed / speed
      ..z *= slowed / speed;
  }

  /// What the vault is flooded with: what the core flows and what the
  /// shins are dragged by, one preset for both.
  static final NativeLiquidProperties _water = NativeLiquidProperties.water;

  /// A cylinder's drag across the flow at a shin's Reynolds number, some
  /// 10⁵ (Hoerner 1965).
  static const double _shinDrag = 1.1;

  /// A shin's breadth, m: the calf's girth over π, 0.39 m the mean for men
  /// in the US Army's ANSUR II survey (Gordon et al., 2014).
  static const double _shin = 0.124;

  /// The walker's mass, kg: the mean for men that Shirvani and colleagues
  /// take for the subjects of the wading law (Moody, 2012).
  static const double _walkerMass = 84.0;

  /// What the fires send the player this step, W/m² from each, summed.
  double heatOnPlayer() {
    final body = _sim.player.body;
    final center = body.position;
    final half = body.halfExtents;
    var total = 0.0;
    for (final fire in world.fires()) {
      final middle = fire.at + fire.axis * (fire.reach / 2.0);
      // The nearest of the player's body to the flame's middle: a standing
      // column from their feet to the top of their head.
      final y = middle.y.clamp(center.y - half.y, center.y + half.y);
      final nearest = Vector3(center.x, y, center.z);
      final along = nearest - middle;
      final apart = along.length;
      final far = math.max(0.0, apart - half.x);
      // A wall between them takes it all.
      if (apart > 1e-6 &&
          _collision.raycast(
            middle,
            along / apart,
            apart,
            _hit,
            mask: CollisionLayers.world,
          ) &&
          _hit.collider?.kind == ColliderKind.static) {
        continue;
      }
      total += CryptHarm.flux(
        power: fire.power,
        radiantShare: fire.radiantShare,
        sootTemperature: fire.sootTemperature,
        far: far,
      );
    }
    return total;
  }

  /// The heat the fires send the player, as harm: the share of what
  /// incapacitates that this step's dose is, of their whole health — the
  /// dose that stops a person is the one that ends the run. Through
  /// `GameSimulation.hurtPlayer`, so the difficulty scales it and the run
  /// hears it as it hears every other harm to the player.
  void _burn(double dt) {
    final player = _sim.player;
    if (!player.isAlive) return;
    final dose = CryptHarm.dosePerSecond(heatOnPlayer()) * dt;
    if (dose <= 0.0) return;
    _sim.hurtPlayer(dose * player.inventory.health.maximum);
  }

  /// The world one step on: the walls as the rockets have cut them, the
  /// step's blasts and shots acted on, the walkers carried to where the
  /// step left them, the torches fed, then stepped, and what has burnt
  /// past holding together broken up.
  void _step(double dt) {
    final breaches = _sim.breaches;
    if (breaches != null && breaches.version != _breaches) {
      // A restore counts as a change to the breaches, which it is for what
      // draws the walls; the stone here came back with the snapshot, cut as
      // the breaches it was saved beside, and is left as it is.
      if (!_restored) _walls(breaches.brushes);
      _breaches = breaches.version;
    }
    _restored = false;
    final projectiles = _sim.projectiles;
    if (projectiles != null) {
      for (final blast in projectiles.detonations) {
        _applyBlast(blast.position, blast.blast.radius);
      }
    }
    _shots();
    _walk(dt);
    for (final t in torches) {
      world.setBurner(t.head, t.fixture.enabled ? _torchBurner : null);
    }
    world.step(dt);
    _heard.addAll(world.readEvents());
    if (_heard.length > _mostHeard) {
      _heard.removeRange(0, _heard.length - _mostHeard);
    }
    _burnOut(dt);
  }

  /// The player's shot this step, read off `GameSimulation.shotEvents`: each
  /// round pushes the first crate or barrel on its way to where it landed.
  void _shots() {
    Vector3? from;
    for (final GameEvent event in _sim.shotEvents) {
      switch (event) {
        case ShotFired():
          from = event.from;
        case ShotLanded(:final hit) when from != null:
          _applyShot(from, hit.point, roundPush);
      }
    }
  }

  /// A rocket's charge going off at [at]: the core pushes and heats what it
  /// reaches as the charge's products and heat reach it; what stood within
  /// [_splits] of the blast's [radius] is shattered.
  void _applyBlast(Vector3 at, double radius) {
    for (final w in wood.toList()) {
      final p = world.localPositionOf(w.body);
      if ((p - at).length < radius * _splits) _split(w);
    }
    world.explode(at, _rocket);
  }

  void _applyShot(Vector3 from, Vector3 to, double push) {
    final along = to - from;
    final far = along.length;
    if (far < 1e-3) return;
    along.scale(1.0 / far);
    final hit = world.rayCast(from, along, far, mask: CryptLayer.wood);
    if (hit == null) return;
    world
      ..applyImpulse(hit.body, along * push, at: hit.point)
      ..wake(hit.body);
    _struck.add((hit.point, hit.normal));
    if (_struck.length > _mostHeard) _struck.removeAt(0);
  }

  /// A crate or a barrel in pieces: its boards or staves where it stood,
  /// moving as it moved and as hot as it was.
  void _split(CryptWood w) {
    final native = w.body;
    final p = world.localPositionOf(native);
    final turn = world.orientationOf(native);
    final moving = world.velocityOf(native);
    final kelvin = world.surfaceTemperatureOf(native);
    world.removeBody(native);
    wood.remove(w);
    final count = w.barrel ? 7 : 6;
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count + _random.nextDouble() * 0.5;
      final spread = Vector3(
        Portable.cos(a),
        0.4 + _random.nextDouble(),
        Portable.sin(a),
      );
      final half = w.barrel ? CryptWood.staveHalf : CryptWood.plankHalf;
      final volume = 8.0 * half.x * half.y * half.z;
      final piece = _add(
        NativeShape.box(half),
        mass: volume * (_pieceMass / volume),
        kind: w.barrel ? WoodKind.stave : WoodKind.plank,
        at: p + spread * 0.25,
        turn:
            turn *
            _turn(
              Vector3(_random.nextDouble(), 1.0, _random.nextDouble())
                ..normalize(),
              _random.nextDouble() * math.pi,
            ),
        velocity: moving,
      );
      // Each board leaves as hot as the face it was part of: what that sets
      // alight, the core decides.
      world.setTemperature(piece.body, kelvin);
    }
    while (pieces.length > _mostPieces) {
      world.removeBody(pieces.removeAt(0).body);
    }
  }

  /// A crate burnt past what holds it together comes apart, still
  /// burning; a piece burnt out and cold is swept away after a while.
  void _burnOut(double dt) {
    for (final w in wood.toList()) {
      if (world.fuelOf(w.body) > w.fuel * _holds) continue;
      if (!world.isBurning(w.body)) continue;
      _split(w);
    }
    for (final p in pieces.toList()) {
      final out =
          !world.isBurning(p.body) && world.fuelOf(p.body) < p.fuel * 0.08;
      p.cold = out ? p.cold + dt : 0.0;
      if (p.cold > 20.0) {
        pieces.remove(p);
        world.removeBody(p.body);
      }
    }
  }

  /// The player and the living monsters followed: each a capsule carried
  /// over the step to where the run has it, or put there outright if it
  /// has fallen far behind — a teleport, a respawn. The dead are let go.
  void _walk(double dt) {
    _player = _follow(_player, _sim.player.body.position, dt, radius: 0.3);
    final seen = <int>{};
    for (final actor in _sim.actors?.actors ?? const <Actor>[]) {
      final at = actor.position;
      if (at == null || !actor.isAlive) continue;
      final key = actor.ordinal;
      seen.add(key);
      _monsters[key] = _follow(_monsters[key], at, dt, radius: 0.4);
    }
    _monsters.removeWhere((key, body) {
      if (seen.contains(key)) return false;
      world.removeBody(body);
      return true;
    });
  }

  NativeBody _follow(
    NativeBody? walker,
    Vector3 at,
    double dt, {
    required double radius,
  }) {
    if (walker == null || !world.contains(walker)) {
      final body = world.addBody(position: at, type: NativeBodyType.kinematic);
      world
        ..setShape(body, NativeShape.capsule(radius, 0.55))
        ..setCollisionFilter(
          body,
          layer: CryptLayer.walker,
          mask: CryptLayer.wood,
        );
      return body;
    }
    if ((world.localPositionOf(walker) - at).length > 1.0) {
      world
        ..setPosition(walker, at)
        ..setOrientation(walker, Quaternion.identity())
        ..setVelocity(walker, Vector3.zero())
        ..setAngularVelocity(walker, Vector3.zero());
    } else {
      world.moveKinematic(walker, at, Quaternion.identity(), dt);
    }
    return walker;
  }

  // ------------------------------------------------------------- saving

  Map<String, Object?> _save() => <String, Object?>{
    'core': base64Encode(world.snapshot()),
    'random': _random.state,
    'serial': _serial,
    'stone': <int>[for (final body in _stone) body.raw],
    'player': _player?.raw,
    'monsters': <List<int>>[
      for (final MapEntry(:key, :value) in _monsters.entries)
        <int>[key, value.raw],
    ],
    'wood': <List<Object>>[for (final w in wood) w._save()],
    'pieces': <List<Object>>[for (final p in pieces) p._save()],
  };

  /// Back to what [_save] wrote. A snapshot the core will not take — one
  /// from another build of it — leaves the crypt as it is.
  void _restore(Object? data) {
    if (data is! Map) return;
    final core = data['core'];
    if (core is! String) return;
    try {
      world.restore(base64Decode(core));
    } on ArgumentError {
      return;
    } on FormatException {
      return;
    }
    int integer(Object? value, int otherwise) =>
        value is num ? value.toInt() : otherwise;
    _random.state = integer(data['random'], _random.state);
    _serial = integer(data['serial'], _serial);
    _restored = true;
    _stone = <NativeBody>[
      if (data['stone'] case final List<Object?> raws)
        for (final raw in raws)
          if (raw is num) NativeBody(raw.toInt()),
    ];
    _player = switch (data['player']) {
      final num raw => NativeBody(raw.toInt()),
      _ => null,
    };
    _monsters
      ..clear()
      ..addAll(<int, NativeBody>{
        if (data['monsters'] case final List<Object?> rows)
          for (final row in rows)
            if (row case [final num key, final num raw])
              key.toInt(): NativeBody(raw.toInt()),
      });
    List<CryptWood> rows(Object? list) => <CryptWood>[
      if (list case final List<Object?> all)
        for (final row in all) ?CryptWood._read(row),
    ];
    wood
      ..clear()
      ..addAll(rows(data['wood']));
    pieces
      ..clear()
      ..addAll(rows(data['pieces']));
    _heard.clear();
    _struck.clear();
  }
}
