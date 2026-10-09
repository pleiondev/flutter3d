/// The level's water, molten metal and fire as part of the run: a world of
/// the physics core's own, built from the level document and stepped in the
/// run's fixed step, with the runner held up and held back by the water it
/// stands in and hurt by the fires it stands beside.
///
/// **In the run, not beside it.** Until 0.9 the elements were a world the
/// game stepped by the wall clock and never wrote back from, so a raft held
/// nobody up and a brazier burnt nobody; a replay could only stay true by
/// leaving them out of it. Now this world is stepped in the run's fixed
/// step — in the engine loop's `elements` phase, after the genre's step
/// ([stepElements]) — and its whole state goes into the run's snapshot as one
/// of the simulation's parts ([elementsPart]). A replay, a rewind, a shared
/// run's ghost and a test each step it to the same bits, because each of
/// them stages the level through `stage` and steps it through `Staged.step`.
///
/// Until the engine loop it rode inside the run's dynamics, stepped where
/// `WorldStep.index` steps the bodies, just before the runner moved. Now it
/// steps after the whole of the genre's step: the runner wades and burns in
/// the water and the fires of the step before, and a tape recorded before the
/// move does not replay to the same bits.
///
/// Nothing here needs a graphics device: `elements.dart` draws this world,
/// which is all it does with it.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter3d_effects/flutter3d_effects.dart'
    show Liquid, LiquidOptics;
import 'package:flutter3d_elements/flutter3d_elements.dart'
    show Bed, Igniter, Solid;
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'dressing.dart';

/// One pit's liquid, as the run has it and the drawing reads it.
final class RunPool {
  RunPool._({
    required this.name,
    required this.liquid,
    required this.ground,
    required this.surface,
    required this.molten,
    required this.center,
    required this.half,
    required this.pours,
    required this.sills,
    required this.density,
  });

  final String name;

  /// The core's liquid.
  final NativeShallowLiquid liquid;

  /// The ground under it, one height a cell, x fastest.
  final List<double> ground;

  /// The height it was filled to, m.
  final double surface;
  final bool molten;

  /// The pit's box: its middle and half its size.
  final Vector3 center, half;

  /// What pours into it, and the height each culvert's water runs at, m.
  final List<Pour> pours;
  final List<double> sills;

  /// kg/m³, what the liquid holds a body up by.
  final double density;

  /// Whether ([x], [z]) lies over its grid.
  bool covers(double x, double z) {
    final o = liquid.origin;
    return x >= o.x &&
        z >= o.z &&
        x <= o.x + liquid.nx * liquid.cell &&
        z <= o.z + liquid.nz * liquid.cell;
  }
}

/// A piece of wood afloat: a [raft] of three logs or a plank, put in
/// turned by [turn].
typedef RunAfloat = ({NativeBody body, bool raft});

/// A bed of burning coal: in a brazier standing at [at], or a heap lying
/// at [at] on a floor.
typedef RunBed = ({NativeBody body, Vector3 at, bool brazier});

/// The elements of a level in the run.
final class RunElements {
  RunElements._(this.world, this._runner);

  /// The core's world the water and the fires are in. The run's own; a
  /// drawing copies it rather than stepping it.
  final NativeWorld world;

  final Runner _runner;

  final List<RunPool> pools = <RunPool>[];
  final List<RunAfloat> afloat = <RunAfloat>[];
  final List<RunBed> beds = <RunBed>[];
  final List<({NativeBody body, Vector3 Function() at})> _followers =
      <({NativeBody body, Vector3 Function() at})>[];

  /// Torches held to the heaps as the level opens, and how long each is
  /// still held, s: run state, saved with the world.
  final List<({NativeBody body, Vector3 at})> _torches =
      <({NativeBody body, Vector3 at})>[];
  final List<double> _torchLeft = <double>[];

  /// How many steps this world has taken: for a drawing, to know when it
  /// has something new to copy.
  int get steps => _steps;
  int _steps = 0;

  final List<NativeEvent> _events = <NativeEvent>[];
  int _unread = 0;

  /// What happened in the world since the last call — splashes, the falls'
  /// roar — for whatever hears it. A second's worth at most is kept for a
  /// run nobody listens to.
  List<NativeEvent> takeEvents() {
    final taken = List<NativeEvent>.of(_events);
    _events.clear();
    _unread = 0;
    return taken;
  }

