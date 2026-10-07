/// What the map does besides the match: the pond and the stream that runs
/// down into it, fires in the halls and the woods, and the stones a siege
/// throws — all of it the physics core's, in a world of its own.
///
/// **It reads the match and never writes to it.** The simulation is a crowd
/// on a heightfield with no water, no fire and no buildings that can be hurt,
/// and the match it plays is recorded, replayed and checked step by step; a
/// layer that changed one number in it would be a second simulation the tapes
/// know nothing about. So everything here is a consequence drawn from what
/// the match already shows:
///
/// * **The water** stands in the hollow the painted pond was in, and a
///   spring at the head of the valley west of it feeds a stream that finds
///   its own way down the low line of the ground into it. The crowd fords it
///   as it walks anything else; the sim's ground is the stream's bed and
///   nothing more.
/// * **A hall catches fire when it is attacked**: armed units of the other
///   side shooting from beside it. Buildings have no health in the match, so
///   what burns is the hall as drawn — the timber under the roofs of its
///   keep and its towers, bodies of their own that char the castle as they
///   go — and the hall goes on working, blackened, for as long as the match
///   says it stands.
/// * **The woods burn** from what falls into them: brands thrown up out of
///   a flame and carried by the wind, and then tree to tree by the heat of
///   their own flames, leaning with the wind and so running downwind. A tree
///   burnt out is left as a black snag.
/// * **A ram's strike throws stones** — at the wall it is working at, where
///   pieces of the wall break off and tumble, or at the units it fights —
///   which bounce on the ground and come to rest.
///
/// What the camera's side cannot see starts nothing: a fight under the fog
/// throws no stones and lights no hall, so the fires never tell a player
/// about a battle the map is careful not to show.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Heightfield;
import 'package:vector_math/vector_math.dart';

import 'staging.dart';

/// A thing thrown or knocked loose, and what draws it.
final class _Piece {
  _Piece(this.body, this.node);

  final NativeBody body;
  final MeshNode node;

  /// The hall a stone was thrown at, until it reaches it.
  _Hall? aim;

  /// Seconds since it was made.
  double age = 0.0;
}

/// A hall as the fires see it: the timber of its roofs and its yard, and
/// the stone that stones strike.
final class _Hall {
  _Hall(this.index, this.building);

  /// Where it is in `simulation.buildings`.
  final int index;
  final Building building;

  /// What burns: the keep's roof first, then the towers'.
  final List<NativeBody> timbers = <NativeBody>[];

  /// How hard each timber has been hit since it last caught: past
  /// [MapEffects._catches] it is alight.
  final List<double> wounds = <double>[];

  /// How much each timber had to burn before anything caught.
  final List<double> fuels = <double>[];

  /// The castle drawn for it and the colour it was drawn in, once anything
  /// of it has caught: what the soot darkens.
  MeshNode? look;
  Vector4? fresh;
}

/// A tree of the map's woods, and the body it burns as once the camera's
/// side has found it.
final class _Tree {
  _Tree(this.batch, this.placement, this.planted)
    : x = planted.storage[12],
      z = planted.storage[14],
      base = planted.storage[13] + 0.2,
      size = math.sqrt(
        planted.storage[0] * planted.storage[0] +
            planted.storage[1] * planted.storage[1] +
            planted.storage[2] * planted.storage[2],
      );

  final int batch, placement;
  final Matrix4 planted;
  final double x, z, base;

  /// How much its model is scaled: about its height, in metres, over one
  /// and a half.
  final double size;

  NativeBody? body;
  double fuel = 0.0;

  /// How black it is drawn, nought to one, and whether it has burnt out.
  double charred = 0.0;
  bool dead = false;

  /// The crown, where the body is: as wide as about a third of the scale,
  /// from a quarter of the way up to the top.
  double get radius => 0.28 * size;
  double get middle => base + 0.85 * size;
  double get halfHeight => 0.45 * size;
}

/// The water, fire and thrown stones over one map, drawn into a scene
/// through a renderer.
final class MapEffects {
  MapEffects._({
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required LiquidLook water,
    required Heightfield ground,
    required bool light,
  }) : _scene = scene,
       _light = light,
       _water = water,
       _field = ground {
    world.gravity = Vector3(0.0, -9.81, 0.0);
    _floor(ground);
    _river = _pour(ground);
    _riverView = LiquidView(
      world: world,
      liquid: _river,
      ground: _ground,
      device: device,
      scene: scene,
      look: water.material,
      detail: light ? LiquidDetail.light : LiquidDetail.full,
    );
    _fire = FireView(
      world: world,
      device: device,
      scene: scene,
      renderer: renderer,
      // A crown's or a roof's thickness: what sizes the tongues, and the
      // smoke's first puffs. At 0.9 a pine's flame was drawn twice as wide
      // as the pine and a few crowns made a cloud the size of a hall.
      baseWidth: 0.6,
      detail: light ? FireDetail.light : FireDetail.full,
    );
    _stoneMesh = DeviceMesh.upload(
      device,
      const SphereShape(radius: 1.0, segments: 10, rings: 7).build(),
    );
    _blockMesh = DeviceMesh.upload(
      device,
      CuboidShape(size: Vector3.all(2.0)).build(),
    );
    hearing.listen(_river);
  }

