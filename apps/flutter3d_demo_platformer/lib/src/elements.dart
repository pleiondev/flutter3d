/// The level's water, molten metal, fire and floating wood, on the physics
/// core and drawn with `flutter3d_effects`.
///
/// **A world of its own beside the run, and the run never learns of it.**
/// The simulation steps the runner through trigger volumes and does not
/// care what they look like; this reads the level document, the hazards'
/// boxes and where the runner and the barges are each frame, and builds a
/// [NativeWorld] of its own out of them: shallow water filling each pit the
/// level's [Dressing] names, springs on the ledges over them that pour in
/// as falls, wood floating in it, coal and braziers burning. The runner
/// wades through that water as a body following them, so the water parts,
/// splashes and leaves a wake behind them, and the barges do the same. None
/// of it is written back: a fire does no harm and a raft holds nobody up,
/// so a replay, a ghost and a test step exactly as they always have.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart' show LevelLoader;
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_platformer/flutter3d_game_platformer.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'dressing.dart';
import 'run.dart';

/// One pit's liquid: the grid it is stepped on, what draws it, and the
/// drain that keeps its level where the level put it.
final class _Pool {
  _Pool({
    required this.name,
    required this.liquid,
    required this.view,
    required this.surface,
    required this.bottom,
    required this.inflow,
    required this.springs,
    required this.drain,
    required this.molten,
  });

  final String name;
  final NativeShallowLiquid liquid;
  final LiquidView view;

  /// The height its surface was filled to, m, and the pit's floor.
  final double surface, bottom;

  /// What its springs pour in, m³/s, and how many there are: its drain is
  /// the source after them.
  final double inflow;
  final int springs;

  /// Where it is drawn off as fast as it is poured in, when anything is.
  final Vector2? drain;
  final bool molten;

  /// Whether ([x], [z]) lies over this pool's grid.
  bool covers(double x, double z) {
    final o = liquid.origin;
    return x >= o.x &&
        z >= o.z &&
        x <= o.x + liquid.nx * liquid.cell &&
        z <= o.z + liquid.nz * liquid.cell;
  }
}

/// A piece of wood afloat and what draws it.
final class _Afloat {
  _Afloat(this.body, this.node, this.home, this.pool, this.phase);

  final NativeBody body;
  final SceneNode node;

  /// Where it was put in, and goes back to when it leaves its pool.
  final Vector3 home;
  final _Pool pool;

  /// Where in its wander the air that pushes it is.
  final double phase;
}

/// Something burning: its body, what draws it, and the box and mass of
/// wood it is made again of when it has burnt down.
final class _Fuel {
  _Fuel(this.body, this.node, this.centre, this.half, this.mass);

  final NativeBody body;
  final MeshNode node;
  final Vector3 centre, half;
  final double mass;
}

/// A body that goes where something of the run goes: the runner, a barge.
final class _Follower {
  _Follower(this.body, this.at);

  final NativeBody body;

  /// Where the thing it follows is now.
  final Vector3 Function() at;
}

/// The effects of a level: built once for the session, and dressed again
/// for every level the run opens.
final class LevelElements {
  LevelElements({
    required GraphicsDevice device,
    required Renderer renderer,
    required this.water,
    required this.molten,
    this.light = false,
  }) : _device = device {
    fire = FireView(
      world: world,
      device: device,
      // A scene of its own until a level is up: [stage] carries the
      // firelight into each level's scene in turn.
      scene: Scene(),
      renderer: renderer,
      // A brazier's split logs and lumps of coal, a hand across: the
      // tongues are sized from it and the fire puffs by it.
      baseWidth: 0.35,
      detail: light ? FireDetail.light : FireDetail.full,
    );
  }

  /// Whether to draw less of the water and the fire, for a phone.
  final bool light;

  /// The looks of the water and of the metal.
  final LiquidLook water, molten;

  final GraphicsDevice _device;

  /// Everything here: the pools, the wood, the fires, the followers.
  final NativeWorld world = NativeWorld();

  /// Every fire of [world], drawn. One for the session, because the
  /// renderer keeps what it adds for good.
  late final FireView fire;

  /// What the fires, the falls and the splashes sound like this frame. A
  /// new one for each level, since it holds the pools it listens to.
  late PhysicsHearing hearing = PhysicsHearing(world);

  final List<_Pool> _pools = <_Pool>[];
  final List<_Afloat> _afloat = <_Afloat>[];
  final List<_Fuel> _burning = <_Fuel>[];
  final List<_Follower> _followers = <_Follower>[];
  final List<NativeBody> _solid = <NativeBody>[];

  /// The hazards' own boxes, kept out of sight under what is drawn instead.
  final List<MeshNode> _hidden = <MeshNode>[];

  /// The body wading where the runner wades, and the pool it was last over.
  _Follower? _wader;
  _Pool? _wadingIn;
  double _clock = 0.0, _sinceFed = 0.0;

  /// No more cells than this to a pool at half a metre a cell; a bigger
  /// pool is stepped a metre a cell.
  static const int _mostCells = 6000;

  /// How far past a pit's box its grid reaches, m, so the bank is in it.
  static const double _margin = 1.0;

  /// Collision layers: the level's stone, the followers, the wood. A
  /// follower pushes the wood and goes through stone, so it never lags the
  /// runner on a step the core would have it climb.
  static const int _stone = 1, _following = 2, _wood = 4;