  /// The elements of [level] — what its [Dressing] names, in the pits its
  /// [mechanisms] put there — or null for a level dressed in nothing.
  /// [runner] is who wades and burns.
  static RunElements? build(
    Level level,
    MechanismWorld mechanisms,
    Runner runner,
  ) {
    final dressing = Dressing.of(level.name);
    if (dressing.isEmpty) return null;
    final elements = RunElements._(NativeWorld(), runner)
      .._stage(level, mechanisms, dressing);
    return elements;
  }

  // ------------------------------------------------------------ building

  /// No more cells than this to a pool at half a metre a cell; a bigger
  /// pool is stepped a metre a cell. **The same on every machine**: the
  /// grid is part of the run now, and a phone stepping coarser water than
  /// the desktop would be playing another run.
  static const int _mostCells = 6000;

  /// How far past a pit's box its grid reaches, m, so the bank is in it.
  static const double _margin = 1.0;

  /// Collision layers: the level's stone, the followers, the wood. A
  /// follower pushes the wood and goes through stone.
  static const int _stone = 1, _following = 2, _wood = 4;

  /// The pits' and culverts' beds: cemented rubble masonry, Manning's n of
  /// 0.025 (Chow, Open-Channel Hydraulics, 1959, table 5-6).
  static const Bed _rubble = Bed(roughness: 0.025);

  /// Cistern water: green over stone, dark where it is deep. It takes
  /// 1.204 of every channel a metre, −ln 0.3: three tenths of the light
  /// gets through a metre of it, grey murk the backscatter then tints
  /// green, where clear water would keep three quarters of the red.
  static final Liquid _water = Liquid.water().copyWith(
    optics: LiquidOptics(
      absorb: Vector3.all(1.204),
      backscatter: Vector3(0.01833, 0.07685, 0.09062),
    ),
  );

  /// The foundry's metal: flowing as molten basalt does, as hot as a melt
  /// tapped from a furnace, about 1450 K.
  static final Liquid metal = Liquid(
    properties: NativeLiquidProperties.moltenBasalt,
    optics: LiquidOptics(
      absorb: Vector3.all(13.82),
      backscatter: Vector3(0.5756, 0.2104, 0.1114),
    ),
    heat: const NativeLiquidHeat(
      temperature: 1450.0,
      specificHeat: 1200.0,
      conductivity: 1.5,
      expansion: 3e-5,
    ),
    glow: Vector3(1.3, 0.3, 0.04),
  );

  /// Cistern water, as the drawing colours it.
  static Liquid get water => _water;

  /// A brazier kept fed: split wood burnt at two grams a second, about
  /// thirty kilowatts.
  static final NativeBurner _tending = NativeBurner(
    fuel: NativeMaterial.wood(),
    rate: 0.002,
  );

  /// A torch held to a heap of coal to light it: a small flame's flux
  /// against a hand's breadth of it, for a minute.
  static const Igniter _torch = Igniter(
    flux: 5e4,
    area: 0.01,
    temperature: 1300.0,
    seconds: 60.0,
  );

  /// Where a brazier's bowl stands over its feet, m.
  static const double bowlAt = 0.92;