  /// Opens the effects over [ground]: loads the water's look through
  /// [renderer] and lets the stream run until it has reached the pond.
  static Future<MapEffects> open({
    required GraphicsDevice device,
    required Scene scene,
    required Renderer renderer,
    required Heightfield ground,
    required Vector3 sunAlong,
    required Vector3 sunLight,
  }) async {
    final water = await LiquidLook.load(
      device: device,
      renderer: renderer,
      bundle: await rootBundle.load(LiquidLook.asset),
    );
    water
      ..sun(along: sunAlong, light: sunLight)
      // A hill pond over earth, and a stream stirring it up: grey-green
      // and cloudy, letting through a share of a thousand a metre, so that
      // even the stream's ten centimetres read as water over the grass.
      ..tint(
        shallow: Vector3(0.16, 0.30, 0.33),
        deep: Vector3(0.04, 0.11, 0.14),
        clearness: 0.003,
      );
    final phone =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return MapEffects._(
      device: device,
      scene: scene,
      renderer: renderer,
      water: water,
      ground: ground,
      light: phone,
    ).._settle();
  }

  /// The world everything here lives in, and nothing of the match does.
  final NativeWorld world = NativeWorld();

  /// What the fires, the stream and the splashes sound like this frame.
  late final PhysicsHearing hearing = PhysicsHearing(world);

  final Scene _scene;

  /// Whether this is a phone, drawing less and burning fewer fires.
  final bool _light;
  final LiquidLook _water;
  final Heightfield _field;
  late final NativeShallowLiquid _river;

  /// The ground under the water as it is drawn, which the view sinks dry
  /// cells beneath: not the banks the water runs between.
  late final List<double> _ground;
  late final LiquidView _riverView;
  late final FireView _fire;
  late final DeviceMesh _stoneMesh, _blockMesh;
  final math.Random _random = math.Random(17);

  Staged? _staged;
  final List<_Hall> _halls = <_Hall>[];
  final List<_Tree> _trees = <_Tree>[];

  /// The trees by the [_lattice]-metre square they stand in.
  final Map<int, List<_Tree>> _byCell = <int, List<_Tree>>{};

  /// The trees that have a body, and those that have none yet.
  final List<_Tree> _burnable = <_Tree>[];
  final List<_Tree> _bare = <_Tree>[];
  final Map<NativeBody, _Tree> _treeOf = <NativeBody, _Tree>{};

  final List<_Piece> _stones = <_Piece>[];
  final List<_Piece> _brands = <_Piece>[];

  /// What each armed unit's cooldown read at the last frame: a cooldown that
  /// has grown since is a shot fired.
  final Expando<double> _cooldowns = Expando<double>('cooldown');

  double _clock = 0.0, _looked = 0.0;

  // ----------------------------------------------------------------- numbers

  /// The water's grid: a metre a cell, from the spring's valley to past the
  /// pond's east shore.
  static const double _x0 = 48.0, _z0 = 44.0;
  static const int _nx = 90, _nz = 40;

  /// Where the stream rises, and how much, m³/s: as much as sinks where
  /// it ends.
  static const double _springX = 52.0, _springZ = 62.0, _flow = 0.4;

  /// How high the pond stands, as it is painted.
  static const double _pondLevel = 0.3;

  /// What a tree's crown and a roof's timber are as fire sees them: dry
  /// leaves and thatch, catching as paper does.
  ///
  /// **Burning about as fast as paper**, a pine's crown going in a minute
  /// or two. A quarter of that was tried first, for crowns that would last;
  /// what it gave was a tongue of flame the size of a hand on the side of a
  /// green tree for minutes on end, too weak to light the next crown, so a
  /// wood set alight never spread and never blackened. A conifer crown in a
  /// real fire torches in well under a minute.
  static final NativeMaterial _dry = () {
    final p = NativeMaterial.paper();
    return NativeMaterial(
      specificHeat: p.specificHeat,
      emissivity: p.emissivity,
      ignitionTemperature: p.ignitionTemperature,
      heatOfCombustion: p.heatOfCombustion,
      burnRate: 0.025,
      fuelFraction: p.fuelFraction,
      flameFeedback: p.flameFeedback,
      conductivity: p.conductivity,
      flameTemperature: p.flameTemperature,
      flameConvection: p.flameConvection,
      flameRadiant: p.flameRadiant,
      flameAbsorption: p.flameAbsorption,
    );
  }();

  /// How hard a timber must be hit to catch: three stones, or nine shots.
  static const double _catches = 3.0;