  /// Dresses [level]: whatever the last level had is taken out, and its
  /// pits filled, its fires lit, its wood floated.
  void stage(LevelReady level) {
    _clear();
    final document = level.loaded.level;
    final scene = level.scene;
    final dressing = Dressing.of(document.name);
    fire.light.removeFromParent();
    scene.add(fire.light);
    hearing = PhysicsHearing(world);
    _tune(document);

    final brushes = <Brush>[
      for (final b in document.brushes)
        if (b.solid) b,
    ];
    final stone = switch (document.materials['stone']) {
      final LevelMaterial m => (
        look: LevelLoader.materialFrom(
          m,
          level.loaded.materialTextures,
          name: 'stone',
        ),
        perMetre: m.texelsPerMetre,
      ),
      null => (
        look: Material(
          name: 'stone',
          baseColor: Vector4(0.36, 0.36, 0.35, 1.0),
          roughness: 1.0,
        ),
        perMetre: 0.5,
      ),
    };
    final dressed = <String>{};
    for (final mechanism in level.staged.mechanisms.all) {
      final (name, collider) = switch (mechanism) {
        Hazard(:final name, :final collider) => (name, collider),
        Water(:final name, :final collider) => (name, collider),
        _ => (null, null),
      };
      final box = collider?.shape;
      if (collider == null || box is! CollisionBox) continue;
      final centre = collider.position;
      final half = box.halfExtents;
      final (surface, hot) = switch (mechanism) {
        // Water the run swims in is drawn full to its top.
        Water() => (centre.y + half.y - 0.05, false),
        _ => switch ((dressing.water[name], dressing.molten[name])) {
          (final double cold?, _) => (cold, false),
          (_, final double metal?) => (metal, true),
          _ => (null, false),
        },
      };
      if (surface == null) continue;
      _pools.add(
        _pool(
          name ?? 'water',
          centre,
          half,
          surface: surface,
          molten: hot,
          pours: <Pour>[
            for (final s in dressing.spills)
              if (s.into == name) s,
          ],
          brushes: brushes,
          scene: scene,
        ),
      );
      _line(centre, half, brushes, stone.look, stone.perMetre, scene);
      if (name != null) dressed.add(name);
    }
    _hidden.addAll(scene.meshes.where((m) => dressed.contains(m.name)));

    _stoneAbout(brushes);
    _float(dressing, level, scene);
    _follow(level);
    for (final (x, y, z) in dressing.braziers) {
      _brazier(Vector3(x, y, z), scene);
    }
    for (final (x, y, z) in dressing.heaps) {
      // A heap of coal lying on the floor of a molten pit.
      _heap(Vector3(x, y, z), scene);
    }
  }

  /// The looks lit as [level] is: its sun, and its fog for the sky they
  /// mirror.
  void _tune(Level level) {
    for (final light in level.lights) {
      if (light.type != LevelLightType.directional) continue;
      for (final look in <LiquidLook>[water, molten]) {
        look.sun(along: light.direction, light: light.color * light.intensity);
      }
      break;
    }
    final fog = level.fogColor;
    water
      ..sky(zenith: fog * 2.0, horizon: fog * 4.0 + Vector3.all(0.05))
      // Cistern water: green over stone, dark where it is deep, and clear
      // enough to see a step or two down.
      ..tint(
        shallow: Vector3(0.16, 0.30, 0.27),
        deep: Vector3(0.015, 0.06, 0.07),
        clearness: 0.3,
      );
    molten
      ..sky(zenith: fog, horizon: fog * 2.0)
      ..tint(
        shallow: Vector3(0.12, 0.035, 0.015),
        deep: Vector3(0.04, 0.015, 0.008),
        clearness: 1e-6,
      )
      ..glow = Vector3(1.3, 0.3, 0.04);
  }

