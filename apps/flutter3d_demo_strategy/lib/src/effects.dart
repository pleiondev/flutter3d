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
///   spring at the head of the valley west of it feeds a small river that
///   winds down the low line of the ground, past stones, and tumbles down
///   the steep bank of the pond's hollow over a few small falls into it.
///   Where the way between the halls crosses it, it spreads into a wide
///   shallow ford. The crowd fords it as it walks anything else; the sim's
///   ground is the river's bed and nothing more.
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

import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_effects/flutter3d_effects.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show Heightfield;
import 'package:vector_math/vector_math.dart';

import 'staging.dart';
import 'woods.dart' show nearestSeam;

/// A stone in the river: where, how far down it, m, how big, and the level
/// of the bed it stands on.
typedef _Stone = ({Vector2 at, double down, double size, double level});

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
    final List<double> bed = _survey(ground);
    _river = _pour(bed);
    final Set<MeshNode> before = scene.meshes.toSet();
    _riverView = LiquidView(
      world: world,
      liquid: _river,
      ground: bed,
      device: device,
      scene: scene,
      look: water.material,
      detail: light ? LiquidDetail.light : LiquidDetail.full,
    );
    // No mist off the falls. A puff of it is a cloud a metre or two
    // across, which close under a falls is a haze, and from where the map's
    // camera hangs is a white ball: a string of them stood down the river
    // like beads.
    for (final MeshNode node in scene.meshes) {
      if (!before.contains(node) && node.name == 'mist') node.visible = false;
    }
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
    _drawBoulders();
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
      // A hill pond over earth, and a river stirring it up: green and
      // cloudy, letting through two parts in a thousand a metre, and darker
      // than the grass it runs through. Looked down on from where the
      // camera hangs the water mirrors almost nothing, so its own colour is
      // all that tells it from the grass: a pale grey-green, as it was,
      // read from up there as a wet strip.
      ..tint(
        shallow: Vector3(0.09, 0.22, 0.25),
        deep: Vector3(0.02, 0.07, 0.10),
        clearness: 0.002,
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

  /// The ground as it is drawn at the middle of each of the water's cells.
  late final List<double> _terrain;

  /// The river's course from the spring into the pond, a point every half
  /// metre or so; how far down it each point is, m; and the level its bed is
  /// laid at down its middle there.
  late final List<Vector2> _line;
  late final List<double> _down, _level;

  /// The pieces of [_line] the river falls over a step in: the bed is laid
  /// at the level of the point above to halfway along, and of the point
  /// below from there.
  final Set<int> _steps = <int>{};

  /// How far round the course the water's ground is shaped, and past that
  /// left as the ground is drawn.
  late final ({double x0, double z0, double x1, double z1}) _reach;

  /// The stones in the river: where, how far down it, how big, and the
  /// level of the bed they stand on; and what draws them.
  late final List<_Stone> _boulders;
  final List<MeshNode> _boulderNodes = <MeshNode>[];

  /// Where down [_line] the ways between the halls ford it, m.
  final List<double> _fords = <double>[];

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

  /// The water's grid: half a metre a cell, from the spring's valley to
  /// past the pond's east shore.
  ///
  /// **Half a metre, not a metre.** The water is drawn one vertex a cell,
  /// and where it ends is found between a wet vertex and a dry one, so a
  /// shore is as fine as the grid: at a metre a cell a river five metres
  /// wide had an edge in steps as long as a fifth of its width, and from
  /// above it was a thing of squares.
  static const double _x0 = 48.0, _z0 = 44.0, _cell = 0.5;
  static const int _nx = 176, _nz = 72;

  /// Where the river rises, and how much, m³/s: a small river's, as much as
  /// the pond lets drain away once it runs in.
  ///
  /// **Enough to run a foot deep.** How deep water runs down
  /// a slope is set by how much of it there is, for the width it has and
  /// the bed it runs on, and the colour of water a few centimetres deep
  /// over grass is mostly the grass's: four hundred litres a second over a
  /// bed two metres wide ran ten centimetres deep, and read from above as
  /// a pale wet strip. Two and a half cubic metres a second on a bouldery
  /// bed four metres wide runs a little over thirty, deep enough to be as
  /// dark as the pond.
  static const double _springX = 52.0, _springZ = 62.0, _flow = 2.5;

  /// The river's course, read off the map's ground: down the valley's low
  /// line from the spring, swinging a stride or two either side of it, and
  /// where the valley tips into the pond's hollow straight down its bank
  /// along the grid, east, into the pond. A course running along the grid
  /// can fall more steeply before the view takes its water for a falls;
  /// see [_steepest].
  static final List<Vector2> _course = <Vector2>[
    Vector2(_springX, _springZ),
    Vector2(56.5, 61.0),
    Vector2(61.0, 59.2),
    Vector2(66.0, 58.6),
    Vector2(71.0, 57.2),
    Vector2(76.0, 57.6),
    Vector2(81.0, 59.0),
    Vector2(86.0, 60.2),
    Vector2(92.0, 60.6),
    Vector2(98.0, 61.0),
    Vector2(104.0, 61.5),
    Vector2(110.0, 62.0),
  ];

  /// Half the width of the river's bed, and of a ford's, m: where the bed
  /// has risen [_shoulder] over its middle. The water runs a little wider,
  /// as far as it is deep over the middle.
  static const double _halfWide = 1.7, _fordHalfWide = 3.0;

  /// How far over its middle the bed has risen at [_halfWide], m. It rises
  /// as the square of the way out from the middle, a bed worn round, so the
  /// water thins to nothing toward its edges and the edge is wherever the
  /// bed comes up through it, not where a cell stops.
  static const double _shoulder = 0.3;

  /// The banks the bed rises to, how far over its middle, and how far they
  /// run on flat past where it reaches them, m.
  ///
  /// **Higher than a step and the water over it.** Beside a step the water
  /// above it stands over the banks of the run below by as much as the step
  /// drops; banks a metre high let it out sideways there, off their outer
  /// edge onto the grass, and the core threw it down as rows of drops in a
  /// line beside the river like a fence.
  static const double _bankHigh = 1.6, _bankWide = 1.0;

  /// How far under the ground the middle of the bed is laid, m, so the
  /// water down it stands only a hand over the grass round it.
  static const double _sunk = 0.15;

  /// The most the bed falls a metre down the course, taken along the grid,
  /// m: the fall from one cell to the next, over the cell, may be no more
  /// than this. The view draws two neighbouring cells as one surface when
  /// they are less than four tenths of a cell apart, and as water falling
  /// from one to the other past that, so a bed falling more steeply runs
  /// water drawn as nothing at all. A quarter leaves room for the water's
  /// own waves: at three tenths the runs between the falls were drawn torn,
  /// cell by cell, wherever a wave stood up.
  static const double _steepest = 0.25;

  /// How far over the ground the bed is let stand before it falls back down
  /// to it over a step, m. Where the ground falls more steeply than
  /// [_steepest] the bed falls as steeply as it may and comes away from the
  /// ground; at this much it drops in one step, and the core throws the
  /// water off it as a sheet that churns the run below it white.
  static const double _mostOver = 0.75;

  /// The pool a fall digs at its foot: how much deeper than the run, m, and
  /// how far down the course it shallows back to it. Landing on a run a
  /// foot deep the water raced on thin and fast and stood up in a jump a
  /// stride below, which the view cuts as a fall; in a pool it lands deep
  /// and goes on slow.
  static const double _plunge = 0.25, _plungeLong = 1.5;

  /// How far a ford runs along the river either side of where the way
  /// crosses it, at its full width, and how far past that it narrows back
  /// to the river's, m; and how far its bar of gravel stands over the bed.
  static const double _fordLong = 2.0, _fordTaper = 3.0, _fordBar = 0.15;

  /// How far apart the stones in the river lie, m, and how far into it the
  /// first one is.
  static const double _stoneEvery = 4.5, _firstStone = 3.0;

  /// Where the pond lets the water the river brings drain away: its middle.
  static const double _drainX = 120.0, _drainZ = 64.0;

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

  /// The river's course laid over [field], its bed graded down it and its
  /// stones placed, and the water's ground shaped round it: what [_pour]
  /// fills and the view draws over.
  ///
  /// **The river runs in a bed nobody sees.** Left to the hillside as it
  /// is, the water from the spring spread into a film a few millimetres
  /// deep and ten metres wide, which from where the camera hangs is no water
  /// at all. A river has worn itself a bed; this ground has not, and carving
  /// one would put the water under the grass that is drawn over it. So the
  /// water's own ground is shaped instead: a bed laid a hand under the grass
  /// down the middle of the course, rising round on either side to banks
  /// over it, which the water stands in four metres wide and a foot deep.
  ///
  /// **The view is given that bed, not the ground as it is drawn.** It ends
  /// the water between a wet vertex and a dry one, as far across as the
  /// depth passes nought, and over the bed the depth falls smoothly to
  /// nought where the bed rises through the water: a shore as smooth as the
  /// bed. Told the drawn ground instead, every dry vertex beside the water
  /// stood under its surface, over a bank only the core knew of, and the
  /// water stopped at the cells round it: banks in steps, cell by cell, and
  /// wherever the bed was wider than its banks let water out a lake with
  /// square edges.
  List<double> _survey(Heightfield field) {
    _terrain = <double>[
      for (var j = 0; j < _nz; j++)
        for (var i = 0; i < _nx; i++)
          field.heightAt(_x0 + (i + 0.5) * _cell, _z0 + (j + 0.5) * _cell),
    ];
    _line = _trace();
    _down = <double>[0.0];
    for (var k = 1; k < _line.length; k++) {
      _down.add(_down.last + (_line[k] - _line[k - 1]).length);
    }
    _level = _grade();
    final double out =
        _fordHalfWide * math.sqrt(_bankHigh / _shoulder) + _bankWide;
    _reach = (
      x0: _line.map((Vector2 p) => p.x).reduce(math.min) - out,
      z0: _line.map((Vector2 p) => p.y).reduce(math.min) - out,
      x1: _line.map((Vector2 p) => p.x).reduce(math.max) + out,
      z1: _line.map((Vector2 p) => p.y).reduce(math.max) + out,
    );
    _boulders = _lay();
    return _bed();
  }

  /// The pond filled to its painted level over [bed], and the spring set
  /// running at the head of the river.
  NativeShallowLiquid _pour(List<double> bed) {
    final river = world.createShallowLiquid(
      nx: _nx,
      nz: _nz,
      cell: _cell,
      origin: Vector3(_x0, 0.0, _z0),
      ground: bed,
    );
    world
      // A bed of cobbles and boulders: rough enough to hold the river back
      // to a deep run, not a sheet racing down the valley a few centimetres
      // thick.
      ..setShallowBed(river, roughness: 0.07)
      ..fillShallowLiquid(
        river,
        x0: 96.0,
        z0: _z0,
        x1: _x0 + _nx * _cell,
        z1: _z0 + _nz * _cell,
        level: _pondLevel,
      )
      ..setShallowSource(
        river,
        0,
        x: _springX,
        z: _springZ,
        radius: 1.5,
        rate: _flow,
      );
    return river;
  }

  /// [_course] drawn through smoothly, a point every half metre or so.
  static List<Vector2> _trace() {
    final List<Vector2> p = <Vector2>[_course.first, ..._course, _course.last];
    const int pieces = 20;
    final dense = <Vector2>[
      for (var i = 1; i + 2 < p.length; i++)
        for (var k = 0; k < pieces; k++)
          _catmull(p[i - 1], p[i], p[i + 1], p[i + 2], k / pieces),
      _course.last,
    ];
    return dense.fold(<Vector2>[], (List<Vector2> kept, Vector2 q) {
      if (kept.isEmpty || (q - kept.last).length >= _cell) kept.add(q);
      return kept;
    });
  }

  /// The point [t] of the way from [b] to [c] on a curve through [a], [b],
  /// [c] and [d].
  static Vector2 _catmull(
    Vector2 a,
    Vector2 b,
    Vector2 c,
    Vector2 d,
    double t,
  ) =>
      (b * 2.0 +
          (c - a) * t +
          (a * 2.0 - b * 5.0 + c * 4.0 - d) * (t * t) +
          (b * 3.0 - a - c * 3.0 + d) * (t * t * t)) *
      0.5;

  /// The level of the bed down the middle of the course, point by point: a
  /// hand under the ground, falling with it as long as it falls no more
  /// steeply than [_steepest] lets the view draw, and where the ground
  /// falls faster, falling that steeply until it stands [_mostOver] over the
  /// ground and then dropping back to it in one step. Down the valley that
  /// is the ground's own fall; down the bank into the pond it is a run of
  /// short steep runs and small falls, as a stream comes down a hillside,
  /// each fall with a pool dug at its foot.
  List<double> _grade() {
    final level = <double>[
      _field.heightAt(_line.first.x, _line.first.y) - _sunk,
    ];
    for (var k = 1; k < _line.length; k++) {
      final Vector2 step = _line[k] - _line[k - 1];
      final double ground = _field.heightAt(_line[k].x, _line[k].y) - _sunk;
      final double laid = math.min(
        level.last,
        math.max(
          ground,
          level.last - _steepest * step.length2 / (step.x.abs() + step.y.abs()),
        ),
      );
      if (laid - ground > _mostOver) _steps.add(k);
      level.add(laid - ground > _mostOver ? ground : laid);
    }
    return <double>[
      for (var k = 0; k < level.length; k++)
        level[k] -
            _steps.fold<double>(0.0, (double most, int step) {
              final double past = (_down[k] - _down[step]) / _plungeLong;
              return past < 0.0 || past >= 1.0
                  ? most
                  : math.max(most, _plunge * (1.0 - past));
            }),
    ];
  }

  /// Where on the line, [down] metres from the spring.
  Vector2 _pointAt(double down) {
    final int k = _segmentAt(down);
    final double t = (down - _down[k]) / (_down[k + 1] - _down[k]);
    return _line[k] + (_line[k + 1] - _line[k]) * t.clamp(0.0, 1.0);
  }

  int _segmentAt(double down) {
    var k = 0;
    while (k + 2 < _line.length && _down[k + 1] < down) {
      k++;
    }
    return k;
  }

  /// How much of a ford there is [down] metres down the line, nought to
  /// one: all of it within [_fordLong] of where a way crosses, and less
  /// and less over [_fordTaper] past that, along a half wave so the bar
  /// rises out of the bed and the banks open out with no corner in either.
  double _fordAt(double down) => _fords.fold(0.0, (double most, double at) {
    final double past = ((down - at).abs() - _fordLong) / _fordTaper;
    return math.max(
      most,
      past <= 0.0
          ? 1.0
          : past >= 1.0
          ? 0.0
          : 0.5 + 0.5 * math.cos(math.pi * past),
    );
  });

  /// The stones in the river: one every [_stoneEvery] metres, a little to
  /// one side of the middle and then the other, each a little bigger or
  /// smaller than the last: the water parts round them, and where it is
  /// slow they are what shows it moving. None on a step, where they would
  /// stand in the falling sheet, and none in the pond.
  List<_Stone> _lay() => <_Stone>[
    for (var n = 0; _firstStone + n * _stoneEvery < _down.last - 2.0; n++)
      ?_stoneAt(n),
  ];

  /// The [n]th stone down the river, if it has a place.
  _Stone? _stoneAt(int n) {
    final double down = _firstStone + n * _stoneEvery;
    final Vector2 middle = _pointAt(down);
    final double level = _nearest(middle.x, middle.y).level;
    final bool clear =
        level > _pondLevel &&
        _steps.every((int k) => (_down[k] - down).abs() > 1.2);
    return clear
        ? (
            at: middle + _across(down) * (n.isEven ? 0.9 : -0.8),
            down: down,
            size: 0.5 + 0.12 * math.sin(n * 2.3),
            level: level,
          )
        : null;
  }

  /// Square to the line at [down], to its left.
  Vector2 _across(double down) {
    final int k = _segmentAt(down);
    final Vector2 along = (_line[k + 1] - _line[k])..normalize();
    return Vector2(along.y, -along.x);
  }

  /// How far `(x, z)` is from the line, how far down the line the nearest
  /// point of it is, m, and the level of the bed's middle there: a step's
  /// level above it to halfway along the step's piece, and below it past
  /// that, so the step is a sharp edge square across the river.
  ({double away, double down, double level}) _nearest(double x, double z) {
    var nearest = double.infinity;
    var down = 0.0, level = 0.0;
    for (var k = 0; k + 1 < _line.length; k++) {
      final double ax = _line[k].x, az = _line[k].y;
      final double bx = _line[k + 1].x - ax, bz = _line[k + 1].y - az;
      final double t = (((x - ax) * bx + (z - az) * bz) / (bx * bx + bz * bz))
          .clamp(0.0, 1.0);
      final double dx = x - ax - bx * t, dz = z - az - bz * t;
      final double d2 = dx * dx + dz * dz;
      if (d2 < nearest) {
        nearest = d2;
        down = _down[k] + t * (_down[k + 1] - _down[k]);
        level = _steps.contains(k + 1)
            ? (t < 0.5 ? _level[k] : _level[k + 1])
            : _level[k] + t * (_level[k + 1] - _level[k]);
      }
    }
    return (away: math.sqrt(nearest), down: down, level: level);
  }

  /// The water's ground, cell by cell: the river's bed worn round down the
  /// course and closed round at the spring, rising to banks either side,
  /// widening and lifted to a bar where a way fords it, a stone standing in
  /// it here and there, and the ground as it is drawn everywhere else.
  List<double> _bed() => <double>[
    for (var j = 0; j < _nz; j++)
      for (var i = 0; i < _nx; i++)
        _bedAt(
          _x0 + (i + 0.5) * _cell,
          _z0 + (j + 0.5) * _cell,
          _terrain[i + j * _nx],
        ),
  ];

  double _bedAt(double x, double z, double ground) {
    if (x < _reach.x0 || x > _reach.x1 || z < _reach.z0 || z > _reach.z1) {
      return ground;
    }
    final (:away, :down, :level) = _nearest(x, z);
    // A ford: the bed lifted a hand and worn wider and flatter, so the
    // river spreads over it shallow and quick instead of keeping to its
    // middle a foot deep.
    final double ford = _fordAt(down);
    final double half = _halfWide + (_fordHalfWide - _halfWide) * ford;
    final double middle = level + _fordBar * ford;
    final double across = away / half;
    final double rise = _shoulder * across * across;
    final double trough =
        away < half * math.sqrt(_bankHigh / _shoulder) + _bankWide
        ? middle + math.min(rise, _bankHigh)
        : double.negativeInfinity;
    // A stone: a round hump in the bed under the one drawn, a little lower
    // than it, that the water runs round. None for a stone taken out of a
    // ford, all of its hump at once: kept where the ford had not reached,
    // the edge of one stood out of the water as a little green island.
    final double stone = _boulders.fold(double.negativeInfinity, (
      double most,
      _Stone b,
    ) {
      final double r = 0.8 * b.size;
      final double dx = x - b.at.x, dz = z - b.at.y;
      final double d2 = (dx * dx + dz * dz) / (r * r);
      return d2 < 1.0 && _fordAt(b.down) == 0.0
          ? math.max(most, b.level + (0.1 + 0.6 * b.size) * (1.0 - d2))
          : most;
    });
    final double bed = math.max(ground, math.max(trough, stone));
    // Where the course runs out into the pond it is the pond's floor: banks
    // standing out of it would be a pier, and held just under its surface
    // they were a pale shelf, square at its corners.
    return ground < _pondLevel ? ground : bed;
  }

  /// The stones laid in the river drawn: rounded boulders, a little sunk
  /// into the bed, standing out of the water.
  void _drawBoulders() {
    for (final (n, (:at, down: _, :size, :level)) in _boulders.indexed) {
      final node =
          MeshNode(
              _stoneMesh,
              Material(
                name: 'boulder',
                baseColor: Vector4(0.42, 0.40, 0.37, 1.0),
                roughness: 0.9,
              ),
              name: 'boulder',
            )
            ..setPosition(at.x, level + 0.25, at.y)
            ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), n * 1.7))
            ..setScale(size, 0.6 * size, 0.8 * size);
      _scene.add(node);
      _boulderNodes.add(node);
    }
  }

  /// Where the ways between the halls cross the river, m down it: the way
  /// an army takes from each hall to each hall of another side, and the
  /// path each hall's crowd wears to its seam.
  List<double> _crossings(StrategySimulation simulation) {
    final List<Building> halls = simulation.buildings;
    Vector2 flat(Vector3 at) => Vector2(at.x, at.z);
    final ways = <(Vector2, Vector2)>[
      for (final Building a in halls)
        for (final Building b in halls)
          if (a.side < b.side) (flat(a.centre), flat(b.centre)),
      for (final Building a in halls)
        if (nearestSeam(a, simulation.resources) case final ResourceNode seam)
          (flat(a.centre), flat(seam.at)),
    ];
    double cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;
    final crossings = <double>[
      for (final (Vector2 p, Vector2 q) in ways)
        for (var k = 0; k + 1 < _line.length; k++)
          if (_crossing(p, q - p, _line[k], _line[k + 1] - _line[k], cross)
              case final double t)
            _down[k] + t * (_down[k + 1] - _down[k]),
    ]..sort();
    // Not at the spring or the mouth, not on the falls, and one ford for
    // ways that cross close together.
    return <double>[
      for (var i = 0; i < crossings.length; i++)
        if (crossings[i] > _fordLong + 2.0 &&
            crossings[i] < _down.last - _fordLong - 2.0 &&
            _steps.every(
              (int k) => (_down[k] - crossings[i]).abs() > _fordLong + 2.0,
            ) &&
            (i == 0 || crossings[i] - crossings[i - 1] > 3.0 * _fordLong))
          crossings[i],
    ];
  }

  /// How far along the line's piece from [a] by [ab] the way from [p] by
  /// [pq] crosses it, nought to one, or null if it does not.
  static double? _crossing(
    Vector2 p,
    Vector2 pq,
    Vector2 a,
    Vector2 ab,
    double Function(Vector2, Vector2) cross,
  ) {
    final double turn = cross(pq, ab);
    if (turn.abs() < 1e-9) return null;
    final double u = cross(a - p, ab) / turn;
    final double t = cross(a - p, pq) / turn;
    return u >= 0.0 && u <= 1.0 && t >= 0.0 && t <= 1.0 ? t : null;
  }

  /// A minute of the river run before the first frame, so the map opens
  /// with water already down its bed and into the pond rather than a
  /// spring just starting; or [seconds] of it, for a bed reshaped. Then the
  /// pond lets drain what the river brings: from the start, it drained the
  /// pond for the minute the river took to fill its bed and reach it, and
  /// left its shore a hand lower than the painted one.
  void _settle([double seconds = 60.0]) {
    for (var i = 0; i < seconds * 10.0; i++) {
      world.step(0.1);
    }
    world.setShallowSource(
      _river,
      1,
      x: _drainX,
      z: _drainZ,
      radius: 2.0,
      rate: -_flow,
    );
    _riverView.update();
  }

  /// The fords laid where the ways of [simulation]'s halls cross the river,
  /// and the water given a while to spread over them, unless they are
  /// already there.
  void _ford(StrategySimulation simulation) {
    final List<double> fords = _crossings(simulation);
    if (listEquals(fords, _fords)) return;
    _fords
      ..clear()
      ..addAll(fords);
    for (final (n, _Stone stone) in _boulders.indexed) {
      _boulderNodes[n].visible = _fordAt(stone.down) == 0.0;
    }
    final List<double> bed = _bed();
    world.setShallowGround(_river, bed);
    _riverView.ground = bed;
    _settle(15.0);
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
    _ford(staged.simulation);

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