  void _stage(Level level, MechanismWorld mechanisms, Dressing dressing) {
    final brushes = <Brush>[
      for (final b in level.brushes)
        if (b.solid) b,
    ];
    for (final mechanism in mechanisms.all) {
      final (name, collider) = switch (mechanism) {
        Hazard(:final name, :final collider) => (name, collider),
        Water(:final name, :final collider) => (name, collider),
        _ => (null, null),
      };
      final box = collider?.shape;
      if (collider == null || box is! CollisionBox) continue;
      final center = collider.position.clone();
      final half = box.halfExtents.clone();
      final (surface, hot) = switch (mechanism) {
        // Water the run swims in is filled to its top.
        Water() => (center.y + half.y - 0.05, false),
        _ => switch ((dressing.water[name], dressing.molten[name])) {
          (final double cold?, _) => (cold, false),
          (_, final double hot?) => (hot, true),
          _ => (null, false),
        },
      };
      if (surface == null) continue;
      pools.add(
        _pool(
          name ?? 'water',
          center,
          half,
          surface: surface,
          molten: hot,
          pours: <Pour>[
            for (final s in dressing.spills)
              if (s.into == name) s,
          ],
          brushes: brushes,
        ),
      );
    }
    _stoneAbout(brushes);
    _float(dressing);
    _follow(mechanisms);
    for (final (x, y, z) in dressing.braziers) {
      // The body that burns stands just over the coal in the bowl and
      // narrower than it: a flame is drawn from where the core says the
      // fire is.
      final body = _bed(
        Vector3(x, y + bowlAt + 0.36, z),
        Vector3(0.22, 0.06, 0.22),
      );
      world.setBurner(body, _tending);
      beds.add((body: body, at: Vector3(x, y, z), brazier: true));
    }
    for (final (x, y, z) in dressing.heaps) {
      final center = Vector3(x, y + 0.3, z);
      final body = _bed(center, Vector3(0.42, 0.3, 0.42));
      _torches.add((body: body, at: center));
      _torchLeft.add(_torch.seconds);
      beds.add((body: body, at: Vector3(x, y, z), brazier: false));
    }
  }

  /// A pit's grid: the box's footprint and a margin of bank, reaching up
  /// onto the ledges its [pours] well up on; the ground the level's
  /// [brushes] stand at; filled to [surface], with a weir in its far corner
  /// letting out what its springs pour in.
  RunPool _pool(
    String name,
    Vector3 center,
    Vector3 half, {
    required double surface,
    required bool molten,
    required List<Pour> pours,
    required List<Brush> brushes,
  }) {
    final (vx0, vz0) = (center.x - half.x, center.z - half.z);
    final (vx1, vz1) = (center.x + half.x, center.z + half.z);
    final x0 = pours.fold(vx0 - _margin, (m, s) => math.min(m, s.x - 2.0));
    final z0 = pours.fold(vz0 - _margin, (m, s) => math.min(m, s.z - 2.0));
    final x1 = pours.fold(vx1 + _margin, (m, s) => math.max(m, s.x + 2.0));
    final z1 = pours.fold(vz1 + _margin, (m, s) => math.max(m, s.z + 2.0));
    final cell = (x1 - x0) * (z1 - z0) / 0.25 <= _mostCells ? 0.5 : 1.0;
    final nx = ((x1 - x0) / cell).ceil(), nz = ((z1 - z0) / cell).ceil();
    final bottom = center.y - half.y;
    // What stands up from the floor counts as ground; what hangs over the
    // pit — a lintel, a shelf — does not, or the water would stop under it.
    final reach = center.y + half.y + 0.5;
    final ground = <double>[
      for (var j = 0; j < nz; j++)
        for (var i = 0; i < nx; i++)
          groundAt(
            x0 + (i + 0.5) * cell,
            z0 + (j + 0.5) * cell,
            brushes,
            floor: bottom,
            reach: reach,
          ),
    ];
    // Each spill runs to the nearest point of the pit's edge down a culvert
    // under the ledge, so it falls in one stream instead of spreading over
    // the floor.
    final sills = <double>[];
    for (final s in pours) {
      final lip = Vector2(s.x.clamp(vx0, vx1), s.z.clamp(vz0, vz1));
      final from = Vector2(s.x, s.z);
      final top = groundAt(s.x, s.z, brushes, floor: bottom, reach: reach);
      for (var j = 0; j < nz; j++) {
        for (var i = 0; i < nx; i++) {
          final p = Vector2(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell);
          final k = i + j * nx;
          if (ground[k] > surface &&
              _toSegment(p, from, lip) < (s.width + cell) / 2) {
            ground[k] = math.min(ground[k], top - s.culvert);
          }
        }
      }
      sills.add(top - s.culvert);
    }
    final liquid = molten ? metal : _water;
    final native = world.createShallowLiquid(
      nx: nx,
      nz: nz,
      cell: cell,
      origin: Vector3(x0, 0.0, z0),
      ground: ground,
    );
    world
      ..setShallowProperties(native, liquid.properties)
      ..setShallowHeat(native, liquid.heat)
      ..setShallowBed(native, roughness: _rubble.roughness)
      ..fillShallowBasin(native, x: center.x, z: center.z, level: surface);
    for (final (k, s) in pours.indexed) {
      world.setShallowSource(
        native,
        k,
        x: s.x,
        z: s.z,
        radius: 0.4,
        rate: s.rate,
      );
    }
    // A weir four metres wide in the corner of the pit furthest from where
    // it pours in, its crest at the level it was filled to: what pours in
    // crosses the pool as a current and leaves over it, the pool standing as
    // far over the crest as Poleni's law needs to pass that much.
    if (pours.isNotEmpty) {
      final from = Vector2(pours.first.x, pours.first.z);
      final corner = <Vector2>[
        Vector2(vx0 + 2.0, vz0 + 2.0),
        Vector2(vx1 - 2.0, vz0 + 2.0),
        Vector2(vx0 + 2.0, vz1 - 2.0),
        Vector2(vx1 - 2.0, vz1 - 2.0),
      ].reduce((a, b) => a.distanceTo(from) >= b.distanceTo(from) ? a : b);
      world.setShallowOutlet(
        native,
        0,
        NativeOutlet.weir(x: corner.x, z: corner.y, crest: surface, width: 4.0),
      );
    }
    return RunPool._(
      name: name,
      liquid: native,
      ground: ground,
      surface: surface,
      molten: molten,
      center: center,
      half: half,
      pours: pours,
      sills: sills,
      density: liquid.properties.density,
    );
  }