  /// A pit's grid: the box's footprint and a margin of bank, reaching up
  /// onto the ledges its [pours] well up on; the ground the level's
  /// brushes stand at; filled to [surface].
  _Pool _pool(
    String name,
    Vector3 centre,
    Vector3 half, {
    required double surface,
    required bool molten,
    required List<Pour> pours,
    required List<Brush> brushes,
    required Scene scene,
  }) {
    final (vx0, vz0) = (centre.x - half.x, centre.z - half.z);
    final (vx1, vz1) = (centre.x + half.x, centre.z + half.z);
    final x0 = pours.fold(vx0 - _margin, (m, s) => math.min(m, s.x - 2.0));
    final z0 = pours.fold(vz0 - _margin, (m, s) => math.min(m, s.z - 2.0));
    final x1 = pours.fold(vx1 + _margin, (m, s) => math.max(m, s.x + 2.0));
    final z1 = pours.fold(vz1 + _margin, (m, s) => math.max(m, s.z + 2.0));
    final fine = (x1 - x0) * (z1 - z0) / 0.25 <= _mostCells;
    final cell = (fine ? 0.5 : 1.0) * (light ? 2.0 : 1.0);
    final nx = ((x1 - x0) / cell).ceil(), nz = ((z1 - z0) / cell).ceil();
    final bottom = centre.y - half.y;
    // What stands up from the floor counts as ground; what hangs over the
    // pit — a lintel, a shelf — does not, or the water would stop under it.
    final reach = centre.y + half.y + 0.5;
    final ground = <double>[
      for (var j = 0; j < nz; j++)
        for (var i = 0; i < nx; i++)
          _groundAt(
            x0 + (i + 0.5) * cell,
            z0 + (j + 0.5) * cell,
            brushes,
            floor: bottom,
            reach: reach,
          ),
    ];
    // Each spill runs to the nearest point of the pit's edge down a culvert
    // under the ledge, so it falls in one stream instead of spreading over
    // the floor: the water in it runs under the stone the level draws, and
    // is first seen pouring out of the culvert's mouth in the pit's wall.
    for (final s in pours) {
      final lip = Vector2(s.x.clamp(vx0, vx1), s.z.clamp(vz0, vz1));
      final from = Vector2(s.x, s.z);
      final top = _groundAt(s.x, s.z, brushes, floor: bottom, reach: reach);
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
      _mouth(lip, (vx0, vz0, vx1, vz1), s, top - s.culvert, scene);
    }
    final liquid = world.createShallowLiquid(
      nx: nx,
      nz: nz,
      cell: cell,
      origin: Vector3(x0, 0.0, z0),
      ground: ground,
    );
    // A pool poured into gets its culverts' bed. A stream reaching a lip
    // metres over the water is driven over it by the whole of that drop in
    // one cell, and on a smooth bed it leaves at ten metres a second, a jet
    // across the pool rather than a fall down the wall; friction on the
    // film in the culvert holds it to a stream's pace. Friction goes as the
    // inverse of the depth to the four thirds, so the pool itself, a metre
    // or more deep, hardly feels it.
    world.setShallowBed(
      liquid,
      roughness: pours.fold(
        molten ? 0.05 : 0.03,
        (n, s) => math.max(n, s.roughness),
      ),
    );
    if (molten) {
      world.setShallowProperties(liquid, NativeLiquidProperties.moltenBasalt);
    }
    world.fillShallowLiquid(
      liquid,
      x0: vx0,
      z0: vz0,
      x1: vx1,
      z1: vz1,
      level: surface,
    );
    for (final (k, s) in pours.indexed) {
      world.setShallowSource(
        liquid,
        k,
        x: s.x,
        z: s.z,
        radius: 0.4,
        rate: s.rate,
      );
    }
    // Drawn off at the corner of the pit furthest from where it pours in,
    // so what pours in crosses the pool as a current on its way out.
    final Vector2? drain;
    if (pours.isEmpty) {
      drain = null;
    } else {
      final from = Vector2(pours.first.x, pours.first.z);
      drain = <Vector2>[
        Vector2(vx0 + 2.0, vz0 + 2.0),
        Vector2(vx1 - 2.0, vz0 + 2.0),
        Vector2(vx0 + 2.0, vz1 - 2.0),
        Vector2(vx1 - 2.0, vz1 - 2.0),
      ].reduce((a, b) => a.distanceTo(from) >= b.distanceTo(from) ? a : b);
    }
    final view = LiquidView(
      world: world,
      liquid: liquid,
      ground: ground,
      device: _device,
      scene: scene,
      look: (molten ? this.molten : water).material,
      detail: light ? LiquidDetail.light : LiquidDetail.full,
    );
    hearing.listen(
      liquid,
      density: molten ? NativeLiquidProperties.moltenBasalt.density : 1000.0,
    );
    return _Pool(
      name: name,
      liquid: liquid,
      view: view,
      surface: surface,
      bottom: bottom,
      inflow: pours.fold(0.0, (sum, s) => sum + s.rate),
      springs: pours.length,
      drain: drain,
      molten: molten,
    );
  }

  /// The ground at ([x], [z]): the top of the highest of [brushes] over it
  /// that stands up from below [reach], or the pit's [floor].
  static double _groundAt(
    double x,
    double z,
    List<Brush> brushes, {
    required double floor,
    required double reach,
  }) => brushes.fold(floor, (top, b) {
    final h = b.size / 2.0;
    final over =
        (x - b.centre.x).abs() <= h.x &&
        (z - b.centre.z).abs() <= h.z &&
        b.centre.y - h.y < reach;
    return over ? math.max(top, b.centre.y + h.y) : top;
  });

  /// How far [p] is from the segment from [a] to [b].
  static double _toSegment(Vector2 p, Vector2 a, Vector2 b) {
    final ab = b - a;
    final t = ab.length2 == 0.0
        ? 0.0
        : ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
    return (a + ab * t).distanceTo(p);
  }

  /// The pit's walls where the level has none: its floors are slabs a metre
  /// thick laid over nothing, so under a walkway that stands higher than
  /// the pit's floor — the gallery four metres over the spill, the side
  /// walls' feet — the pit's side is open, and its water was seen ending
  /// against a black gap. Each side is faced in [look] from the pit's floor
  /// up to the underside of whatever stands over that side, facing into
  /// the pit, so it shares no face with a brush.
  void _line(
    Vector3 centre,
    Vector3 half,
    List<Brush> brushes,
    Material look,
    double perMetre,
    Scene scene,
  ) {
    final (x0, x1) = (centre.x - half.x, centre.x + half.x);
    final (z0, z1) = (centre.z - half.z, centre.z + half.z);
    final floor = centre.y - half.y;
    // Each side: along x or z, where it stands, its span, and which way is
    // into the pit.
    final sides = <(bool, double, double, double, double)>[
      (true, z0, x0, x1, 1.0),
      (true, z1, x0, x1, -1.0),
      (false, x0, z0, z1, 1.0),
      (false, x1, z0, z1, -1.0),
    ];
    const touch = 0.05;
    for (final (alongX, at, from, to, inwards) in sides) {
      final over = brushes.where((b) {
        final h = b.size / 2.0;
        final (across, across0, across1) = alongX
            ? (b.centre.z, b.centre.x - h.x, b.centre.x + h.x)
            : (b.centre.x, b.centre.z - h.z, b.centre.z + h.z);
        final depth = alongX ? h.z : h.x;
        // On the far side of the line from the pit, touching it.
        final beyond = inwards > 0
            ? across + depth <= at + touch && across + depth >= at - touch
            : across - depth >= at - touch && across - depth <= at + touch;
        return beyond &&
            across1 > from &&
            across0 < to &&
            b.centre.y - b.size.y / 2.0 > floor + touch;
      });
      if (over.isEmpty) continue;
      // Never over the pit's own top, where the walkways are: what stands
      // higher than that beside a pit stands on something else.
      final top = over
          .map((b) => b.centre.y - b.size.y / 2.0)
          .fold(centre.y + half.y, math.min);
      if (top <= floor + touch) continue;
      final mesh = DeviceMesh.upload(
        _device,
        _face(
          alongX: alongX,
          at: at,
          from: from,
          to: to,
          bottom: floor,
          top: top,
          inwards: inwards,
          perMetre: perMetre,
        ),
      );
      scene.add(MeshNode(mesh, look, name: 'pit wall'));
    }
  }

