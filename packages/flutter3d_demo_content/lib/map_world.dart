/// What a map does besides the crowd: a pond and the river that runs down
/// into it, fires in the halls and the woods, and the stones a siege throws —
/// all of it the physics core's, in a world of its own that is part of the
/// match.
///
/// **Stepped in the simulation's own step, and saved in its own save.** A
/// [MapWorld] hangs itself on `StrategySimulation.afterStep` and on its entity
/// world, so whatever steps a match — the screen, a replay of a tape, a
/// playthrough with nobody watching — steps the water and the fires with it,
/// and whatever saves one — a save on disk, a demo's start, a checkpoint's
/// digest — carries the core's own snapshot. It was the strategy game's, and
/// stepped round the match by a loop of the application's: a resumed match
/// came back to a fresh river and no fires, and a demo's checkpoints said
/// nothing of either.
///
/// **And the match feels it**, through two doors the simulation has:
///
/// * **Water slows a unit wading it**, through `StrategySimulation.pace`:
///   where a unit stands in the river, a ford or the pond, the water as deep
///   as it stands over the ground pushes back on its legs, and the unit goes
///   as fast as the work it puts into walking lets it go against that push.
///   See [wadingPace].
/// * **Fire hurts a unit near it**, by the heat its flames radiate onto it,
///   taken off its health at the rate that heat brings a person to harm: see
///   [radiantFlux] and [harmRate].
///
/// What starts a fire and throws a stone is read off the step's own
/// `StrategySimulation.shots`:
///
/// * **A hall catches fire when it is shot at**: each shot an armed unit of
///   the other side fires from within its range of the hall looses a fire
///   arrow at the timber nearest it, and where the arrow strikes timber —
///   the core's contact, not a distance — its flame is held, until it has
///   brought that surface to the point it ignites at. Buildings have no
///   health in the match, and nobody stands inside one, so what burns is
///   the hall as drawn — the timber under the roofs of its keep and its
///   towers — and what it hurts is whoever stands near it while it burns.
/// * **The woods burn** from what falls into them: brands a fire lofts by the
///   fuel it burns ([Firebrands]), as hot as its flame, which light a crown
///   they come down in; and then tree to tree by the heat of their own
///   flames, leaning with the wind and so running downwind.
/// * **A ram's strike throws stones** — at the wall it is working at, where
///   pieces of the wall break off and tumble where a stone strikes its
///   stone, or at the unit it hits. Stones and arrows are thrown by the
///   core's own flight of them ([Ballistics]), so they come down where they
///   were aimed.
///
/// What the viewing side cannot see starts nothing: a fight under its fog
/// throws no stones and lights no hall, so the fires never tell the player
/// about a battle the map is careful not to show. The fog is the
/// simulation's, so this rule replays as everything else does.
///
/// **The same map gives the same world, to the bit.** It is built from the
/// map alone and draws its dice from a seed of its own; the core is single
/// precision and deterministic on every platform, and the sines and powers
/// worked out here are [Portable]'s, not each platform's own.
///
/// Nothing here draws: what draws the world adopts it and reads it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_elements/flutter3d_elements.dart'
    show Ballistics, Firebrands, Solid;
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show referenceBodyMass;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart'
    as sim
    show GameRandom, Heightfield;
import 'package:vector_math/vector_math.dart';

import 'src/map_channel.dart';

/// A stone in the river: where, how far down it, m, how big, and the level
/// of the bed it stands on.
typedef RiverStone = ({Vector3 at, double down, double size, double level});

/// What a thrown or loosened body is, for drawing it.
///
/// **Not an enum**, because this package is published and a closed list is a
/// promise somebody else's `switch` is written against: what draws the
/// pieces asks which of these each is and keeps a look for anything else.
final class PieceKind {
  const PieceKind._(this.index, this.name);

  /// Where it is in [values]: what a save writes for it.
  final int index;

  /// What it is called in a sentence.
  final String name;

  /// A stone a ram lobbed: a ball of [MapPiece.size]'s x.
  static const PieceKind stone = PieceKind._(0, 'stone');

  /// A piece knocked off a wall: a block [MapPiece.size] each way from its
  /// middle.
  static const PieceKind rubble = PieceKind._(1, 'rubble');

  /// A burning brand a fire lofted: a ball of [MapPiece.size]'s x.
  static const PieceKind brand = PieceKind._(2, 'brand');

  /// Every kind, in the order a save numbers them.
  static const List<PieceKind> values = <PieceKind>[stone, rubble, brand];

  @override
  String toString() => name;
}

/// A thing thrown or knocked loose.
final class MapPiece {
  MapPiece._(this.body, this.kind, this.size);

  final NativeBody body;
  final PieceKind kind;

  /// Its half-extents, or its radius in x for a ball.
  final Vector3 size;

  /// The hall a stone was thrown at, until it strikes something.
  MapHall? _aim;

  /// Seconds since it was made.
  double _age = 0.0;
}

/// A hall as the fires see it: the timber of its roofs, and the stone a
/// stone thrown at it strikes.
final class MapHall {
  MapHall._(this.index, this.building);

  /// Where it is in `simulation.buildings`.
  final int index;
  final Building building;

  /// What burns: the keep's roof first, then the towers'.
  final List<NativeBody> timbers = <NativeBody>[];

  /// Its stone: the curtain wall and the keep.
  final List<NativeBody> _stones = <NativeBody>[];
}

/// A fire arrow in flight: its body, the hall it was loosed at, and the
/// seconds since.
typedef _Arrow = ({NativeBody body, MapHall hall, double age});

/// A tree of the map's woods, and the body it burns as once it is near a
/// fire.
final class MapTree {
  /// A tree standing at ([x], [z]) on ground at [base], its model drawn
  /// [size] times over — about its height, in metres, over one and a half.
  /// [batch] and [placement] say where the game draws it, for the look that
  /// chars it; the world only keeps them.
  MapTree({
    required this.batch,
    required this.placement,
    required this.x,
    required this.z,
    required this.base,
    required this.size,
  });

  /// Which of the game's batches of trees it is drawn in, and where in it.
  final int batch, placement;

  final double x, z, base;

  /// How much its model is scaled: about its height, in metres, over one
  /// and a half.
  final double size;

  /// Its crown in the world, once it has one.
  NativeBody? get body => _body;
  NativeBody? _body;

  /// Whether it has burnt out.
  bool get dead => _dead;
  bool _dead = false;