  /// The ground at ([x], [z]): the top of the highest of [brushes] over it
  /// that stands up from below [reach], or the pit's [floor].
  static double groundAt(
    double x,
    double z,
    List<Brush> brushes, {
    required double floor,
    required double reach,
  }) => brushes.fold(floor, (top, b) {
    final h = b.size / 2.0;
    final over =
        (x - b.center.x).abs() <= h.x &&
        (z - b.center.z).abs() <= h.z &&
        b.center.y - h.y < reach;
    return over ? math.max(top, b.center.y + h.y) : top;
  });

  /// How far [p] is from the segment from [a] to [b].
  static double _toSegment(Vector2 p, Vector2 a, Vector2 b) {
    final ab = b - a;
    final t = ab.length2 == 0.0
        ? 0.0
        : ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
    return (a + ab * t).distanceTo(p);
  }

  /// [solid] at [at], turned [turn]: the core's calls `Elements.addBody`
  /// makes, here without anything to draw it.
  NativeBody _add(
    Solid solid, {
    required Vector3 at,
    Quaternion? turn,
    NativeBodyType type = NativeBodyType.dynamic,
    ({int layer, int mask})? collides,
  }) {
    final native = world.addBody(position: at, type: type, mass: solid.mass);
    final parts = solid.parts;
    if (parts != null) {
      world.setCompound(native, world.createCompound(parts));
    } else {
      world.setShape(native, solid.shape);
    }
    world.setMaterial(native, solid.material);
    if (solid.rounding > 0) world.setRounding(native, solid.rounding);
    if (turn != null) world.setOrientation(native, turn);
    if (collides != null) {
      world.setCollisionFilter(
        native,
        layer: collides.layer,
        mask: collides.mask,
      );
    }
    return native;
  }

  /// The level's stone round the pools, as bodies the wood bumps into:
  /// granite, at 2700 kg/m³, though fixed bodies do not move whatever they
  /// weigh.
  void _stoneAbout(List<Brush> brushes) {
    for (final b in brushes) {
      final h = b.size / 2.0;
      final near = pools.any((p) {
        final o = p.liquid.origin;
        final w = p.liquid.nx * p.liquid.cell, d = p.liquid.nz * p.liquid.cell;
        return b.center.x + h.x > o.x - 1.0 &&
            b.center.x - h.x < o.x + w + 1.0 &&
            b.center.z + h.z > o.z - 1.0 &&
            b.center.z - h.z < o.z + d + 1.0 &&
            b.center.y - h.y < p.surface + 1.0;
      });
      if (!near) continue;
      _add(
        Solid.box(h, material: NativeMaterial.stone(), density: 2700.0),
        at: b.center,
        type: NativeBodyType.fixed,
        collides: (layer: _stone, mask: _wood),
      );
    }
  }

  /// A log's radius and half its length, m.
  static const double logRadius = 0.15, logHalf = 0.8;