  /// A culvert's mouth in the wall the [pour] runs out over, at [lip] on the
  /// pit's [box]: a dark opening as wide as the culvert, its sill where the
  /// water in it runs at [sill], in an iron frame, so the stream has
  /// somewhere to come out of.
  void _mouth(
    Vector2 lip,
    (double, double, double, double) box,
    Pour pour,
    double sill,
    Scene scene,
  ) {
    final (x0, z0, x1, z1) = box;
    // Which wall it is in, and which way out of it is.
    final (Vector2 out, bool alongX) = switch (lip) {
      _ when lip.y <= z0 + 1e-6 => (Vector2(0.0, 1.0), true),
      _ when lip.y >= z1 - 1e-6 => (Vector2(0.0, -1.0), true),
      _ when lip.x <= x0 + 1e-6 => (Vector2(1.0, 0.0), false),
      _ => (Vector2(-1.0, 0.0), false),
    };
    const band = 0.07, standOff = 0.06;
    // Its lintel stays under the ledge's top, short of the edge of the floor.
    final height = math.min(0.42, pour.culvert - band - 0.02);
    if (height <= 0.05) return;
    final width = pour.width;
    final dark = Material(
      name: 'culvert',
      baseColor: Vector4(0.012, 0.012, 0.012, 1.0),
      roughness: 1.0,
    );
    final iron = _ironLook;
    final bar = _mesh('bar', () => CuboidShape(size: Vector3.all(1.0)).build());
    // Proud of the wall by a centimetre and a half: enough that the depth
    // test never mixes it with the stone behind it.
    final face = lip + out * 0.015;
    final mid = sill + height / 2.0;
    scene.add(
      MeshNode(bar, dark, name: 'culvert mouth')
        ..setPosition(face.x, mid, face.y)
        ..setScale(alongX ? width : 0.01, height, alongX ? 0.01 : width),
    );
    // The frame: a lintel over it and a jamb either side, an iron band
    // standing six centimetres off the wall.
    final frame = lip + out * (standOff / 2.0);
    final across = alongX ? Vector2(1.0, 0.0) : Vector2(0.0, 1.0);
    for (final (along, y, long, tall) in <(double, double, double, double)>[
      (0.0, sill + height + band / 2.0, width + 2 * band, band),
      (-(width + band) / 2.0, mid, band, height),
      ((width + band) / 2.0, mid, band, height),
    ]) {
      final at = frame + across * along;
      scene.add(
        MeshNode(bar, iron, name: 'culvert frame')
          ..setPosition(at.x, y, at.y)
          ..setScale(alongX ? long : standOff, tall, alongX ? standOff : long),
      );
    }
  }

  /// A wall's face standing at [at] across x ([alongX]) or z, from [from]
  /// to [to] along it and [bottom] to [top], facing [inwards] along the
  /// axis across it, its texture laid in world metres at [perMetre] as the
  /// level's own brushes lay theirs, so the stone runs on from theirs.
  static MeshData _face({
    required bool alongX,
    required double at,
    required double from,
    required double to,
    required double bottom,
    required double top,
    required double inwards,
    required double perMetre,
  }) {
    final normal = alongX
        ? Vector3(0.0, 0.0, inwards)
        : Vector3(inwards, 0.0, 0.0);
    // The face's own axes as the level's brushes take them: `u × v` is the
    // normal, and the stone's texture is the world projected on them.
    final u = alongX ? Vector3(inwards, 0.0, 0.0) : Vector3(0.0, 0.0, -inwards);
    final v = Vector3(0.0, 1.0, 0.0);
    final builder = MeshBuilder(
      VertexLayout.standard,
      reserveVertices: 4,
      reserveIndices: 6,
    );
    final (a, b) = inwards * (alongX ? 1.0 : -1.0) > 0
        ? (from, to)
        : (to, from);
    for (final (along, y) in <(double, double)>[
      (a, bottom),
      (b, bottom),
      (b, top),
      (a, top),
    ]) {
      final p = alongX ? Vector3(along, y, at) : Vector3(at, y, along);
      builder.addVertex(
        position: p,
        normal: normal,
        texcoord: Vector2(p.dot(u) * perMetre, p.dot(v) * perMetre),
        tangent: Vector4(u.x, u.y, u.z, -1.0),
      );
    }
    builder.addQuad(0, 1, 2, 3);
    return builder.build();
  }

  /// The level's stone round the pools, as bodies the wood bumps into.
  void _stoneAbout(List<Brush> brushes) {
    for (final b in brushes) {
      final h = b.size / 2.0;
      final near = _pools.any((p) {
        final o = p.liquid.origin;
        final w = p.liquid.nx * p.liquid.cell, d = p.liquid.nz * p.liquid.cell;
        return b.centre.x + h.x > o.x - 1.0 &&
            b.centre.x - h.x < o.x + w + 1.0 &&
            b.centre.z + h.z > o.z - 1.0 &&
            b.centre.z - h.z < o.z + d + 1.0 &&
            b.centre.y - h.y < p.surface + 1.0;
      });
      if (!near) continue;
      final body = world.addBody(
        position: b.centre,
        type: NativeBodyType.fixed,
        mass: 1000.0,
      );
      world
        ..setShape(body, NativeShape.box(h))
        ..setMaterial(body, NativeMaterial.stone())
        ..setCollisionFilter(body, layer: _stone, mask: _wood);
      _solid.add(body);
    }
  }