  /// The most fires burning at once, a phone's fewer: the core's heat from
  /// a fire to everything near it costs most of a millisecond a step for
  /// each, and the match's frame comes first. Past it no brand is thrown,
  /// and no crown catches.
  int get _mostFires => _light ? 3 : 6;

  /// How far from a fire a tree is given a body, m: further than a crown's
  /// flame leans, and than most brands fly.
  static const double _near = 14.0;

  /// How much ground around a tree the camera's side must have found before
  /// the tree can catch, m: about as far as a crown's flame and the first of
  /// its smoke lean downwind.
  static const double _margin = 6.0;

  /// The most brands in the air, and stones and pieces on the ground.
  static const int _mostBrands = 6, _mostStones = 32;

  /// The brightest the fires' light on the map is let be.
  static const double _mostGlow = 3.0;

  /// The side of a square of [_byCell], m.
  static const double _lattice = 8.0;

  // ------------------------------------------------------------------ ground

  /// The map's ground as one fixed mesh, triangulated as it is drawn.
  void _floor(Heightfield field) {
    final columns = field.columns, rows = field.rows;
    final points = <Vector3>[
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < columns; c++)
          Vector3(
            field.origin.x + c * field.cellSize,
            field.origin.y + field.sample(c, r),
            field.origin.z + r * field.cellSize,
          ),
    ];
    final indices = <int>[
      for (var r = 0; r < rows - 1; r++)
        for (var c = 0; c < columns - 1; c++) ...<int>[
          // The diagonal from (c, r) to (c + 1, r + 1), as `heightAt` has
          // it, each triangle wound to face up.
          c + r * columns,
          c + 1 + (r + 1) * columns,
          c + 1 + r * columns,
          c + r * columns,
          c + (r + 1) * columns,
          c + 1 + (r + 1) * columns,
        ],
    ];
    final floor = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
      mass: 0.0,
    );
    world
      ..setMesh(floor, world.createMesh(points, indices))
      ..setMaterial(floor, NativeMaterial.stone());
  }

  /// The pond filled to its painted level, and the stream down the valley
  /// west of it.
  ///
  /// **The stream runs between banks nobody sees.** Left to the hillside as
  /// it is, the water from the spring spread into a film a few millimetres
  /// deep and ten metres wide, which from where the camera hangs is no water
  /// at all. A stream has worn itself a bed; this ground has not, and carving
  /// one would put the water under the grass that is drawn over it. So the
  /// water's own ground is raised instead, a hand's height either side of the
  /// line the stream takes: it runs a couple of metres wide and ten
  /// centimetres deep down the middle, standing over the grass where it is
  /// drawn.
  ///
  /// **It sinks where the valley tips into the pond's hollow.** Below that
  /// the bank falls one in two and a half, and ten centimetres of water
  /// sliding down it is a film no surface can be drawn for: every cell of it
  /// is perched over the next, and it was drawn as nothing at all, a stream
  /// that stopped in the grass. So it ends where it can still be drawn, in
  /// the ground at the rim, as a stream over a hill's loose rock does; the
  /// pond, with nothing running in, keeps its level.
  NativeShallowLiquid _pour(Heightfield field) {
    _ground = <double>[
      for (var j = 0; j < _nz; j++)
        for (var i = 0; i < _nx; i++)
          field.heightAt(_x0 + i + 0.5, _z0 + j + 0.5),
    ];
    final List<Vector2> line = _lowLine(field);
    final bed = <double>[
      for (var j = 0; j < _nz; j++)
        for (var i = 0; i < _nx; i++)
          _ground[i + j * _nx] +
              _bank(
                _ground[i + j * _nx],
                _away(line, _x0 + i + 0.5, _z0 + j + 0.5),
              ),
    ];
    final river = world.createShallowLiquid(
      nx: _nx,
      nz: _nz,
      cell: 1.0,
      origin: Vector3(_x0, 0.0, _z0),
      ground: bed,
    );
    world
      ..setShallowBed(river, roughness: 0.035)
      ..fillShallowLiquid(
        river,
        x0: _x0 + 48.0,
        z0: _z0,
        x1: _x0 + _nx,
        z1: _z0 + _nz,
        level: _pondLevel,
      )
      ..setShallowSource(
        river,
        0,
        x: _springX,
        z: _springZ,
        radius: 1.2,
        rate: _flow,
      )
      ..setShallowSource(
        river,
        1,
        x: line.last.x,
        z: line.last.y,
        radius: 1.5,
        rate: -_flow,
      );
    return river;
  }

  /// The line water takes from the spring down the valley: the steepest
  /// way, two metres at a time, as far as the ground falls no faster than
  /// one in four.
  static List<Vector2> _lowLine(Heightfield field) {
    final line = <Vector2>[Vector2(_springX, _springZ)];
    while (line.length < 100) {
      final Vector2 at = line.last;
      final double here = field.heightAt(at.x, at.y);
      var lowest = here;
      Vector2? next;
      for (var k = 0; k < 32; k++) {
        final double a = k * math.pi / 16.0;
        final step = at + Vector2(2.0 * math.cos(a), 2.0 * math.sin(a));
        final double h = field.heightAt(step.x, step.y);
        if (h < lowest) {
          lowest = h;
          next = step;
        }
      }
      if (next == null || here - lowest > 0.5) break;
      line.add(next);
    }
    return line;
  }

  /// How far `(x, z)` is from [line], m.
  static double _away(List<Vector2> line, double x, double z) {
    final p = Vector2(x, z);
    var away = double.infinity;
    for (var k = 0; k + 1 < line.length; k++) {
      final Vector2 a = line[k];
      final Vector2 ab = line[k + 1] - a;
      final double t = ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
      away = math.min(away, (p - (a + ab * t)).length);
    }
    return away;
  }

  /// How much the water's ground is raised [away] metres from the stream's
  /// line, over ground [height] high: nothing in its two-metre bed, forty
  /// centimetres on the banks a metre either side of it, and nothing again
  /// past them or at the pond, whose shore is the hollow's own.
  static double _bank(double height, double away) {
    if (height < _pondLevel + 0.3) return 0.0;
    return 0.4 *
        ((away - 1.1) / 1.0).clamp(0.0, 1.0) *
        ((5.0 - away) / 1.0).clamp(0.0, 1.0);
  }

  /// Half a minute of the stream run before the first frame, so the map
  /// opens with water already in its bed rather than a spring just starting.
  void _settle() {
    for (var i = 0; i < 300; i++) {
      world.step(0.1);
    }
    _riverView.update();
  }

  // ------------------------------------------------------------------- match

  /// Watches [staged]'s match: its halls and its woods, from now on.
  ///
  /// Called again for every match the run opens; what the last one left —
  /// its fires, its stones, its trees — is cleared away first.
  void follow(Staged staged) {
    for (final _Hall hall in _halls) {
      hall.timbers.forEach(world.removeBody);
    }
    for (final _Tree tree in _burnable) {
      world.removeBody(tree.body!);
    }
    for (final _Piece piece in <_Piece>[..._stones, ..._brands]) {
      world.removeBody(piece.body);
      _scene.remove(piece.node);
    }
    _halls.clear();
    _trees.clear();
    _byCell.clear();
    _burnable.clear();
    _bare.clear();
    _treeOf.clear();
    _stones.clear();
    _brands.clear();
    _staged = staged;

    // The painted sheet gives way to the water that moves.
    staged.visuals.water?.visible = false;

    final List<Building> buildings = staged.simulation.buildings;
    for (var i = 0; i < buildings.length; i++) {
      _halls.add(_build(i, buildings[i]));
    }
    for (var b = 0; b < staged.visuals.propBatchCount; b++) {
      final List<Matrix4> placed = staged.visuals.propPlacementsOf(b);
      for (var p = 0; p < placed.length; p++) {
        final tree = _Tree(b, p, placed[p]);
        _trees.add(tree);
        _bare.add(tree);
        (_byCell[_cellOf(tree.x, tree.z)] ??= <_Tree>[]).add(tree);
      }
    }
  }

  static int _cellOf(double x, double z) =>
      (x / _lattice).floor() * 4096 + (z / _lattice).floor();

  /// The bodies of the castle drawn for [building]: its stone, for stones
  /// to strike, and the timber that burns.
  ///
  /// Placed from the castle's own layout in `kit.dart` — towers at the
  /// corners, the keep at the back, all of it about twice its kit's size.
  _Hall _build(int index, Building building) {
    final hall = _Hall(index, building);
    final Vector3 c = building.centre;
    final double k = (building.width / 6.0 + building.depth / 5.0) / 2.0;
    void stone(Vector3 at, Vector3 half) {
      final body = world.addBody(
        position: c + at,
        type: NativeBodyType.fixed,
        mass: 0.0,
      );
      world
        ..setShape(body, NativeShape.box(half))
        ..setMaterial(body, NativeMaterial.stone());
    }

    stone(
      Vector3(0.0, 0.55 * k, 0.0),
      Vector3(building.width / 2.0, 0.55 * k, building.depth / 2.0),
    );
    stone(Vector3(0.0, 2.2 * k, -0.6 * k), Vector3(k, 2.2 * k, k));

    void timber(Vector3 at, Vector3 half, double mass) {
      final body = world.addBody(
        position: c + at,
        type: NativeBodyType.fixed,
        mass: mass,
      );
      world
        ..setShape(body, NativeShape.box(half))
        ..setMaterial(body, _dry);
      hall.timbers.add(body);
      hall.wounds.add(0.0);
      hall.fuels.add(world.fuelOf(body));
    }

    timber(Vector3(0.0, 4.7 * k, -0.6 * k), Vector3.all(0.8 * k), 90.0);
    for (final (double x, double z) in <(double, double)>[
      (-2.5, -2.0),
      (2.5, -2.0),
      (-2.5, 2.0),
      (2.5, 2.0),
    ]) {
      timber(
        Vector3(x * k, 2.6 * k, z * k),
        Vector3(0.4 * k, 0.3 * k, 0.4 * k),
        30.0,
      );
    }
    return hall;
  }

  // ------------------------------------------------------------------- frame

  /// The world on by [dt]: what the match did since the last frame read off
  /// it, the water, the fires and the stones stepped, and drawn from [eye].
  void update(double dt, {required Vector3 eye}) {
    final Staged? staged = _staged;
    if (staged == null || dt <= 0.0) return;
    _clock += dt;
    _wind();
    _looked -= dt;
    if (_looked <= 0.0) {
      _looked = 0.5;
      _find();
    }
    _shots(staged);
    _throwBrands(dt);
    world.step(dt);
    _events();
    _fly(dt);
    _char(staged);
    _riverView.update();
    _fire.update(dt);
    // The fires' glow on the ground held to a fraction of the sun's: lit
    // by a light as strong as their power, a few burning pines turned the
    // grass around them yellow-white at noon, which a fire in daylight
    // does not do.
    _fire.light.intensity = math.min(_fire.light.intensity, _mostGlow);
    hearing.update(dt);
    _water.update(seconds: _clock, eye: eye);
  }

  /// A fresh breeze along +x and a little +z, five metres a second, its
  /// heading wandering a quarter of a right angle either way over a few
  /// minutes and its strength in gusts. Fresh enough to lean a burning
  /// crown's flame into the next crown downwind, and not the one upwind.
  void _wind() {
    final double heading =
        0.38 + 0.4 * math.sin(_clock / 53.0) + 0.15 * math.sin(_clock / 7.3);
    final double speed = 5.0 + 1.2 * math.sin(_clock / 3.1);
    world.wind = Vector3(
      speed * math.cos(heading),
      0.0,
      speed * math.sin(heading),
    );
  }

  /// Gives a body to every tree the camera's side has found that stands
  /// within [_near] metres of a fire.
  ///
  /// **Found**, with the ground around it, because a tree under the fog is
  /// not drawn, and a fire in it would be a flame standing on nothing: see
  /// [_found]. **Near a fire**, because every body a flame could warm is one
  /// the core looks at for every fire, every step: a map's whole wood given
  /// bodies made each burning crown cost a millisecond, and a wood a fire is
  /// nowhere near has nothing to say.
  void _find() {
    final (:fires, :bodies) = world.readFires();
    if (bodies.isEmpty) return;
    const n = nativeFireFloats;
    _bare.removeWhere((_Tree tree) {
      var near = false;
      for (var k = 0; k < bodies.length && !near; k++) {
        final double dx = fires[n * k] - tree.x, dz = fires[n * k + 2] - tree.z;
        near = dx * dx + dz * dz < _near * _near;
      }
      if (!near || !_found(tree)) return false;
      _grow(tree);
      return true;
    });
  }

  /// [tree]'s crown as a body that can burn.
  void _grow(_Tree tree) {
    final body = world.addBody(
      position: Vector3(tree.x, tree.middle, tree.z),
      type: NativeBodyType.fixed,
      // The crown's leaves and twigs: what burns of a tree in a fire that
      // runs through a wood, not its trunk.
      mass: 12.0 * tree.size,
    );
    world
      ..setShape(body, NativeShape.cylinder(tree.radius, tree.halfHeight))
      ..setMaterial(body, _dry);
    tree
      ..body = body
      ..fuel = world.fuelOf(body);
    _burnable.add(tree);
    _treeOf[body] = tree;
  }

  /// Every shot fired since the last frame that the camera's side can see,
  /// and what it strikes: a hall of the other side beside the shooter, or
  /// for a ram, the unit it works at.
  void _shots(Staged staged) {
    final StrategySimulation simulation = staged.simulation;
    for (final Unit unit in simulation.units) {
      if (!unit.type.isArmed) continue;
      final double was = _cooldowns[unit] ?? unit.cooldown;
      _cooldowns[unit] = unit.cooldown;
      if (unit.cooldown <= was + 1e-6) continue;
      final Vector3 at = unit.position;
      if (unit.side != viewerSide &&
          !simulation.fog.sees(viewerSide, at.x, at.z)) {
        continue;
      }
      final bool ram = unit.type.name == UnitType.tank.name;
      final _Hall? hall = _hallBeside(unit);
      if (hall != null) {
        if (ram) {
          _throwAt(at, _onWall(hall.building, at), hall);
        } else {
          // Fire arrows, or a torch over the wall: the timber nearest the
          // shooter warms by a third of what a stone does.
          _wound(hall, at, 1.0 / 3.0);
        }
      } else if (ram) {
        final Unit? mark = _markOf(unit, simulation);
        if (mark != null) {
          _throwAt(at, mark.position + Vector3(0.0, 0.3, 0.0), null);
        }
      }
    }
  }

  /// The hall of another side [unit] stands close enough to to be hitting.
  _Hall? _hallBeside(Unit unit) {
    for (final _Hall hall in _halls) {
      final Building b = hall.building;
      if (b.side == unit.side) continue;
      if (b.distanceTo(unit.position.x, unit.position.z) <=
          unit.type.range + 3.0) {
        return hall;
      }
    }
    return null;
  }

  /// Who [unit] is shooting at, as near as the picture can tell: its order's
  /// target, or else the nearest unit of another side in its reach.
  static Unit? _markOf(Unit unit, StrategySimulation simulation) {
    if (unit.order.target case final Unit told when told.isAlive) return told;
    final double reach = unit.type.range + 1.0;
    Unit? best;
    var bestAt = reach * reach;
    for (final Unit other in simulation.units) {
      if (other.side == unit.side || !other.isAlive) continue;
      final double dx = other.position.x - unit.position.x;
      final double dz = other.position.z - unit.position.z;
      final double d = dx * dx + dz * dz;
      if (d < bestAt) {
        bestAt = d;
        best = other;
      }
    }
    return best;
  }

  /// The point on [building]'s wall nearest [from], partway up it.
  Vector3 _onWall(Building building, Vector3 from) {
    final Vector3 c = building.centre;
    final double k = (building.width / 6.0 + building.depth / 5.0) / 2.0;
    return Vector3(
      from.x.clamp(c.x - building.width / 2.0, c.x + building.width / 2.0) +
          (_random.nextDouble() - 0.5),
      c.y + (0.5 + 0.5 * _random.nextDouble()) * k,
      from.z.clamp(c.z - building.depth / 2.0, c.z + building.depth / 2.0) +
          (_random.nextDouble() - 0.5),
    );
  }

  /// A stone lobbed from a ram at [from] to land on [to] in under a second,
  /// a few of them for a strike on a wall.
  void _throwAt(Vector3 from, Vector3 to, _Hall? hall) {
    final start = from + Vector3(0.0, 1.5, 0.0);
    const double flight = 0.8;
    final velocity = (to - start)
      ..scale(1.0 / flight)
      ..y += 0.5 * 9.81 * flight;
    final stone = _stone(
      start,
      velocity,
      radius: 0.22 + 0.08 * _random.nextDouble(),
      colour: Vector4(0.42, 0.40, 0.37, 1.0),
    )..aim = hall;
    hearing.watch(stone.body, _river);
  }

  /// [hall] struck near [at] by [weight] of a stone: its timber nearest the
  /// strike warms, and catches once it has taken [_catches].
  void _wound(_Hall hall, Vector3 at, double weight) {
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < hall.timbers.length; i++) {
      final double d = (world.positionOf(hall.timbers[i]) - at).length2;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    final NativeBody timber = hall.timbers[nearest];
    if (world.isBurning(timber) || world.fuelOf(timber) <= 0.0) return;
    hall.wounds[nearest] += weight;
    if (hall.wounds[nearest] < _catches) return;
    hall.wounds[nearest] = 0.0;
    world.setTemperature(timber, 750.0);
    _watch(hall);
  }

  /// Starts sooting the castle drawn for [hall], once anything of it has
  /// caught.
  ///
  /// **Not [FireView.watch]**, which chars a body's own look and makes it
  /// glow while it burns: the castle is one model, stone walls and timber
  /// roofs together, and a whole castle glowing like an ember because one
  /// tower's roof is alight read as a castle lit pink. Here the stone only
  /// darkens, by how much of its timber has gone.
  void _watch(_Hall hall) {
    if (hall.look != null) return;
    final MeshNode? node = _staged?.visuals.buildingAt(hall.index);
    if (node == null) return;
    hall
      ..look = node
      ..fresh = node.material.baseColor.clone();
  }

  /// What the steps said: a timber or a tree catching from its neighbour's
  /// flame, and a fire burnt out.
  ///
  /// A crown catching while [_mostFires] already burn smoulders and goes
  /// out instead: the fire front holds where it is until a crown behind it
  /// burns out, and a whole wood is never alight at once.
  void _events() {
    var burning = _fire.burning;
    for (final NativeEvent event in world.readEvents()) {
      if (event.kind == NativeEventKind.ignited) {
        burning++;
        for (final _Hall hall in _halls) {
          if (hall.timbers.contains(event.body)) _watch(hall);
        }
        if (burning > _mostFires && _treeOf.containsKey(event.body)) {
          world.setTemperature(event.body, 340.0);
          burning--;
        }
      } else if (event.kind == NativeEventKind.burntOut) {
        final _Tree? tree = _treeOf[event.body];
        if (tree != null) tree.dead = true;
      }
    }
  }

  /// Brands thrown up from the tips of the flames, now and then, into the
  /// wind: burning tinder that a wood downwind of a fire catches from.
  void _throwBrands(double dt) {
    if (_brands.length >= _mostBrands || _fire.burning >= _mostFires) return;
    final (:fires, :bodies) = world.readFires();
    const n = nativeFireFloats;
    for (var k = 0; k < bodies.length; k++) {
      if (_brands.length >= _mostBrands) return;
      // A big fire throws more: about one every four seconds from a
      // megawatt.
      final double megawatts = fires[n * k + 3] / 1e6;
      if (_random.nextDouble() > dt * megawatts / 4.0) continue;
      final double reach = fires[n * k + 4];
      final tip = Vector3(
        fires[n * k] + fires[n * k + 5] * reach * 0.4,
        fires[n * k + 1] + fires[n * k + 6] * reach * 0.4,
        fires[n * k + 2] + fires[n * k + 7] * reach * 0.4,
      );
      final Vector3 air = world.windAt(tip);
      final body = world.addBody(position: tip, mass: 0.3);
      // Glowing, not alight: a brand is a few grams of tinder, and its own
      // flame would be drawn a tree's width wide.
      world
        ..setShape(body, const NativeShape.sphere(0.12))
        ..setVelocity(
          body,
          air * 1.2 +
              Vector3(
                (_random.nextDouble() - 0.5) * 3.0,
                1.0 + 2.5 * _random.nextDouble(),
                (_random.nextDouble() - 0.5) * 3.0,
              ),
        );
      final node = MeshNode(
        _stoneMesh,
        Material(
          name: 'brand',
          baseColor: Vector4(0.1, 0.05, 0.02, 1.0),
          emissive: Vector3(3.0, 0.9, 0.2),
        ),
        name: 'brand',
      )..setScale(0.12, 0.12, 0.12);
      _scene.add(node);
      _brands.add(_Piece(body, node));
    }
  }

  /// The stones, the pieces and the brands moved to where their bodies are;
  /// a stone at its wall breaks pieces off it, a brand in a crown lights it.
  void _fly(double dt) {
    // Struck after the walk, not during it: what breaks off a wall is more
    // stones, and the list being walked is theirs.
    final struck = <(_Hall, Vector3)>[];
    for (final _Piece piece in _stones) {
      piece.age += dt;
      final Vector3 at = world.positionOf(piece.body);
      piece.node
        ..setPosition(at.x, at.y, at.z)
        ..setRotation(world.orientationOf(piece.body));
      final _Hall? hall = piece.aim;
      if (hall == null) continue;
      final Building b = hall.building;
      if (b.distanceTo(at.x, at.z) < 0.7 || piece.age > 1.5) {
        piece.aim = null;
        if (piece.age <= 1.5) struck.add((hall, at));
      }
    }
    for (final (_Hall hall, Vector3 at) in struck) {
      _breakOff(hall, at);
    }
    while (_stones.length > _mostStones) {
      final _Piece old = _stones.removeAt(0);
      hearing.forget(old.body);
      world.removeBody(old.body);
      _scene.remove(old.node);
    }

    _brands.removeWhere((_Piece brand) {
      brand.age += dt;
      final Vector3 at = world.positionOf(brand.body);
      brand.node.setPosition(at.x, at.y, at.z);
      final _Tree? caught = _crownAt(at);
      final bool down =
          caught != null ||
          brand.age > 7.0 ||
          at.y < _field.heightAt(at.x, at.z) + 0.25;
      if (!down) return false;
      if (caught != null) {
        if (caught.body == null) {
          _bare.remove(caught);
          _grow(caught);
        }
        world.setTemperature(caught.body!, 700.0);
      }
      world.removeBody(brand.body);
      _scene.remove(brand.node);
      return true;
    });
  }

  /// The tree whose crown [at] is inside, and that can still catch: one
  /// with a body not yet alight, or one the camera's side has found that
  /// has none yet.
  _Tree? _crownAt(Vector3 at) {
    final int cx = (at.x / _lattice).floor(), cz = (at.z / _lattice).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dz = -1; dz <= 1; dz++) {
        for (final _Tree tree
            in _byCell[(cx + dx) * 4096 + cz + dz] ?? const <_Tree>[]) {
          if (tree.dead) continue;
          final double ddx = at.x - tree.x, ddz = at.z - tree.z;
          final double r = tree.radius + 0.8;
          if (ddx * ddx + ddz * ddz > r * r) continue;
          if ((at.y - tree.middle).abs() > tree.halfHeight + 0.5) continue;
          final NativeBody? body = tree.body;
          if (body != null ? world.isBurning(body) : !_found(tree)) continue;
          return tree;
        }
      }
    }
    return null;
  }

  /// Whether the camera's side has found [tree] and the ground for
  /// [_margin] metres around it.
  ///
  /// **Not the tree alone.** A crown at the edge of what has been explored
  /// burned with its flame leaning out over the black, and its smoke drawn
  /// across ground the map has not shown yet; a tree that close to the fog
  /// does not catch, so the fire stops where the map stops.
  bool _found(_Tree tree) {
    final FogOfWar? fog = _staged?.simulation.fog;
    if (fog == null) return false;
    bool knows(double dx, double dz) =>
        fog.knows(viewerSide, tree.x + dx, tree.z + dz);
    return knows(0.0, 0.0) &&
        knows(_margin, 0.0) &&
        knows(-_margin, 0.0) &&
        knows(0.0, _margin) &&
        knows(0.0, -_margin);
  }

  /// Pieces of [hall]'s wall knocked loose where a stone struck it at [at],
  /// thrown back off the wall; and the strike counted against its timber.
  void _breakOff(_Hall hall, Vector3 at) {
    final Vector3 c = hall.building.centre;
    final out = Vector3(at.x - c.x, 0.0, at.z - c.z);
    if (out.length2 < 1e-6) out.setValues(0.0, 0.0, 1.0);
    out.normalize();
    final int pieces = 2 + _random.nextInt(3);
    for (var i = 0; i < pieces; i++) {
      final double half = 0.15 + 0.2 * _random.nextDouble();
      final start = at + out * 0.6 + Vector3(0.0, 0.3 * i, 0.0);
      final body = world.addBody(position: start, mass: 2000.0 * half * half);
      world
        ..setShape(body, NativeShape.box(Vector3(half, half * 0.7, half)))
        ..setMaterial(body, NativeMaterial.stone())
        ..setVelocity(
          body,
          out * (2.0 + 2.5 * _random.nextDouble()) +
              Vector3(
                (_random.nextDouble() - 0.5) * 2.5,
                1.5 + 2.0 * _random.nextDouble(),
                (_random.nextDouble() - 0.5) * 2.5,
              ),
        )
        ..setAngularVelocity(
          body,
          Vector3(
            _random.nextDouble() * 6.0 - 3.0,
            _random.nextDouble() * 6.0 - 3.0,
            _random.nextDouble() * 6.0 - 3.0,
          ),
        );
      final node = MeshNode(
        _blockMesh,
        Material(
          name: 'rubble',
          // The castle's sandstone, a little dirtier for having come off.
          baseColor: Vector4(0.80, 0.68, 0.52, 1.0),
          roughness: 0.95,
        ),
        name: 'rubble',
      )..setScale(half, half * 0.7, half);
      _scene.add(node);
      _stones.add(_Piece(body, node));
      hearing.watch(body, _river);
    }
    _wound(hall, at, 1.0);
  }

  _Piece _stone(
    Vector3 at,
    Vector3 velocity, {
    required double radius,
    required Vector4 colour,
  }) {
    final body = world.addBody(
      position: at,
      mass: 2600.0 * 4.2 * radius * radius * radius,
    );
    world
      ..setShape(body, NativeShape.sphere(radius))
      ..setMaterial(body, NativeMaterial.stone())
      ..setVelocity(body, velocity);
    final node = MeshNode(
      _stoneMesh,
      Material(name: 'stone', baseColor: colour, roughness: 0.9),
      name: 'stone',
    )..setScale(radius, radius, radius);
    _scene.add(node);
    final piece = _Piece(body, node);
    _stones.add(piece);
    return piece;
  }

  /// Every tree with a body drawn as burnt as it is: blackening as its crown
  /// goes, and once burnt out, a bare black snag. A castle whose timber has
  /// caught darkens with soot by as much of it as has burnt, to under half
  /// its colour once a third has gone.
  void _char(Staged staged) {
    for (final _Hall hall in _halls) {
      final MeshNode? look = hall.look;
      final Vector4? fresh = hall.fresh;
      if (look == null || fresh == null) continue;
      var burnt = 0.0;
      for (var i = 0; i < hall.timbers.length; i++) {
        if (hall.fuels[i] <= 0.0) continue;
        burnt += 1.0 - world.fuelOf(hall.timbers[i]) / hall.fuels[i];
      }
      final double soot = math.min(1.0, 3.0 * burnt / hall.timbers.length);
      look.material.baseColor
        ..setFrom(fresh)
        ..scale(1.0 - 0.55 * soot)
        ..w = fresh.w;
    }
    for (final _Tree tree in _burnable) {
      final NativeBody body = tree.body!;
      final double burnt = tree.fuel > 0.0
          ? 1.0 - world.fuelOf(body) / tree.fuel
          : 0.0;
      final double black = math.min(1.0, burnt * 3.0);
      if (tree.charred >= 2.0) continue;
      if (!tree.dead && black - tree.charred < 0.02) continue;
      final double g = tree.dead ? 0.1 : 1.0 - 0.9 * black;
      final bool drawn = staged.visuals.dressProp(
        tree.batch,
        tree.placement,
        colour: Vector4(g, g * 0.97, g * 0.93, 1.0),
        transform: tree.dead
            ? (tree.planted.clone()..scaleByDouble(0.45, 0.85, 0.45, 1.0))
            : null,
      );
      if (!drawn) continue;
      // Two marks a snag already drawn as one, so it is not drawn again.
      tree.charred = tree.dead ? 2.0 : black;
    }
  }

  /// The world given back, for the window closing.
  void dispose() => world.dispose();
}