  static final List<NativeCompoundPart> _raftParts = <NativeCompoundPart>[
    // Logs as rounded bars along z: a cylinder on its side would roll.
    for (final x in <double>[-0.31, 0.0, 0.31])
      NativeCompoundPart(
        NativeShape.box(
          Vector3(logRadius * 0.6, logRadius * 0.6, logHalf - 0.06),
        ),
        at: Vector3(x, 0, 0),
        rounding: logRadius * 0.4,
      ),
  ];

  /// The wood the [dressing] floats. Held up by what it displaces, its
  /// shape righting it, dragged and rocked by the water and nothing else:
  /// where a current takes it, it goes.
  void _float(Dressing dressing) {
    for (final (k, a) in dressing.afloat.indexed) {
      final pool = pools.where((p) => p.name == a.pool).firstOrNull;
      if (pool == null) continue;
      // Turned a little each, so no two lie square to the pit.
      final turn = Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7 * k + 0.3);
      final solid = a.raft
          // Pine at 450 kg/m³.
          ? Solid.compound(
              _raftParts,
              material: NativeMaterial.wood(),
              density: 450.0,
            )
          // Boards nailed across two battens: pine, and air under the boards.
          : Solid.box(
              Vector3(0.4, 0.07, 1.1),
              material: NativeMaterial.wood(),
              density: 400.0,
            );
      afloat.add((
        body: _add(
          solid,
          at: Vector3(a.x, pool.surface + 0.3, a.z),
          turn: turn,
          collides: (layer: _wood, mask: _stone | _following | _wood),
        ),
        raft: a.raft,
      ));
    }
  }

  /// The height of the wading legs' middle over the feet, m.
  static const double _shin = 0.24;

  /// The runner, and every barge whose hull reaches down into a pool, as
  /// bodies following them through the water: they part it and push the
  /// wood. What wades is the legs, not the box the run steps: that box is
  /// the runner's reach, and in shin-deep water all of a body that size
  /// pushed every drop out of the cells it stood in. Legs and hips, sixty
  /// litres about, from the feet up.
  void _follow(MechanismWorld mechanisms) {
    if (pools.isEmpty) return;
    final body = _runner.body;
    _followWith(
      () => body.position.clone()..y += _shin - body.halfExtents.y,
      Vector3(0.17, 0.3, 0.14),
    );
    for (final mechanism in mechanisms.all) {
      if (mechanism is! Mover) continue;
      final shape = mechanism.collider.shape;
      if (shape is! CollisionBox) continue;
      final at = mechanism.collider.position;
      final half = shape.halfExtents;
      final wet = pools.any(
        (p) => !p.molten && p.covers(at.x, at.z) && at.y - half.y < p.surface,
      );
      if (!wet) continue;
      _followWith(() => mechanism.collider.position.clone(), half);
    }
  }

  void _followWith(Vector3 Function() at, Vector3 half) {
    final native = world.addBody(
      position: at(),
      type: NativeBodyType.kinematic,
    );
    world
      ..setShape(native, NativeShape.box(half))
      ..setCollisionFilter(native, layer: _following, mask: _wood);
    _followers.add((body: native, at: at));
  }

  /// A bed of split wood and coal, [half] a box about [center], at 500
  /// kg/m³.
  NativeBody _bed(Vector3 center, Vector3 half) => _add(
    Solid.box(half, material: NativeMaterial.wood(), density: 500.0),
    at: center,
    type: NativeBodyType.fixed,
  );

  // ------------------------------------------------------------ stepping

  /// One fixed step of the run: the followers carried to where the runner
  /// and the barges are now — put there outright when one has gone further
  /// than a step could carry it, a respawn or a teleport — the torches
  /// held, the world on by [dt], and then the runner held up, held back
  /// and burnt by what the world now is, for the runner's next step.
  void step(double dt) {
    if (dt <= 0.0) return;
    for (final f in _followers) {
      final to = f.at();
      if ((to - world.localPositionOf(f.body)).length > 3.0) {
        world
          ..setPosition(f.body, to)
          ..setVelocity(f.body, Vector3.zero());
      } else {
        world.moveKinematic(f.body, to, Quaternion.identity(), dt);
      }
    }
    for (var k = 0; k < _torches.length; k++) {
      if (_torchLeft[k] <= 0.0) continue;
      final t = _torches[k];
      world.holdFlame(
        t.body,
        t.at,
        flux: _torch.flux,
        area: _torch.area,
        temperature: _torch.temperature,
      );
      _torchLeft[k] -= dt;
    }
    world.step(dt);
    _steps++;
    // Read every step, so none wait in the world's snapshot.
    final events = world.readEvents();
    if (++_unread > 60) {
      _events.clear();
      _unread = 1;
    }
    _events.addAll(events);
    wade(_runner, dt);
    burn(_runner, dt);
  }

  // ------------------------------------------------------------ the runner

  /// The runner's body, as ICRP Publication 89's reference adult man:
  /// 73 kg and 1.76 m.
  static const double runnerMass = 73.0, runnerHeight = 1.76;

  /// A body's density, kg/m³: Brožek, Grande, Anderson and Keys's reference
  /// body (Ann. N.Y. Acad. Sci. 110, 1963), 1.064 g/cm³.
  static const double runnerDensity = 1064.0;

  /// The width the water meets, m: a cylinder of the body's own volume and
  /// height, 0.22 m across — about the two legs side by side.
  static final double runnerWidth =
      2.0 * math.sqrt(runnerMass / runnerDensity / (math.pi * runnerHeight));

  /// A circular cylinder's drag coefficient across a flow below the drag
  /// crisis, Reynolds numbers 10⁴ to 2·10⁵ — wading at up to a metre a
  /// second (Hoerner, Fluid-Dynamic Drag, 1965, chapter 3).
  static const double cylinderDrag = 1.2;

  /// The water about the runner held up and held back by it.
  ///
  /// The core's water at the runner's feet says how deep they stand in it
  /// and how it flows there. **Archimedes:** what is under the surface of a
  /// body of [runnerDensity] in a liquid of density ρ takes ρ/ρ_body of its
  /// share of the weight off it, so in the air — a jump, a fall into a pool
  /// — the run's own gravity is that much weaker. On the floor the share
  /// goes to the runner as `Runner.lift`: the feet are pressed onto the
  /// floor that much less, and push along it that much less, μ g (1 − lift)
  /// (`RunnerSettings.grip`). **Drag:** F = ½ ρ C_d A |v − u| (v − u) on the
  /// wetted front of a [runnerWidth] cylinder, v the runner's velocity and
  /// u the water's, integrated over the step exactly — v − u shrinks by
  /// 1 + k|v − u|dt, k = ½ρC_dA/m — so a step never turns the runner round.
  ///
  /// Before the runner's own step, which accelerates the runner again by as
  /// much as the soles can push: the runner settles where the drag at their
  /// speed takes what the legs give back, k v² = a (1 + k v dt) with
  /// a = μ g (1 − lift). On the run's gravity of 24 m/s² and a grip of
  /// 0.68, water a shin deep (0.3 m) holds a walk or a sprint to 5.1 m/s,
  /// to the knee (0.5 m) to 3.7, and over the head to 0.56; water at the
  /// ankle (0.1 m) slows a sprint to 9.3 and leaves a walk alone. Before
  /// the grip, when the legs pushed at the controller's 70 m/s², shin-deep
  /// water slowed nobody below 11.9. A current
  /// the runner does not walk against carries them.
  static void wadeIn(
    Runner runner,
    double dt, {
    required double surface,
    required double density,
    required double flowX,
    required double flowZ,
  }) {
    final body = runner.body;
    final feet = body.position.y - body.halfExtents.y;
    final wet = (surface - feet).clamp(0.0, runnerHeight);
    if (wet <= 0.0) return;
    final v = body.velocity;
    final share = density / runnerDensity * wet / runnerHeight;
    runner.lift = share;
    v.y += runner.gravity * share * dt;
    final k = 0.5 * density * cylinderDrag * runnerWidth * wet / runnerMass;
    final rx = v.x - flowX, rz = v.z - flowZ;
    final slowed = 1.0 / (1.0 + k * math.sqrt(rx * rx + rz * rz) * dt);
    v
      ..x = flowX + rx * slowed
      ..z = flowZ + rz * slowed;
  }

  /// [wadeIn] the pool the runner stands over, if there is water there.
  void wade(Runner runner, double dt) {
    final p = runner.body.position;
    for (final pool in pools) {
      if (!pool.covers(p.x, p.z)) continue;
      final at = world.sampleShallow(pool.liquid, p.x, p.z);
      if (at == null || at.depth <= 0.0) continue;
      wadeIn(
        runner,
        dt,
        surface: pool.liquid.origin.y + at.surface,
        density: pool.density,
        flowX: at.flowX,
        flowZ: at.flowZ,
      );
      return;
    }
  }

  /// The incident radiant flux at or below which skin takes no harm however
  /// long, W/m²: ISO 13571:2012, §8.4, 2.5 kW/m² —
  /// [FireExposure.harmlessFlux].
  static const double harmlessFlux = FireExposure.harmlessFlux;

  /// W/m² onto the point of the runner's box nearest each flame, summed
  /// over the world's fires.
  ///
  /// Each fire as Modak's point source (Combustion and Flame 29, 1977): its
  /// radiant share of the power it gives off, spread over a sphere about
  /// the middle of its flame, q = χ_r Q / 4πR². Close in the point source
  /// overstates it without bound, and nothing is heated past what the
  /// flame's own soot radiates, σT⁴: inside the flame that is the flux.
  /// [FireExposure.fluxFrom], measured to the runner's box.
  static double fluxOnto(Runner runner, List<NativeFire> fires) {
    final body = runner.body;
    final lo = body.position - body.halfExtents;
    final hi = body.position + body.halfExtents;
    return fires.fold(0.0, (flux, fire) {
      final source = FireExposure.middleOf(fire);
      final near = Vector3(
        source.x.clamp(lo.x, hi.x),
        source.y.clamp(lo.y, hi.y),
        source.z.clamp(lo.z, hi.z),
      );
      return flux + FireExposure.fluxFrom(fire, (source - near).length2);
    });
  }

  /// The share of the runner's health a step of [dt] s at [flux] W/m²
  /// costs: none at or under [harmlessFlux], and above it the dose of radiant
  /// heat ISO 13571:2012 counts to second-degree burns, its equation (7)
  /// after Wieczorek and Dembsey (2001): t = 6.9 q^−1.56 minutes, q in
  /// kW/m². A full dose is the whole of the runner's health.
  /// [FireExposure.burnDoseRate] over [dt].
  static double burnt(double flux, double dt) =>
      dt * FireExposure.burnDoseRate(flux);

  /// The fires the runner stands beside, hurting them.
  void burn(Runner runner, double dt) {
    final health = runner.health;
    if (health.isDead) return;
    final share = burnt(fluxOnto(runner, world.fires()), dt);
    if (share > 0.0) runner.applyDamage(health.maximum * share);
  }

  // ------------------------------------------------------------ saving

  /// The world as it is, the torches still held with it: a value JSON can
  /// hold, for the run's snapshot.
  Object? save() => <String, Object?>{
    'world': base64Encode(world.snapshot()),
    'torches': List<double>.of(_torchLeft),
  };

  /// Back to what [save] gave; anything else changes nothing.
  void restore(Object? saved) {
    if (saved case {
      'world': final String bytes,
      'torches': final List<Object?> torches,
    }) {
      world.restore(base64Decode(bytes));
      for (var k = 0; k < _torchLeft.length && k < torches.length; k++) {
        if (torches[k] case final num left) _torchLeft[k] = left.toDouble();
      }
      _events.clear();
      _unread = 0;
    }
  }

  /// Lets the world go, with the level: the run closes a level before it
  /// opens the next, and a drawing still holding this one asks [isDisposed]
  /// before it copies.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    world.dispose();
  }

  bool get isDisposed => _disposed;
  bool _disposed = false;
}

/// The name the elements' state is saved under in the run's snapshot
/// (`PlatformerSimulation.parts`).
const String elementsPart = 'elements';

/// The elements' share of one step of the run, after the simulation's own:
/// [elements] stepped by [dt] when [sim]'s step moved the world, so the water
/// and the fires stand still exactly when everything else does — behind the
/// summary screen, and on the step that puts a fallen runner back.
///
/// **The one place this is decided**, called from the engine loop's
/// `elements` phase and from `Staged.step`, so a replay, a rewind, the ghost
/// and a test step the elements as the game does.
void stepElements(PlatformerSimulation sim, RunElements? elements, double dt) {
  if (elements == null || !sim.didMoveThisStep) return;
  elements.step(dt);
}