  /// The wood the [dressing] floats, in the level's own wood where it has
  /// some.
  void _float(Dressing dressing, LevelReady level, Scene scene) {
    if (dressing.afloat.isEmpty) return;
    final wood = level.loaded.level.materials['wood'];
    final look = wood == null
        ? Material(
            name: 'wood',
            baseColor: Vector4(0.42, 0.30, 0.18, 1.0),
            roughness: 0.85,
          )
        : LevelLoader.materialFrom(
            wood,
            level.loaded.materialTextures,
            name: 'wood',
          );
    final log = _mesh(
      'log',
      () => const CylinderShape(
        radiusTop: _logRadius * 0.92,
        radiusBottom: _logRadius,
        height: 2 * _logHalf,
        segments: 12,
      ).build(),
    );
    final plank = _mesh(
      'plank',
      () => CuboidShape(size: Vector3(0.8, 0.14, 2.2)).build(),
    );
    for (final (k, a) in dressing.afloat.indexed) {
      final pool = _pools.where((p) => p.name == a.pool).firstOrNull;
      if (pool == null) continue;
      final home = Vector3(a.x, pool.surface + 0.3, a.z);
      final NativeBody body;
      final SceneNode node;
      if (a.raft) {
        body = world.addBody(
          position: home,
          // Pine at 450 kg/m³.
          mass: 3 * 450.0 * math.pi * _logRadius * _logRadius * 2 * _logHalf,
        );
        world.setCompound(body, _raftShape);
        node = SceneNode(name: 'raft');
        for (final x in <double>[-0.31, 0.0, 0.31]) {
          node.add(
            MeshNode(log, look, name: 'log')
              ..setPosition(x, 0, 0)
              ..setRotation(
                Quaternion.axisAngle(Vector3(1.0, 0.0, 0.0), math.pi / 2),
              ),
          );
        }
      } else {
        // Boards nailed across two battens: pine, and air under the boards.
        body = world.addBody(position: home, mass: 400.0 * 0.8 * 0.14 * 2.2);
        world.setShape(body, NativeShape.box(Vector3(0.4, 0.07, 1.1)));
        node = MeshNode(plank, look, name: 'plank');
      }
      world
        ..setMaterial(body, NativeMaterial.wood())
        // Water damps a rocking board within a few rolls.
        ..setDamping(body, linear: 0.1, angular: 3.0)
        ..setCollisionFilter(
          body,
          layer: _wood,
          mask: _stone | _following | _wood,
        )
        // Turned a little each, so no two lie square to the pit.
        ..setOrientation(
          body,
          Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.7 * k + 0.3),
        );
      scene.add(node);
      _afloat.add(_Afloat(body, node, home, pool, 1.9 * k));
      if (!pool.molten) hearing.watch(body, pool.liquid);
    }
  }

  /// A log's radius and half its length, m.
  static const double _logRadius = 0.15, _logHalf = 0.8;

  late final NativeCompound _raftShape = world.createCompound(
    <NativeCompoundPart>[
      // Logs as rounded bars along z: a cylinder on its side would roll.
      for (final x in <double>[-0.31, 0.0, 0.31])
        NativeCompoundPart(
          NativeShape.box(
            Vector3(_logRadius * 0.6, _logRadius * 0.6, _logHalf - 0.06),
          ),
          at: Vector3(x, 0, 0),
          rounding: _logRadius * 0.4,
        ),
    ],
  );

  /// The meshes made once, by name, and kept for every level after.
  final Map<String, DeviceMesh> _meshes = <String, DeviceMesh>{};
  DeviceMesh _mesh(String name, MeshData Function() build) =>
      _meshes.putIfAbsent(name, () => DeviceMesh.upload(_device, build()));

  /// The runner, and every barge whose hull reaches down into a pool, as
  /// bodies following them through the water.
  void _follow(LevelReady level) {
    if (_pools.isEmpty) return;
    final runner = level.runner.body;
    // What wades is the legs, not the box the run steps: that box is the
    // runner's reach, and in shin-deep water all of a body that size
    // pushed every drop out of the cells it stood in, leaving a dry patch
    // of floor round the runner. The core takes a body as a ball of its
    // volume: one of sixty litres, legs and hips about, with its middle a
    // ball's radius over the feet, parts the water and leaves it standing
    // round them.
    Vector3 legs() =>
        runner.position.clone()..y += _shin - runner.halfExtents.y;
    _wader = _follower(legs(), Vector3(0.17, 0.3, 0.14), mass: 70.0, at: legs);
    for (final mechanism in level.staged.mechanisms.all) {
      if (mechanism is! Mover) continue;
      final shape = mechanism.collider.shape;
      if (shape is! CollisionBox) continue;
      final at = mechanism.collider.position;
      final half = shape.halfExtents;
      final pool = _pools
          .where(
            (p) =>
                !p.molten && p.covers(at.x, at.z) && at.y - half.y < p.surface,
          )
          .firstOrNull;
      if (pool == null) continue;
      final barge = _follower(
        at,
        half,
        mass: 2000.0,
        at: () => mechanism.collider.position,
      );
      hearing.watch(barge.body, pool.liquid);
    }
  }

  /// The radius of the ball the core takes the wading legs as, m.
  static const double _shin = 0.24;

  _Follower _follower(
    Vector3 from,
    Vector3 half, {
    required double mass,
    required Vector3 Function() at,
  }) {
    final body = world.addBody(position: from.clone(), mass: mass);
    world
      ..setShape(body, NativeShape.box(half))
      ..lockRotation(body)
      ..setCollisionFilter(body, layer: _following, mask: _wood);
    final follower = _Follower(body, at);
    _followers.add(follower);
    return follower;
  }

  /// The iron of the braziers and the culverts' frames: wrought iron gone
  /// dark with heat and damp.
  late final Material _ironLook = Material(
    name: 'iron',
    baseColor: Vector4(0.09, 0.085, 0.08, 1.0),
    roughness: 0.6,
    metallic: 0.85,
  );

  /// An iron brazier standing [at] its feet, its bowl heaped with coal and
  /// two split logs, alight: a hammered bowl with a rolled rim on three
  /// splayed legs, braced by a ring a third of the way up.
  void _brazier(Vector3 at, Scene scene) {
    final iron = _ironLook;
    final bowl = _mesh(
      'bowl',
      () => LatheShape(
        // Out and up the outside to the rim, then back down the inside:
        // a bowl with a wall to it, open at the top.
        profile: <Vector2>[
          Vector2(0.0, 0.0),
          Vector2(0.14, 0.0),
          Vector2(0.30, 0.10),
          Vector2(0.40, 0.22),
          Vector2(0.425, 0.27),
          Vector2(0.395, 0.27),
          Vector2(0.37, 0.215),
          Vector2(0.27, 0.115),
          Vector2(0.12, 0.04),
          Vector2(0.0, 0.04),
        ],
        segments: 20,
      ).build(),
    );
    final rim = _mesh(
      'rim',
      () => const TorusShape(
        radius: 0.41,
        tubeRadius: 0.022,
        segments: 24,
        tubeSegments: 6,
      ).build(),
    );
    final brace = _mesh(
      'brace',
      () => const TorusShape(
        radius: 0.33,
        tubeRadius: 0.014,
        segments: 24,
        tubeSegments: 5,
      ).build(),
    );
    final leg = _mesh(
      'leg',
      () => const CylinderShape(
        radiusTop: 0.018,
        radiusBottom: 0.024,
        segments: 6,
      ).build(),
    );
    final foot = _mesh(
      'foot',
      () => const SphereShape(radius: 0.045, segments: 8, rings: 4).build(),
    );
    const bowlAt = 0.92;
    scene
      ..add(
        MeshNode(bowl, iron, name: 'brazier bowl')
          ..setPosition(at.x, at.y + bowlAt, at.z),
      )
      ..add(
        MeshNode(rim, iron, name: 'brazier rim')
          ..setPosition(at.x, at.y + bowlAt + 0.27, at.z),
      )
      ..add(
        MeshNode(brace, iron, name: 'brazier brace')
          ..setPosition(at.x, at.y + 0.30, at.z),
      );
    for (var k = 0; k < 3; k++) {
      final turn = 2 * math.pi * k / 3 + 0.4;
      final out = Vector3(math.cos(turn), 0.0, math.sin(turn));
      // From a foot on the floor wide of the bowl to the bowl's underside.
      final low = at + out * 0.40;
      final high = at + out * 0.16 + Vector3(0.0, bowlAt + 0.03, 0.0);
      final along = high - low;
      final mid = (low + high) * 0.5;
      scene
        ..add(
          MeshNode(leg, iron, name: 'brazier leg')
            ..setPosition(mid.x, mid.y, mid.z)
            ..setRotation(
              Quaternion.fromTwoVectors(
                Vector3(0.0, 1.0, 0.0),
                along.normalized(),
              ),
            )
            ..setScale(1.0, along.length, 1.0),
        )
        ..add(
          MeshNode(foot, iron, name: 'brazier foot')
            ..setPosition(low.x, at.y + 0.012, low.z)
            ..setScale(1.0, 0.45, 1.0),
        );
    }
    // The coal's bed sits in the bowl's throat and crowns a few
    // centimetres over the rim. The body that burns stands just over it and
    // narrower than the bowl: a flame is drawn from where the core says the
    // fire is, its tongues rooted a little under that, and from the coal
    // itself they hung down past the bowl between the legs.
    final coals = _coals(
      Vector3(at.x, at.y + bowlAt + 0.19, at.z),
      radius: 0.36,
      height: 0.12,
      logs: true,
      scene: scene,
    );
    _burning.add(
      _kindle(
        Vector3(at.x, at.y + bowlAt + 0.36, at.z),
        Vector3(0.22, 0.06, 0.22),
        120.0,
        coals,
      ),
    );
  }

  /// A heap of coal lying [at] on a floor, alight.
  void _heap(Vector3 at, Scene scene) {
    final coals = _coals(
      at,
      radius: 0.5,
      height: 0.5,
      logs: false,
      scene: scene,
    );
    _burning.add(
      _kindle(
        Vector3(at.x, at.y + 0.3, at.z),
        Vector3(0.42, 0.3, 0.42),
        600.0,
        coals,
      ),
    );
  }

  /// Coal heaped over a mound [radius] wide and [height] high from [at],
  /// and, where [logs], two split logs laid crossed on it.
  ///
  /// The mound is the coal glowing in the heart of the heap, and what the
  /// fire chars and lights; lumps of coal lie close over it, a quarter of
  /// them glowing with it and the rest black, so the light shows in the
  /// gaps between the lumps rather than over a face of the heap. The mound
  /// is returned, the lumps and the logs its children.
  MeshNode _coals(
    Vector3 at, {
    required double radius,
    required double height,
    required bool logs,
    required Scene scene,
  }) {
    double crown(double r) =>
        height * math.sqrt(math.max(0.0, 1.0 - (r * r) / (radius * radius)));
    final mound = _mesh(
      'mound $radius $height',
      () => LatheShape(
        profile: <Vector2>[
          for (var k = 0; k <= 6; k++)
            () {
              final r = radius * (1.0 - k / 6);
              return Vector2(r, crown(r));
            }(),
        ],
        segments: 14,
      ).build(),
    );
    final glowing = Material(
      name: 'coal',
      baseColor: Vector4(0.07, 0.055, 0.045, 1.0),
      roughness: 0.85,
    );
    final black = Material(
      name: 'coal',
      baseColor: Vector4(0.035, 0.032, 0.03, 1.0),
      roughness: 0.55,
    );
    final heap = MeshNode(mound, glowing, name: 'coal')
      ..setPosition(at.x, at.y, at.z);
    // Lumps baked into two meshes, the black and the glowing, so a brazier
    // is a handful of draws rather than one a lump.
    for (final (lit, look) in <(bool, Material)>[
      (false, black),
      (true, glowing),
    ]) {
      heap.add(
        MeshNode(
          _mesh(
            '${lit ? 'glowing' : 'black'} lumps $radius $height',
            () => _lumps(radius, crown, glowing: lit),
          ),
          look,
          name: 'coal',
        ),
      );
    }
    if (logs) {
      final log = _mesh(
        'split log',
        () => const CylinderShape(
          radiusTop: 0.045,
          radiusBottom: 0.05,
          height: 0.56,
          segments: 7,
        ).build(),
      );
      final wood = Material(
        name: 'charred wood',
        baseColor: Vector4(0.06, 0.04, 0.03, 1.0),
        roughness: 0.95,
      );
      for (final (turn, rise) in <(double, double)>[(0.5, 0.0), (-1.0, 0.06)]) {
        heap.add(
          MeshNode(log, wood, name: 'log')
            ..setPosition(0.0, height * 0.7 + rise, 0.0)
            ..setRotation(
              Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), turn) *
                  Quaternion.axisAngle(
                    Vector3(0.0, 0.0, 1.0),
                    math.pi / 2 - 0.08,
                  ),
            ),
        );
      }
    }
    scene.add(heap);
    return heap;
  }

  /// The lumps of coal over a mound [radius] wide whose height at a
  /// distance from its middle is [crown]: every fourth of them where
  /// [glowing], the rest where not. Laid on a sunflower's spiral, so they
  /// cover it evenly and close enough to touch, each turned and squashed its
  /// own way; the same for every heap of the same size.
  static MeshData _lumps(
    double radius,
    double Function(double) crown, {
    required bool glowing,
  }) {
    final lump = const SphereShape(radius: 1.0, segments: 6, rings: 4).build();
    final stride = lump.layout.floatsPerVertex;
    final scatter = math.Random(7);
    final count = (radius * radius * 420).round().clamp(24, 110);
    final builder = MeshBuilder(VertexLayout.standard);
    for (var k = 0; k < count; k++) {
      final r = radius * 0.9 * math.sqrt((k + 0.5) / count);
      final turn = k * 2.39996;
      final size = (0.05 + 0.03 * scatter.nextDouble()) * (radius / 0.36);
      final axis = Vector3(scatter.nextDouble(), 1.0, scatter.nextDouble())
        ..normalize();
      final spin = Quaternion.axisAngle(axis, scatter.nextDouble() * math.pi);
      if ((k % 4 == 0) != glowing) continue;
      final scale = Vector3(size * 1.2, size * 0.75, size);
      final centre = Vector3(
        r * math.cos(turn),
        crown(r) - 0.3 * size,
        r * math.sin(turn),
      );
      final first = builder.vertexCount;
      for (var v = 0; v < lump.vertexCount; v++) {
        final o = v * stride;
        final p = Vector3(
          lump.vertices[o] * scale.x,
          lump.vertices[o + 1] * scale.y,
          lump.vertices[o + 2] * scale.z,
        );
        // A normal goes through a stretch by its inverse.
        final n = Vector3(
          lump.vertices[o + 3] / scale.x,
          lump.vertices[o + 4] / scale.y,
          lump.vertices[o + 5] / scale.z,
        )..normalize();
        builder.addVertex(
          position: spin.rotated(p)..add(centre),
          normal: spin.rotated(n),
          texcoord: Vector2(lump.vertices[o + 6], lump.vertices[o + 7]),
        );
      }
      for (var i = 0; i < lump.indices.length; i += 3) {
        builder.addTriangle(
          first + lump.indices[i],
          first + lump.indices[i + 1],
          first + lump.indices[i + 2],
        );
      }
    }
    return builder.build();
  }

  /// A fixed body of [mass] kg of wood, [half] a box about [centre], hot
  /// enough to burn, drawn by [node].
  _Fuel _kindle(Vector3 centre, Vector3 half, double mass, MeshNode node) {
    final body = world.addBody(
      position: centre,
      type: NativeBodyType.fixed,
      mass: mass,
    );
    world
      ..setShape(body, NativeShape.box(half))
      ..setMaterial(body, NativeMaterial.wood())
      ..setTemperature(body, 900.0);
    fire.watch(body, node, fresh: Vector4(0.07, 0.055, 0.045, 1.0));
    return _Fuel(body, node, centre, half, mass);
  }

  /// Hides the hazards' boxes drawn in the pools' place. After the fixtures
  /// are placed, every frame: placing them shows them again.
  void hideDressed() {
    for (final node in _hidden) {
      node.visible = false;
    }
  }

  /// A frame: the followers moved to where the runner and the barges are
  /// now, the world on by [dt] — nought while the run is held for a
  /// photograph — and everything drawn as it then stands, seen from [eye].
  void update(double dt, {required Vector3 eye}) {
    if (dt > 0.0) {
      _clock += dt;
      for (final f in _followers) {
        _chase(f, dt);
      }
      _wade();
      _drain();
      _drift();
      world.step(dt);
      _steady();
      _sinceFed += dt;
      if (_sinceFed >= 1.0) {
        _sinceFed = 0.0;
        _feed();
        _gather();
      }
    }
    for (final p in _afloat) {
      final at = world.positionOf(p.body);
      p.node
        ..setPosition(at.x, at.y, at.z)
        ..setRotation(world.orientationOf(p.body));
    }
    for (final pool in _pools) {
      pool.view.update();
    }
    fire.update(dt);
    hearing.update(dt);
    water.update(seconds: _clock, eye: eye);
    molten.update(seconds: _clock, eye: eye);
  }

  /// [f] sent to where what it follows is, as fast as that takes in one
  /// step; put there outright when it has gone too far to chase — a
  /// respawn, a level edit.
  void _chase(_Follower f, double dt) {
    final to = f.at();
    final gap = to - world.positionOf(f.body);
    if (gap.length > 3.0) {
      world
        ..setPosition(f.body, to)
        ..setVelocity(f.body, Vector3.zero());
      return;
    }
    world
      ..wake(f.body)
      ..setVelocity(f.body, gap / dt);
  }

  /// The splash heard is the pool the runner is over.
  void _wade() {
    final wader = _wader;
    if (wader == null) return;
    final at = world.positionOf(wader.body);
    final pool = _pools
        .where((p) => !p.molten && p.covers(at.x, at.z))
        .firstOrNull;
    if (pool == null || identical(pool, _wadingIn)) return;
    _wadingIn = pool;
    hearing.watch(wader.body, pool.liquid);
  }

  /// Every pool poured into is drawn off as fast, and a little faster
  /// while it stands over the level it was filled to, so it neither
  /// floods its banks nor runs dry.
  void _drain() {
    for (final pool in _pools) {
      final drain = pool.drain;
      if (drain == null) continue;
      final here = world.sampleShallow(pool.liquid, drain.x, drain.y);
      if (here == null) continue;
      final over = here.surface - pool.surface;
      final rate = (pool.inflow + 6.0 * over).clamp(0.0, 2.0 * pool.inflow);
      world.setShallowSource(
        pool.liquid,
        pool.springs,
        x: drain.x,
        z: drain.y,
        radius: 1.0,
        rate: -rate,
      );
    }
  }

  /// A breath of air over the water, wandering, so wood left alone still
  /// drifts; and each piece turned back towards lying flat.
  ///
  /// The core holds a floating body up by what it displaces about its
  /// middle, which gives a board nothing that rights it once something has
  /// tipped it: a plank nudged in the shallows ends up leaning on its end
  /// against the bed and stays there. Wide wood on water lies flat, so it
  /// is turned back towards flat as hard as it is tipped, either face up,
  /// and [_steady] lets none lean further than [_mostTilt]. Kept awake for
  /// it: a board come to rest would otherwise sleep however it lay.
  void _drift() {
    for (final p in _afloat) {
      final t = _clock * 0.11 + p.phase;
      final mass = world.massOf(p.body);
      final push = mass * 0.06;
      final (tilt, _) = _leanOf(p.body);
      world
        ..wake(p.body)
        ..addForce(
          p.body,
          Vector3(math.cos(t) * push, 0.0, math.sin(t * 0.7) * push),
        )
        ..addTorque(p.body, tilt * (mass * 4.0));
    }
  }

  /// Every floating piece leaning further than [_mostTilt] turned back to
  /// it, and its rocking stopped.
  void _steady() {
    for (final p in _afloat) {
      final (tilt, lean) = _leanOf(p.body);
      if (lean <= _mostTilt || tilt.length2 < 1e-12) continue;
      world
        // The body's turn, then the turn back about the world's axis.
        ..setOrientation(
          p.body,
          Quaternion.axisAngle(tilt.normalized(), lean - _mostTilt) *
              world.orientationOf(p.body),
        )
        ..setAngularVelocity(
          p.body,
          Vector3(0.0, world.angularVelocityOf(p.body).y, 0.0),
        );
    }
  }

  /// The axis [body] would turn about to lie flat, as long as the sine of
  /// its lean, and the lean, radians; face up or face down alike, a board
  /// upside down being a board lying flat.
  (Vector3, double) _leanOf(NativeBody body) {
    final up = Vector3(0.0, 1.0, 0.0);
    // Through the matrix: vector_math's `Quaternion.rotated` turns by the
    // inverse.
    final face = world.orientationOf(body).asRotationMatrix().transformed(up);
    if (face.y < 0.0) face.negate();
    return (face.cross(up), math.acos(face.y.clamp(-1.0, 1.0)));
  }

  /// The furthest a floating piece leans, radians: as far as a wave or a
  /// shove rocks one, and short of standing on end.
  static const double _mostTilt = 0.35;

  /// Fuel put back on a fire burnt down, as somebody tending it would.
  void _feed() {
    for (final (k, f) in _burning.indexed) {
      if (world.isBurning(f.body) && world.fuelOf(f.body) > 5.0) continue;
      fire.forget(f.body);
      world.removeBody(f.body);
      _burning[k] = _kindle(f.centre, f.half, f.mass, f.node);
    }
  }

  /// Wood that has left its pool — over a lip, onto a bank and off it —
  /// put back where it was first floated.
  void _gather() {
    for (final p in _afloat) {
      final at = world.positionOf(p.body);
      final lost =
          !p.pool.covers(at.x, at.z) ||
          at.y < p.pool.bottom - 1.0 ||
          at.y > p.pool.surface + 4.0;
      if (!lost) continue;
      world
        ..setPosition(p.body, p.home)
        ..setVelocity(p.body, Vector3.zero());
    }
  }

  /// Everything the last level had, taken out of the world and the scene.
  void _clear() {
    for (final pool in _pools) {
      world.removeShallowLiquid(pool.liquid);
    }
    _pools.clear();
    for (final p in _afloat) {
      world.removeBody(p.body);
    }
    _afloat.clear();
    for (final f in _burning) {
      fire.forget(f.body);
      world.removeBody(f.body);
    }
    _burning.clear();
    for (final f in _followers) {
      world.removeBody(f.body);
    }
    _followers.clear();
    _solid
      ..forEach(world.removeBody)
      ..clear();
    _hidden.clear();
    _wader = null;
    _wadingIn = null;
  }

  void dispose() => world.dispose();
}