  /// The crown, where the body is: as wide as about a third of the scale,
  /// from a quarter of the way up to the top.
  double get radius => 0.28 * size;
  double get middle => base + 0.85 * size;
  double get halfHeight => 0.45 * size;
}

/// Where a map's water is and how it runs: the content a [MapWorld] is
/// built from, beside the ground and the halls the simulation already has.
final class MapWater {
  /// A river from [course]'s first point down through the rest of it into a
  /// pond filled to [pondLevel]; [flow] m³/s rising at the spring, the pond
  /// let out over a sill [sill] wide at ([drainX], [drainZ]). The water's
  /// grid is [nx] × [nz] cells of [cell] m from ([x0], [z0]).
  MapWater({
    required this.x0,
    required this.z0,
    required this.cell,
    required this.nx,
    required this.nz,
    required List<Vector2> course,
    required this.flow,
    required this.drainX,
    required this.drainZ,
    required this.sill,
    required this.pondLevel,
  }) : course = List<Vector2>.unmodifiable(<Vector2>[
         for (final Vector2 p in course) p.clone(),
       ]);

  final double x0, z0, cell;
  final int nx, nz;

  /// The river's course, from the spring to where it runs into the pond: a
  /// few points it is drawn smoothly through.
  final List<Vector2> course;

  /// What rises at the spring, m³/s.
  final double flow;

  /// Where the pond lets out, and how wide its sill is, m.
  final double drainX, drainZ, sill;

  /// The level the pond is filled to, m: its painted shore.
  final double pondLevel;

  /// [ground] with this river carved into it: its bed laid down the
  /// course, rising to its banks, falling at its steps into the pools they
  /// dig, lifted at its fords and humped over its stones — the bed the
  /// water stands in ([MapWorld.bed]) — on a grid [cell] metres a side
  /// over [ground]'s extent, [ground] as it was everywhere the river does
  /// not reach.
  ///
  /// **The ground the map is drawn and walked on**, so the water runs in a
  /// channel the ground has rather than in a bed of its own under the
  /// grass. [cell] is the water's own unless given: the map's two-metre
  /// grid cannot hold a bed three and a half metres wide. [halls] and
  /// [seams] are the map's, as the match stands them: the ways between them
  /// are where the river is forded. A [MapWorld] over a match standing on
  /// this ground is given [ground] as its `uncarved`, so it lays the same
  /// bed rather than one carved into the carving.
  sim.Heightfield carve(
    sim.Heightfield ground, {
    required List<Building> halls,
    required List<ResourceNode> seams,
    double? cell,
  }) {
    final double step = cell ?? this.cell;
    final channel = MapChannel(this, ground, halls, seams);
    final int columns = (ground.width / step).round() + 1;
    final int rows = (ground.depth / step).round() + 1;
    final heights = Float32List(columns * rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        final double x = ground.origin.x + c * step;
        final double z = ground.origin.z + r * step;
        heights[r * columns + c] = channel.bedAt(x, z, ground.heightAt(x, z));
      }
    }
    return sim.Heightfield(
      columns: columns,
      rows: rows,
      cellSize: step,
      heights: heights,
      origin: ground.origin.clone(),
    );
  }
}

/// The seam nearest [hall], on the ground plane: the one its crowd wears a
/// path to — where a river is forded, and where the game keeps its woods
/// off.
ResourceNode? nearestSeam(Building hall, List<ResourceNode> seams) {
  ResourceNode? best;
  var bestDistance = double.infinity;
  for (final ResourceNode seam in seams) {
    final double dx = seam.at.x - hall.center.x;
    final double dz = seam.at.z - hall.center.z;
    final double d = math.sqrt(dx * dx + dz * dz);
    if (d < bestDistance) {
      bestDistance = d;
      best = seam;
    }
  }
  return best;
}

/// How fast a person walks wading water [depth] metres deep over the
/// ground, m/s, who walks [dry] m/s on dry ground, with the water running
/// [current] m/s along the way they walk.
///
/// **A power balance, the walker's against the water's.** On dry ground a
/// walker pays [costOfTransport] joules per kilogram per metre, so at [dry]
/// m/s spends c·m·v₀ watts. In water each leg is pushed back by drag,
/// F = ½ρ·C_d·A·|v − u|·(v − u) over the frontal area A wetted (Hoerner,
/// *Fluid-Dynamic Drag*, 1965: a cylinder across the flow below the drag
/// crisis, C_d ≈ 1.2), and working against it at v costs F·v over the
/// muscles' efficiency in positive work, η ≈ 0.25 (Margaria, *Int. Z.
/// angew. Physiol.* 25, 1968). The walker keeps spending what it spent dry
/// and goes as fast as that buys:
///
///     c·m·(v₀ − v) = F(v)·v / η
///
/// The area is two legs below the crotch and the hips above it — a fiftieth
/// percentile man's knee breadth and hip breadth, and his crotch height
/// (NASA-STD-3000, vol. I, §3 anthropometry). Water running the way the
/// walker goes pushes it on, but no faster than it walks dry.
double wadingPace({
  required double depth,
  required double dry,
  double current = 0.0,
}) {
  if (depth <= 0.0 || dry <= 0.0) return dry;
  final double area =
      2.0 * _legBreadth * math.min(depth, _crotch) +
      _hipBreadth * math.max(0.0, depth - _crotch);
  final double k = 0.5 * NativeLiquidProperties.water.density * _legDrag * area;
  // The reference man's mass, the one every body in the engine weighs.
  const double budget = costOfTransport * referenceBodyMass;
  double surplus(double v) {
    final double relative = v - current;
    return budget * (dry - v) - k * relative.abs() * relative * v / _muscle;
  }

  if (surplus(dry) >= 0.0) return dry;
  // Bisection: what is left over falls from c·m·v₀ at a standstill to below
  // nought at the dry pace, and the pace is where it crosses.
  var lo = 0.0, hi = dry;
  for (var i = 0; i < 40; i++) {
    final double mid = 0.5 * (lo + hi);
    if (surplus(mid) > 0.0) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return 0.5 * (lo + hi);
}

/// How far over a sharp-crested weir's crest water stands to pass [flow]
/// m³/s over [width] metres of it under a gravity of [g] m/s² — the
/// world's: H = (Q / (⅔·C_d·√(2g)·b))^(2/3) (Poleni, C_d 0.611).
///
/// What the pond's sill is set by, so a map's pond stands at its painted
/// shore once the river runs in, on whatever world it is: water pours
/// slower on the Moon, and the same river backs up a higher head.
double weirHead({
  required double flow,
  required double width,
  required double g,
  double coefficient = 0.611,
}) => Portable.pow(
  flow / (2.0 / 3.0 * coefficient * math.sqrt(2.0 * g) * width),
  2.0 / 3.0,
);

/// The velocity that carries a body thrown from [from] onto [to] in
/// [flight] seconds under a gravity of [g] m/s² — the world's — pulling
/// down y: the straight line's pace, and as much up as the fall takes back.
Vector3 lobVelocity(
  Vector3 from,
  Vector3 to, {
  required double flight,
  required double g,
}) => (to - from)
  ..scale(1.0 / flight)
  ..y += 0.5 * g * flight;

/// The net metabolic cost of running, J/(kg·m): about a kilocalorie a
/// kilogram a kilometre, whatever the speed (Margaria, Cerretelli, Aghemo
/// and Sassi, *J. Appl. Physiol.* 18, 1963). Running and not walking,
/// because the crowd moves at two to three and a half metres a second,
/// past the walk-to-run transition at about two.
const double costOfTransport = 4.18;

/// A leg's breadth across the flow, the hips' breadth, and the crotch's
/// height, m: NASA-STD-3000's fiftieth-percentile man.
const double _legBreadth = 0.12, _hipBreadth = 0.36, _crotch = 0.8;

/// A leg's drag coefficient, a cylinder's (Hoerner 1965), and the muscles'
/// efficiency in positive work (Margaria 1968).
const double _legDrag = 1.2, _muscle = 0.25;

/// The heat flux a flame radiating [radiated] watts, its soot glowing at
/// [soot] kelvin, throws onto a point [distance] metres from its middle,
/// W/m².
///
/// **Modak's point source** (*Fire Safety J.* 1, 1977; Beyler, SFPE
/// Handbook, "Fire hazard calculations for large, open hydrocarbon fires"):
/// the flame's radiant share of its power, χ·Q, given off evenly in every
/// direction from the middle of the flame, q″ = χ·Q / (4π·R²). Close in,
/// where that runs to infinity, a point in the flame sees no more than the
/// flame gives off itself: its soot glowing as a black body, σ·T⁴.
/// [FireExposure.flux].
double radiantFlux({
  required double radiated,
  required double soot,
  required double distance,
}) => FireExposure.flux(
  radiant: radiated,
  sootTemperature: soot,
  distanceSquared: distance <= 0.0 ? 0.0 : distance * distance,
);

/// The share of a person's tolerance a heat flux of [flux] W/m² uses up a
/// second.
///
/// **ISO 13571:2012's tolerance to radiant heat**, the law every game here
/// hurts by: at or below 2.5 kW/m² (§8.4) a person bears the heat, and
/// above it is burnt to the second degree in t = 6.9·q^−1.56 minutes, q in
/// kW/m² (Eq. 7, after Wieczorek and Dembsey, 2001). The dose a second is
/// 1/t, and a unit's whole health is the whole dose.
/// [FireExposure.burnDoseRate].
double harmRate(double flux) => FireExposure.burnDoseRate(flux);

/// The heat flux a person bears for half an hour, W/m² (ISO 13571):
/// [FireExposure.harmlessFlux].
const double tolerableFlux = FireExposure.harmlessFlux;

/// The river, the pond, the fires and the thrown stones over one map, in a
/// world of the physics core's stepped and saved with the simulation.
final class MapWorld {
  /// The world over [simulation]'s map, hung on its step and its save: the
  /// ground, the river [water] describes laid down it and run until it
  /// reaches the pond, the halls' timber, and [trees].
  ///
  /// Built from the map alone — its ground, where its halls and seams stand,
  /// what the game says of its water and its woods — so the same map gives
  /// the same world, which is what lets a replay build it again. Built after
  /// the map is staged and before anything of a save is put back into it,
  /// so a restore finds it there to fill. [viewer] is the side whose fog a
  /// fire or a stone has to be seen through to start.
  ///
  /// [uncarved] is the ground [simulation]'s was carved from, when the
  /// match stands on [MapWater.carve]'s: the river is laid over it, so the
  /// bed is the one carved and not one carved into the carving. Null for a
  /// match on a ground with no channel in it.
  MapWorld(
    StrategySimulation simulation, {
    required this.water,
    required List<MapTree> trees,
    this.viewer = 0,
    WorldProperties? properties,
    sim.Heightfield? uncarved,
  }) : _simulation = simulation,
       _field = simulation.ground,
       trees = List<MapTree>.unmodifiable(trees),
       world = NativeWorld() {
    // The valley's world, the standard one unless the game says: the
    // gravity the stones fall by, the pond's weir is set by and the river
    // runs down, and the air the fires burn in. Its wind is the map's own
    // weather, which turns with the clock, over the world's.
    world
      ..applyProperties(properties ?? WorldProperties.standard)
      ..wind = _windAt(0.0);
    _floor(_field);
    _channel = MapChannel(
      water,
      uncarved ?? _field,
      simulation.buildings,
      simulation.resources,
    );
    bed = _channel.bed();
    river = _pour();
    _settle();
    for (var i = 0; i < simulation.buildings.length; i++) {
      halls.add(_build(i, simulation.buildings[i]));
    }
    for (final MapTree tree in this.trees) {
      _bare.add(tree);
      (_byCell[_cellOf(tree.x, tree.z)] ??= <MapTree>[]).add(tree);
    }
    _hang();
  }

  final StrategySimulation _simulation;

  /// What the map's water is.
  final MapWater water;

  /// The side whose fog a fire or a stone has to be seen through to start.
  final int viewer;

  /// The core's world: everything here lives in it, and nothing of the
  /// crowd does.
  final NativeWorld world;

  final sim.Heightfield _field;

  /// The river and the pond.
  late final NativeShallowLiquid river;

  /// The river's ground, cell by cell: what the water stands on and its
  /// view draws over.
  late final List<double> bed;

  /// The halls, in the order the simulation has them.
  final List<MapHall> halls = <MapHall>[];

  /// The map's trees.
  final List<MapTree> trees;

  /// The trees that have a body, in the order they were given one.
  final List<MapTree> burnable = <MapTree>[];

  /// The stones, the pieces and the brands in the air or on the ground.
  final List<MapPiece> pieces = <MapPiece>[];

  /// The river's course, bed, fords and stones over the map.
  late final MapChannel _channel;

  /// The stones laid in the river.
  List<RiverStone> get boulders => _channel.stones;

  /// Where the ways between the halls ford the river: the middle of each
  /// ford, on the ground.
  List<Vector3> get fords => <Vector3>[
    for (final double down in _channel.fords)
      if (_channel.pointAt(down) case final Vector2 p)
        Vector3(p.x, _field.heightAt(p.x, p.y), p.y),
  ];

  /// The wind now, m/s.
  Vector3 get wind => _windAt(_clock);

  /// Seconds of match the world has been stepped through.
  double get clock => _clock;

  // ----------------------------------------------------------------- numbers

  /// What a tree's crown and a roof's timber are as fire sees them: dry
  /// leaves, twigs and thatch — a loose bed of thin stalks, which the core's
  /// thatch is (Rossa's straw: each stalk heated through, the bed taking
  /// radiant heat to a depth of 4/(βσ)), so a fire arrow held to it sets it
  /// burning where a flame on solid timber would only char it and go out.
  /// How fast it burns is the core's, from its heat balance.
  static final NativeMaterial dry = NativeMaterial.thatch();

  /// A fire arrow's flame held against timber: a rag of pitch burning, its
  /// flame on a hand's breadth of the wood. The game's arrow, not a
  /// measured one.
  static const ({double flux, double area, double temperature, double seconds})
  _fireArrow = (flux: 5e4, area: 0.01, temperature: 1100.0, seconds: 30.0);

  /// The most fires burning at once that brands are still lofted from: the
  /// core's heat from a fire to everything near it costs most of a
  /// millisecond a step for each, and this is paid in the match's step on a
  /// phone as on a desktop — one number for both, because a match must play
  /// the same on either.
  static const int _mostFires = 4;

  /// What a brand is: the burnt end of a twig of the crown, a centimetre
  /// across, as dense as the catalogue's pine. Not of the crown's thatch: a
  /// bed of stalks that small is heated through and burns its fuel in one
  /// step, before it has left the flame.
  static final Solid _brand = Solid.of(
    const NativeShape.sphere(0.01),
    Materials.pine,
  );

  /// The share of what a fire burns that its plume lofts as brands. The
  /// game's, not a measured one: as many as it threw before brands were
  /// lofted by what burns, about one every four seconds from a megawatt of
  /// thatch.
  static final double _brandShare =
      0.25 * _brand.mass * dry.heatOfCombustion / 1e6;

  /// What a fire arrow is as it flies: its head and its burning rag, a ball
  /// of pine two centimetres across.
  static final Solid _arrow = Solid.of(
    const NativeShape.sphere(0.02),
    Materials.pine,
  );

  /// The arc a stone and an arrow are thrown on: as far over the level as
  /// a lob that comes down in [_lob] seconds leaves at, the core's own
  /// flight then aimed at the mark.
  static const double _lob = 0.8;

  /// How far from a fire a tree is given a body, m: further than a crown's
  /// flame leans, and than most brands fly.
  static const double _near = 14.0;

  /// How much ground around a tree the viewing side must have found before
  /// the tree can catch, m: about as far as a crown's flame and the first of
  /// its smoke lean downwind.
  static const double _margin = 6.0;

  /// The most brands in the air, and stones and pieces on the ground.
  static const int _mostBrands = 6, _mostStones = 32;

  /// The side of a square of [_byCell], m.
  static const double _lattice = 8.0;

  /// How many steps apart the trees near a fire are looked for: half a
  /// second's.
  static const int _lookEvery = 30;

  // ------------------------------------------------------------------- state

  /// The trees by the [_lattice]-metre square they stand in, and those with
  /// no body yet.
  final Map<int, List<MapTree>> _byCell = <int, List<MapTree>>{};
  final List<MapTree> _bare = <MapTree>[];
  final Map<NativeBody, MapTree> _treeOf = <NativeBody, MapTree>{};

  /// The dice: a seed of the world's own, so it rolls the same in a replay
  /// and never moves the simulation's.
  final sim.GameRandom _random = sim.GameRandom(17);

  /// The fire arrows held to timber, and how long each is held still.
  final List<({NativeBody body, Vector3 at, double left})> _held =
      <({NativeBody body, Vector3 at, double left})>[];

  /// The fire arrows in flight.
  final List<_Arrow> _arrows = <_Arrow>[];

  /// The brands the fires loft.
  late final Firebrands _brands = Firebrands(
    world,
    brand: _brand,
    share: _brandShare,
    most: _mostBrands,
  );

  /// What the steps since the last [takeEvents] said. Not part of the match
  /// — what is heard of it — and so not saved.
  final List<NativeEvent> _events = <NativeEvent>[];

  double _clock = 0.0;
  int _ticks = 0;

  // ------------------------------------------------------------------ ground

  /// The map's ground as one fixed mesh, triangulated as it is drawn.
  void _floor(sim.Heightfield field) {
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
    final ground = world.addBody(
      position: Vector3.zero(),
      type: NativeBodyType.fixed,
    );
    world
      ..setMesh(ground, world.createMesh(points, indices))
      ..setMaterial(ground, NativeMaterial.stone());
  }

  /// The pond filled to its painted level over [bed], and the spring set
  /// running at the head of the river.
  NativeShallowLiquid _pour() {
    final MapWater w = water;
    final Vector2 spring = w.course.first;
    final liquid = world.createShallowLiquid(
      nx: w.nx,
      nz: w.nz,
      cell: w.cell,
      origin: Vector3(w.x0, 0.0, w.z0),
      ground: bed,
    );
    world
      ..setShallowProperties(liquid, NativeLiquidProperties.water)
      // As warm as the valley's air.
      ..setShallowHeat(
        liquid,
        NativeLiquidHeat.water(temperature: world.airTemperature),
      )
      // A bed of cobbles and large boulders, the roughest of Chow's
      // mountain streams: it holds the river back to a deep run, not a
      // sheet racing down the valley a few centimetres thick.
      ..setShallowBed(liquid, roughness: 0.07)
      ..fillShallowBasin(liquid, x: w.drainX, z: w.drainZ, level: w.pondLevel)
      ..setShallowSource(
        liquid,
        0,
        x: spring.x,
        z: spring.y,
        radius: 1.5,
        rate: w.flow,
      );
    return liquid;
  }

  /// A minute of the river run before the match, so it opens with water
  /// already down its bed and into the pond rather than a spring just
  /// starting. Then the pond lets drain what the river brings: from the
  /// start, it drained the pond for the minute the river took to fill its
  /// bed and reach it, and left its shore a hand lower than the painted one.
  ///
  /// The pond lets out over a sill [MapWater.sill] wide: a sharp-crested
  /// weir, whose crest stands as far under the painted shore as the head
  /// that passes the river's whole flow over it,
  /// H = (Q / (⅔·C_d·√(2g)·b))^(2/3) (Poleni, C_d 0.611), so the pond stands
  /// at its shore once the river runs in.
  void _settle() {
    for (var i = 0; i < 600; i++) {
      world.step(0.1);
    }
    const double cd = 0.611;
    final double head = weirHead(
      flow: water.flow,
      width: water.sill,
      g: world.gravityMagnitude,
      coefficient: cd,
    );
    world
      ..setShallowOutlet(
        river,
        0,
        NativeOutlet.weir(
          x: water.drainX,
          z: water.drainZ,
          crest: water.pondLevel - head,
          width: water.sill,
          coefficient: cd,
        ),
      )
      // What the settling said is the river's business before the match,
      // and nobody's to hear.
      ..readEvents();
  }

  // ------------------------------------------------------------------- halls

  /// The bodies of the castle drawn for [building]: its stone, for stones
  /// to strike, and the timber that burns — the castle's layout, towers at
  /// the corners and the keep at the back, about twice its kit's size.
  MapHall _build(int index, Building building) {
    final hall = MapHall._(index, building);
    final Vector3 c = building.center;
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
      hall._stones.add(body);
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
        ..setMaterial(body, dry);
      hall.timbers.add(body);
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

  static int _cellOf(double x, double z) =>
      (x / _lattice).floor() * 4096 + (z / _lattice).floor();

  // -------------------------------------------------------------------- step

  /// Hung on the simulation: the waders' pace asked in its walk, this world
  /// stepped after the crowd with what the step did, and saved and restored
  /// with the simulation's own entities.
  void _hang() {
    _simulation
      ..pace = _pace
      ..afterStep.add(_afterStep);
    final entities = _simulation.entities;
    entities.components.register<MapWorld>(
      InPlaceCodec<MapWorld>.of(
        id: 'map world',
        encode: (map) => map._save(),
        restore: (context) {
          final map = context.value;
          final data = context.data;
          map._restore(data);
        },
      ),
    );
    entities.set<MapWorld>(entities.spawn(), this);
  }

  /// The world one step on, after the crowd's: the trees near a fire found
  /// now and then, the step's shots answered, brands lofted and fire arrows
  /// held, then stepped; what the stones and arrows struck answered, and
  /// its fires burn whoever is near them.
  void _afterStep(double dt) {
    _clock += dt;
    _ticks++;
    world.wind = wind;
    if (_ticks % _lookEvery == 0) _find(_simulation);
    _shots(_simulation);
    _loft(dt);
    _hold(dt);
    world.step(dt);
    final List<NativeEvent> happened = world.readEvents();
    _events.addAll(happened);
    if (_events.length > _mostHeard) {
      _events.removeRange(0, _events.length - _mostHeard);
    }
    _burnt(happened);
    _struck(world.readContacts(), dt);
    _fly(dt, _simulation);
    _scorch(_simulation, dt);
  }

  /// Kept no longer than this, for a match nobody is drawing.
  static const int _mostHeard = 512;

  /// What the world's steps said since this was last asked: for what draws
  /// and hears it.
  List<NativeEvent> takeEvents() {
    final List<NativeEvent> taken = List<NativeEvent>.of(_events);
    _events.clear();
    return taken;
  }

  /// How fast [unit] goes wading where it stands, heading along ([x], [z]),
  /// as a share of its dry pace: its [wadingPace] in the water as deep as
  /// the surface stands over the ground the unit stands on — the
  /// simulation's ground, what the player sees it wade — with the current
  /// along its way. One out of the water.
  double _pace(StrategyUnit unit, double x, double z) {
    final MapWater w = water;
    final double px = unit.position.x, pz = unit.position.z;
    if (px < w.x0 ||
        pz < w.z0 ||
        px > w.x0 + w.nx * w.cell ||
        pz > w.z0 + w.nz * w.cell ||
        unit.speed <= 0.0) {
      return 1.0;
    }
    final NativeShallowSample? here = world.sampleShallow(river, px, pz);
    if (here == null || here.depth <= 0.0) return 1.0;
    final double depth = here.surface - _field.heightAt(px, pz);
    if (depth <= 0.0) return 1.0;
    final double along = here.flowX * x + here.flowZ * z;
    return wadingPace(depth: depth, dry: unit.speed, current: along) /
        unit.speed;
  }

  /// Every unit near a fire hurt by the heat its flames radiate onto it,
  /// at the [harmRate] that heat does harm, taken against its whole health.
  ///
  /// Measured at the middle of a person standing there, a metre up.
  void _scorch(StrategySimulation simulation, double dt) {
    final List<NativeFire> fires = world.fires();
    if (fires.isEmpty) return;
    final at = Vector3.zero();
    for (final StrategyUnit unit in simulation.units) {
      if (!unit.isAlive) continue;
      at.setValues(unit.position.x, unit.position.y + 1.0, unit.position.z);
      final double rate = harmRate(FireExposure.fluxAt(fires, at));
      if (rate > 0.0) unit.hurt(unit.type.health * rate * dt);
    }
  }

  /// The fire arrows held this step, and their time run down.
  void _hold(double dt) {
    for (var k = _held.length - 1; k >= 0; k--) {
      final h = _held[k];
      if (h.left <= 0.0 || !world.contains(h.body)) {
        _held.removeAt(k);
        continue;
      }
      world.holdFlame(
        h.body,
        h.at,
        flux: _fireArrow.flux,
        area: _fireArrow.area,
        temperature: _fireArrow.temperature,
      );
      _held[k] = (body: h.body, at: h.at, left: h.left - dt);
    }
  }

  /// A fresh breeze along +x and a little +z, five metres a second, its
  /// heading wandering a quarter of a right angle either way over a few
  /// minutes and its strength in gusts, at [seconds] into the match. Fresh
  /// enough to lean a burning crown's flame into the next crown downwind,
  /// and not the one upwind.
  static Vector3 _windAt(double seconds) {
    final double heading =
        0.38 +
        0.4 * Portable.sin(seconds / 53.0) +
        0.15 * Portable.sin(seconds / 7.3);
    final double speed = 5.0 + 1.2 * Portable.sin(seconds / 3.1);
    return Vector3(
      speed * Portable.cos(heading),
      0.0,
      speed * Portable.sin(heading),
    );
  }

  /// Gives a body to every tree the viewing side has found that stands
  /// within [_near] metres of a fire.
  ///
  /// **Found**, with the ground around it, because a tree under the fog is
  /// not drawn, and a fire in it would be a flame standing on nothing: see
  /// [_found]. **Near a fire**, because every body a flame could warm is one
  /// the core looks at for every fire, every step: a map's whole wood given
  /// bodies made each burning crown cost a millisecond, and a wood a fire is
  /// nowhere near has nothing to say.
  void _find(StrategySimulation simulation) {
    final List<NativeFire> fires = world.fires();
    if (fires.isEmpty) return;
    _bare.removeWhere((MapTree tree) {
      var near = false;
      for (var k = 0; k < fires.length && !near; k++) {
        final double dx = fires[k].at.x - tree.x, dz = fires[k].at.z - tree.z;
        near = dx * dx + dz * dz < _near * _near;
      }
      if (!near || !_found(tree, simulation)) return false;
      _grow(tree);
      return true;
    });
  }

  /// [tree]'s crown as a body that can burn.
  void _grow(MapTree tree) {
    final body = world.addBody(
      position: Vector3(tree.x, tree.middle, tree.z),
      type: NativeBodyType.fixed,
      // The crown's leaves and twigs: what burns of a tree in a fire that
      // runs through a wood, not its trunk.
      mass: 12.0 * tree.size,
    );
    world
      ..setShape(body, NativeShape.cylinder(tree.radius, tree.halfHeight))
      ..setMaterial(body, dry);
    tree._body = body;
    burnable.add(tree);
    _treeOf[body] = tree;
  }

  /// Every shot the step fired that the viewing side can see, and what it
  /// strikes: a hall of the other side beside the shooter, or for a ram, the
  /// unit it hit.
  void _shots(StrategySimulation simulation) {
    for (final UnitShot shot in simulation.shots) {
      final StrategyUnit unit = shot.shooter;
      final Vector3 at = unit.position;
      if (unit.side != viewer && !simulation.fog.sees(viewer, at.x, at.z)) {
        continue;
      }
      final bool ram = unit.type.name == UnitType.tank.name;
      final MapHall? hall = _hallBeside(unit);
      if (hall != null) {
        if (ram) {
          _throwAt(at, _onWall(hall.building, at), hall);
        } else {
          _shootAt(hall, at);
        }
      } else if (ram) {
        _throwAt(at, shot.mark.position + Vector3(0.0, 0.3, 0.0), null);
      }
    }
  }

  /// The hall of another side within [unit]'s range: what it looses at
  /// beside its mark. Whether that strikes is the flight's.
  MapHall? _hallBeside(StrategyUnit unit) {
    for (final MapHall hall in halls) {
      final Building b = hall.building;
      if (b.side == unit.side) continue;
      if (b.distanceTo(unit.position.x, unit.position.z) <= unit.type.range) {
        return hall;
      }
    }
    return null;
  }

  /// The throw that brings [solid] from [from] down on [to] by the core's
  /// own flight of it, on the arc of a lob that comes down in [_lob]
  /// seconds; that lob's when the air cannot carry it there on that arc.
  Vector3 _aimed(Solid solid, Vector3 from, Vector3 to) {
    final g = world.gravityMagnitude;
    final lob = lobVelocity(from, to, flight: _lob, g: g);
    final flat = math.sqrt(lob.x * lob.x + lob.z * lob.z);
    try {
      return Ballistics.aim(
        world,
        solid,
        from: from,
        to: to,
        elevation: Portable.atan2(lob.y, flat),
      );
    } on ArgumentError {
      return lob;
    } on StateError {
      return lob;
    }
  }

  /// The point on [building]'s wall nearest [from], partway up it.
  Vector3 _onWall(Building building, Vector3 from) {
    final Vector3 c = building.center;
    final double k = (building.width / 6.0 + building.depth / 5.0) / 2.0;
    return Vector3(
      from.x.clamp(c.x - building.width / 2.0, c.x + building.width / 2.0) +
          (_random.nextDouble() - 0.5),
      c.y + (0.5 + 0.5 * _random.nextDouble()) * k,
      from.z.clamp(c.z - building.depth / 2.0, c.z + building.depth / 2.0) +
          (_random.nextDouble() - 0.5),
    );
  }

  /// A stone lobbed from a ram at [from] to land on [to] in under a second.
  void _throwAt(Vector3 from, Vector3 to, MapHall? hall) {
    final start = from + Vector3(0.0, 1.5, 0.0);
    final double radius = 0.22 + 0.08 * _random.nextDouble();
    // A granite ball, as heavy as the catalogue's granite is.
    final stone = Solid.of(NativeShape.sphere(radius), Materials.granite);
    final body = world.addBody(position: start, mass: stone.mass);
    world
      ..setShape(body, stone.shape)
      ..setMaterial(body, NativeMaterial.stone())
      ..setVelocity(body, _aimed(stone, start, to));
    pieces.add(
      MapPiece._(body, PieceKind.stone, Vector3.all(radius)).._aim = hall,
    );
  }

  /// A fire arrow shot from [from] at the hall standing [index] in the
  /// match's buildings, as a shot from beside it would be: for a game that
  /// sets a hall alight itself — the strategy demo's reel opens on one.
  void shootAtHall(int index, Vector3 from) => _shootAt(halls[index], from);

  /// A fire arrow loosed from [from] at [hall]: at the face of the timber
  /// nearest the shooter that looks towards it, by the core's flight of
  /// it, and held to what it strikes there ([_struck]). None at a timber
  /// already alight or with an arrow on its way.
  void _shootAt(MapHall hall, Vector3 from) {
    NativeBody? nearest;
    var best = double.infinity;
    for (final NativeBody timber in hall.timbers) {
      final double d = (world.localPositionOf(timber) - from).length2;
      if (d < best) {
        best = d;
        nearest = timber;
      }
    }
    if (nearest == null || world.isBurning(nearest)) return;
    if (_arrows.any((_Arrow a) => identical(a.hall, hall))) return;
    final Vector3 middle = world.localPositionOf(nearest);
    final Vector3 toward = (from - middle)..normalize();
    final Vector3 start = from + Vector3(0.0, 1.5, 0.0);
    final body = world.addBody(position: start, mass: _arrow.mass);
    world
      ..setShape(body, _arrow.shape)
      ..setMaterial(body, _arrow.material)
      ..setVelocity(body, _aimed(_arrow, start, middle + toward * 0.3));
    _arrows.add((body: body, hall: hall, age: 0.0));
  }

  /// What the stones and the arrows struck in the step, by the core's
  /// [contacts]: a stone thrown at a hall breaks pieces off its wall where
  /// it strikes its stone; a fire arrow is held, burning, where it strikes
  /// its hall's timber. Either is spent on the first thing it strikes, and
  /// an arrow that strikes nothing in [_arrowFlies] seconds is let go.
  void _struck(List<NativeContact> contacts, double dt) {
    final aimed = <NativeBody, MapPiece>{
      for (final MapPiece piece in pieces)
        if (piece._aim != null) piece.body: piece,
    };
    final flying = <NativeBody, _Arrow>{
      for (final _Arrow arrow in _arrows) arrow.body: arrow,
    };
    if (aimed.isEmpty && flying.isEmpty) return;
    final breaks = <(MapHall, Vector3)>[];
    final spent = <NativeBody>{};
    for (final NativeContact c in contacts) {
      for (final (NativeBody it, NativeBody other)
          in <(NativeBody, NativeBody)>[(c.a, c.b), (c.b, c.a)]) {
        if (aimed[it] case final MapPiece stone? when stone._aim != null) {
          final MapHall hall = stone._aim!;
          stone._aim = null;
          if (hall._stones.contains(other)) breaks.add((hall, c.point));
        }
        if (flying[it] case final _Arrow arrow? when !spent.contains(it)) {
          spent.add(it);
          if (arrow.hall.timbers.contains(other)) {
            _held.add((
              body: other,
              at: c.point.clone(),
              left: _fireArrow.seconds,
            ));
          }
        }
      }
    }
    _arrows.removeWhere((_Arrow arrow) {
      final gone = spent.contains(arrow.body) || arrow.age > _arrowFlies;
      if (gone && world.contains(arrow.body)) world.removeBody(arrow.body);
      return gone;
    });
    for (var i = 0; i < _arrows.length; i++) {
      final _Arrow a = _arrows[i];
      _arrows[i] = (body: a.body, hall: a.hall, age: a.age + dt);
    }
    for (final (MapHall hall, Vector3 at) in breaks) {
      _breakOff(hall, at);
    }
  }

  /// How long an arrow is let fly before it is taken to have gone off the
  /// map, s: longer than any lob over a hall's range.
  static const double _arrowFlies = 10.0;

  /// The brands the fires loft this step, while few enough burn
  /// ([_mostFires]), and [pieces] brought up to them: a new brand drawn, a
  /// spent one no longer.
  void _loft(double dt) {
    if (world.fires().length < _mostFires) _brands.step(dt);
    final aloft = _brands.brands.toSet();
    pieces.removeWhere(
      (MapPiece p) => p.kind == PieceKind.brand && !aloft.contains(p.body),
    );
    final drawn = <NativeBody>{
      for (final MapPiece p in pieces)
        if (p.kind == PieceKind.brand) p.body,
    };
    final size = Vector3.all(_brand.shape.first);
    for (final NativeBody body in _brands.brands) {
      if (!drawn.contains(body)) {
        pieces.add(MapPiece._(body, PieceKind.brand, size.clone()));
      }
    }
  }

  /// A tree burnt out, from what the step said.
  void _burnt(List<NativeEvent> happened) {
    for (final NativeEvent event in happened) {
      if (event.kind != NativeEventKind.burntOut) continue;
      _treeOf[event.body]?._dead = true;
    }
  }

  /// A brand in a crown lights it; grounded brands and the oldest stones
  /// are taken out.
  void _fly(double dt, StrategySimulation simulation) {
    for (final MapPiece piece in pieces) {
      piece._age += dt;
    }

    // A brand lights a crown it comes down in with its own flame; the crown
    // it is in is given a body for that, if the viewing side has found it.
    // On the ground, it is gone; burnt out, the brands let it go.
    pieces.removeWhere((MapPiece piece) {
      if (piece.kind != PieceKind.brand) return false;
      final Vector3 at = world.localPositionOf(piece.body);
      final MapTree? crown = _crownAt(at, simulation);
      if (crown != null && crown.body == null) {
        _bare.remove(crown);
        _grow(crown);
      }
      final bool gone = at.y < _field.heightAt(at.x, at.z) + 0.05;
      if (gone) _brands.remove(piece.body);
      return gone;
    });

    var stones = pieces.where((MapPiece p) => p.kind != PieceKind.brand).length;
    pieces.removeWhere((MapPiece piece) {
      if (stones <= _mostStones || piece.kind == PieceKind.brand) return false;
      stones--;
      world.removeBody(piece.body);
      return true;
    });
  }

  /// The tree whose crown [at] is inside, and that can still catch: one
  /// with a body not yet alight, or one the viewing side has found that has
  /// none yet.
  MapTree? _crownAt(Vector3 at, StrategySimulation simulation) {
    final int cx = (at.x / _lattice).floor(), cz = (at.z / _lattice).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dz = -1; dz <= 1; dz++) {
        for (final MapTree tree
            in _byCell[(cx + dx) * 4096 + cz + dz] ?? const <MapTree>[]) {
          if (tree.dead) continue;
          final double ddx = at.x - tree.x, ddz = at.z - tree.z;
          final double r = tree.radius + 0.8;
          if (ddx * ddx + ddz * ddz > r * r) continue;
          if ((at.y - tree.middle).abs() > tree.halfHeight + 0.5) continue;
          final NativeBody? body = tree.body;
          if (body != null
              ? world.isBurning(body)
              : !_found(tree, simulation)) {
            continue;
          }
          return tree;
        }
      }
    }
    return null;
  }

  /// Whether the viewing side has found [tree] and the ground for [_margin]
  /// metres around it.
  ///
  /// **Not the tree alone.** A crown at the edge of what has been explored
  /// burned with its flame leaning out over the black, and its smoke drawn
  /// across ground the map has not shown yet; a tree that close to the fog
  /// does not catch, so the fire stops where the map stops.
  bool _found(MapTree tree, StrategySimulation simulation) {
    final FogOfWar fog = simulation.fog;
    bool knows(double dx, double dz) =>
        fog.knows(viewer, tree.x + dx, tree.z + dz);
    return knows(0.0, 0.0) &&
        knows(_margin, 0.0) &&
        knows(-_margin, 0.0) &&
        knows(0.0, _margin) &&
        knows(0.0, -_margin);
  }

  /// Pieces of [hall]'s wall knocked loose where a stone struck it at [at],
  /// thrown back off the wall.
  void _breakOff(MapHall hall, Vector3 at) {
    final Vector3 c = hall.building.center;
    final out = Vector3(at.x - c.x, 0.0, at.z - c.z);
    if (out.length2 < 1e-6) out.setValues(0.0, 0.0, 1.0);
    out.normalize();
    final int count = 2 + _random.nextInt(3);
    for (var i = 0; i < count; i++) {
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
      pieces.add(
        MapPiece._(body, PieceKind.rubble, Vector3(half, half * 0.7, half)),
      );
    }
  }

  // ------------------------------------------------------------------ saving

  /// The core's own snapshot, and everything here that says what its bodies
  /// are: which trees have crowns and which have burnt out, what each loose
  /// body is and where a stone was thrown, the fire arrows still held, the
  /// clock the wind blows by and the dice.
  Map<String, Object?> _save() => <String, Object?>{
    'core': base64Encode(world.snapshot()),
    'random': _random.state,
    'clock': _clock,
    'ticks': _ticks,
    'trees': <List<int>>[
      for (final MapTree tree in trees)
        <int>[tree.body?.raw ?? -1, if (tree.dead) 1 else 0],
    ],
    'burnable': <int>[for (final MapTree tree in burnable) trees.indexOf(tree)],
    'pieces': <List<Object>>[
      for (final MapPiece piece in pieces)
        <Object>[
          piece.body.raw,
          piece.kind.index,
          piece.size.x,
          piece.size.y,
          piece.size.z,
          piece._aim?.index ?? -1,
          piece._age,
        ],
    ],
    'held': <List<Object>>[
      for (final h in _held)
        <Object>[h.body.raw, h.at.x, h.at.y, h.at.z, h.left],
    ],
    'arrows': <List<Object>>[
      for (final _Arrow a in _arrows) <Object>[a.body.raw, a.hall.index, a.age],
    ],
    'brands': _brands.save(),
  };

  /// Back to what [_save] wrote. A snapshot the core will not take — one
  /// from another build of it — leaves the world as it is.
  void _restore(Object? data) {
    if (data is! Map) return;
    final Object? core = data['core'];
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
    double number(Object? value, double otherwise) =>
        value is num ? value.toDouble() : otherwise;
    _random.state = integer(data['random'], _random.state);
    _clock = number(data['clock'], _clock);
    _ticks = integer(data['ticks'], _ticks);

    final Object? rows = data['trees'];
    for (var i = 0; i < trees.length; i++) {
      final MapTree tree = trees[i];
      final Object? row = rows is List && i < rows.length ? rows[i] : null;
      final (int raw, bool dead) = switch (row) {
        [final num raw, final num dead, ...] => (raw.toInt(), dead != 0),
        _ => (-1, false),
      };
      tree
        .._body = raw < 0 ? null : NativeBody(raw)
        .._dead = dead;
    }
    _bare
      ..clear()
      ..addAll(trees.where((MapTree tree) => tree.body == null));
    _treeOf
      ..clear()
      ..addAll(<NativeBody, MapTree>{
        for (final MapTree tree in trees)
          if (tree.body case final NativeBody body) body: tree,
      });
    burnable
      ..clear()
      ..addAll(<MapTree>[
        if (data['burnable'] case final List<Object?> order)
          for (final Object? index in order)
            if (index is num &&
                index >= 0 &&
                index < trees.length &&
                trees[index.toInt()].body != null)
              trees[index.toInt()],
      ]);

    pieces
      ..clear()
      ..addAll(<MapPiece>[
        if (data['pieces'] case final List<Object?> all)
          for (final Object? row in all)
            if (row case [
              final num raw,
              final num kind,
              final num x,
              final num y,
              final num z,
              final num aim,
              final num age,
              ...,
            ] when kind >= 0 && kind < PieceKind.values.length)
              MapPiece._(
                  NativeBody(raw.toInt()),
                  PieceKind.values[kind.toInt()],
                  Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
                )
                .._aim = aim >= 0 && aim < halls.length
                    ? halls[aim.toInt()]
                    : null
                .._age = age.toDouble(),
      ]);
    _held
      ..clear()
      ..addAll(<({NativeBody body, Vector3 at, double left})>[
        if (data['held'] case final List<Object?> all)
          for (final Object? row in all)
            if (row case [
              final num raw,
              final num x,
              final num y,
              final num z,
              final num left,
              ...,
            ])
              (
                body: NativeBody(raw.toInt()),
                at: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
                left: left.toDouble(),
              ),
      ]);
    _arrows
      ..clear()
      ..addAll(<_Arrow>[
        if (data['arrows'] case final List<Object?> all)
          for (final Object? row in all)
            if (row case [
              final num raw,
              final num hall,
              final num age,
              ...,
            ] when hall >= 0 && hall < halls.length)
              (
                body: NativeBody(raw.toInt()),
                hall: halls[hall.toInt()],
                age: age.toDouble(),
              ),
      ]);
    _brands.restore(data['brands']);
    _events.clear();
  }

  /// Takes the world off the simulation and gives it back: the simulation
  /// steps and saves without it from here on.
  void dispose() {
    if (_simulation.pace == _pace) _simulation.pace = null;
    _simulation.afterStep.remove(_afterStep);
    // Found again rather than taken from where it was spawned: a restore
    // puts back the save's generations, and the handle kept from then may
    // no longer be the one the world rides on.
    final entities = _simulation.entities;
    for (final Entity entity in entities.queryOf<MapWorld>().toList()) {
      if (identical(entities.get<MapWorld>(entity), this)) {
        entities.despawn(entity);
      }
    }
    world.dispose();
  }
}
