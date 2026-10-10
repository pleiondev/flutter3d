/// Where an agent can stand, as convex polygons rather than cells.
///
/// ## The bake
///
/// Brushes and terrain are voxelised into columns of solid spans; the tops of
/// those spans are filtered into floors an agent fits on and can step between;
/// the floors are eroded by the agent's radius, cut into regions, outlined,
/// and the outlines cut into convex polygons that know their neighbours. Each
/// stage is a file in this directory and says why it is shaped the way it is.
///
/// ## Why it is the same mesh everywhere
///
/// The voxeliser is the only stage that sees a floating-point number, and it
/// turns each into a whole number of voxels by one division and one rounding.
/// Everything after compares and adds integers, sweeps the lattice in one
/// fixed order, and keeps no map it walks. So [digest] is a fact about the
/// level and the [config] and not about the machine, and CI holds it fixed on
/// every operating system it runs on.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../level/heightfield.dart';
import '../../level/level.dart';
import '../../save/state_digest.dart';
import '../jump_links.dart';
import 'contours.dart';
import 'distance_field.dart';
import 'mesh_links.dart';
import 'navmesh_config.dart';
import 'open_field.dart';
import 'poly_mesh.dart';
import 'regions.dart';
import 'route.dart';
import 'span_field.dart';

/// The surfaces a polygon can be, by number.
///
/// A number and not an enum because the set is the game's: mud, a shallow
/// ford, a road a cart prefers. The mesh only carries the number to whatever
/// path search will price it, and keeps two values for itself.
abstract final class NavArea {
  /// Not a surface. No polygon has it; a brush given it is not walked on.
  static const int none = 0;

  /// Ground, when nothing says otherwise.
  static const int ground = 1;
}

/// Convex polygons over a level's floors, and which of them touch.
final class NavMesh {
  NavMesh._({
    required this.config,
    required this.lattice,
    required this._tileContours,
    required this._vertices,
    required this._polygons,
    required this._neighbors,
    required this._areas,
    required this._columnStart,
    required this._floors,
    this.links = const <NavMeshLink>[],
  });

  /// What the mesh was baked to. Part of [digest].
  final NavMeshSettings config;

  /// The cells the mesh was baked on, which a part baked again keeps.
  final NavLattice lattice;

  /// The world position of lattice point `(0, 0, 0)`: its X, in metres.
  double get originX => lattice.originX;

  /// Lattice point `(0, 0, 0)`'s Y, in metres.
  double get originY => lattice.originY;

  /// Lattice point `(0, 0, 0)`'s Z, in metres.
  double get originZ => lattice.originZ;

  /// The outlines the polygons were cut from, tile by tile, in tile order:
  /// what [rebake] replaces a part of and cuts again.
  final List<List<Contour>> _tileContours;

  final Int32List _vertices;
  final Int32List _polygons;
  final Int32List _neighbors;
  final Uint8List _areas;

  /// The floors a body may stand on, column by column of the lattice, in
  /// voxels: column `c`'s are `_floors[_columnStart[c]]` up to
  /// `_floors[_columnStart[c + 1]]`, lowest first. The heights the polygons'
  /// corners cannot carry — see [heightAt].
  int get _columns => lattice.columns;
  int get _rows => lattice.rows;
  final Int32List _columnStart;
  final Int32List _floors;

  /// The jumps the bake found between polygons the walk does not join —
  /// none unless it was given a reach. See [NavMeshLink].
  final List<NavMeshLink> links;

  /// Indices into [links] of the jumps that leave [polygon], in [links]'
  /// order.
  List<int> linksFrom(int polygon) => _linksFrom[polygon];

  late final List<List<int>> _linksFrom = () {
    final out = List<List<int>>.generate(polygonCount, (_) => <int>[]);
    for (var i = 0; i < links.length; i++) {
      out[links[i].from].add(i);
    }
    return out;
  }();

  int get maxVerticesPerPolygon => config.maxVerticesPerPolygon;

  int get vertexCount => _vertices.length ~/ 3;
  int get polygonCount => _areas.length;

  /// True when there is nowhere to stand: an empty level, or one whose every
  /// floor the filters refused.
  bool get isEmpty => polygonCount == 0;

  /// A vertex on the lattice, in cells across and voxels up. Whole numbers,
  /// which is what a test compares and what [digest] is taken of.
  int latticeX(int vertex) => _vertices[vertex * 3];
  int latticeY(int vertex) => _vertices[vertex * 3 + 1];
  int latticeZ(int vertex) => _vertices[vertex * 3 + 2];

  /// A vertex in the world.
  void vertexAt(int vertex, Vector3 out) => out.setValues(
    originX + latticeX(vertex) * config.cellSize,
    originY + latticeY(vertex) * config.cellHeight,
    originZ + latticeZ(vertex) * config.cellSize,
  );

  /// How many corners [polygon] has.
  int polygonVertexCount(int polygon) {
    final base = polygon * maxVerticesPerPolygon;
    var n = 0;
    while (n < maxVerticesPerPolygon && _polygons[base + n] >= 0) {
      n++;
    }
    return n;
  }

  /// Corner [k] of [polygon]. Corners run so that the polygon turns left at
  /// each in the `(x, z)` plane: x across, z up the page.
  int polygonVertex(int polygon, int k) =>
      _polygons[polygon * maxVerticesPerPolygon + k];

  /// The polygon across edge [k] of [polygon] — the edge from corner `k` to
  /// corner `k + 1` — or −1 where the edge is a wall or a drop.
  int neighborAt(int polygon, int k) =>
      _neighbors[polygon * maxVerticesPerPolygon + k];

  /// The surface [polygon] is, from the bake's `areaOf`. Never [NavArea.none].
  int areaOf(int polygon) => _areas[polygon];

  /// Whether the world point `(x, z)` lies on [polygon] in plan, edges
  /// included.
  bool containsPoint(int polygon, double x, double z) {
    final u = (x - originX) / config.cellSize;
    final v = (z - originZ) / config.cellSize;
    final n = polygonVertexCount(polygon);
    for (var k = 0; k < n; k++) {
      final a = polygonVertex(polygon, k);
      final b = polygonVertex(polygon, (k + 1) % n);
      final ax = latticeX(a);
      final az = latticeZ(a);
      final turn =
          (latticeX(b) - ax) * (v - az) - (latticeZ(b) - az) * (u - ax);
      if (turn < 0.0) return false;
    }
    return true;
  }

  /// Every polygon over `(x, z)` in plan, lowest index first — one per floor
  /// where floors are stacked.
  ///
  /// Asked of the polygons [_byColumn] lists for the lattice column under
  /// the point, not of every polygon: a body asks this every step, and on a
  /// mesh of hundreds of polygons the walk over all of them was most of what
  /// finding its route cost.
  List<int> polygonsAt(double x, double z) {
    final cx = ((x - originX) / config.cellSize).floor();
    final cz = ((z - originZ) / config.cellSize).floor();
    if (cx < 0 || cz < 0 || cx >= _columns || cz >= _rows) return <int>[];
    final (start, polygons) = _byColumn;
    final c = cz * _columns + cx;
    return <int>[
      for (var i = start[c]; i < start[c + 1]; i++)
        if (containsPoint(polygons[i], x, z)) polygons[i],
    ];
  }

  /// For each lattice column, the polygons whose extent in plan reaches it,
  /// lowest index first: column `c`'s are `polygons[start[c]]` up to
  /// `polygons[start[c + 1]]`.
  ///
  /// **Up to the column its far corners start**, not the last one it covers,
  /// because a polygon's edges count as on it and a point on its far edge is
  /// in the next column over. Nothing outside the lattice is on the mesh: the bake
  /// puts every floor inside it.
  late final (Int32List, Int32List) _byColumn = () {
    final count = _columns * _rows;
    final lists = List<List<int>>.generate(count, (_) => <int>[]);
    for (var p = 0; p < polygonCount; p++) {
      var x0 = 1 << 30;
      var x1 = -(1 << 30);
      var z0 = 1 << 30;
      var z1 = -(1 << 30);
      for (var k = 0; k < polygonVertexCount(p); k++) {
        final v = polygonVertex(p, k);
        x0 = math.min(x0, latticeX(v));
        x1 = math.max(x1, latticeX(v));
        z0 = math.min(z0, latticeZ(v));
        z1 = math.max(z1, latticeZ(v));
      }
      for (var cz = math.max(0, z0); cz <= math.min(_rows - 1, z1); cz++) {
        for (var cx = math.max(0, x0); cx <= math.min(_columns - 1, x1); cx++) {
          lists[cz * _columns + cx].add(p);
        }
      }
    }
    final start = Int32List(count + 1);
    for (var c = 0; c < count; c++) {
      start[c + 1] = start[c] + lists[c].length;
    }
    return (start, Int32List.fromList(<int>[for (final l in lists) ...l]));
  }();

  /// The height of [polygon]'s surface over `(x, z)`.
  ///
  /// **A polygon's corners are not its surface.** A floor and the ramp up
  /// from it are one region, and can be one polygon whose corners are at the
  /// foot of the floor and the top of the ramp; between them the corners say
  /// a slope where there is a flat. So the corners give a first guess, from
  /// the triangle of the polygon's fan the point is over, and the floor of
  /// the lattice column under the point nearest that guess is the answer —
  /// floors stacked in one column are a body's height apart, far more than
  /// the guess is ever out. Where the column has no floor a body may stand
  /// on, an edge or a rim, the guess is the answer.
  double heightAt(int polygon, double x, double z) {
    final guess = _cornerHeightAt(polygon, x, z);
    final cx = ((x - originX) / config.cellSize).floor();
    final cz = ((z - originZ) / config.cellSize).floor();
    if (cx < 0 || cz < 0 || cx >= _columns || cz >= _rows) return guess;
    final c = cz * _columns + cx;
    final voxels = (guess - originY) / config.cellHeight;
    var best = -1;
    var distance = config.walkableHeight / 2;
    for (var i = _columnStart[c]; i < _columnStart[c + 1]; i++) {
      final d = (_floors[i] - voxels).abs();
      if (d < distance) (best, distance) = (_floors[i], d);
    }
    return best < 0 ? guess : originY + best * config.cellHeight;
  }

  /// [heightAt]'s first guess: the height of the triangle of [polygon]'s fan
  /// that `(x, z)` is over, or of the nearest one, extended, for a point
  /// outside it in plan.
  double _cornerHeightAt(int polygon, double x, double z) {
    final n = polygonVertexCount(polygon);
    final a = Vector3.zero();
    final b = Vector3.zero();
    final c = Vector3.zero();
    vertexAt(polygonVertex(polygon, 0), a);
    var best = double.infinity;
    var height = a.y;
    for (var k = 1; k + 1 < n; k++) {
      vertexAt(polygonVertex(polygon, k), b);
      vertexAt(polygonVertex(polygon, k + 1), c);
      final area = (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);
      final wb = ((x - a.x) * (c.z - a.z) - (z - a.z) * (c.x - a.x)) / area;
      final wc = ((b.x - a.x) * (z - a.z) - (b.z - a.z) * (x - a.x)) / area;
      final wa = 1.0 - wb - wc;
      // How far outside the triangle the point is, by its most negative
      // weight; nought inside.
      final outside = -math.min(0.0, math.min(wa, math.min(wb, wc)));
      if (outside < best) {
        best = outside;
        height = wa * a.y + wb * b.y + wc * c.y;
      }
    }
    return height;
  }

  /// The polygon a body at [at] stands on: of the polygons over it in plan,
  /// the one whose surface there is nearest its height, or −1 when no
  /// polygon is under it at all.
  ///
  /// Nearest and not nearest below: a body in the air over a floor is
  /// still over that floor, and one a little under a ramp's surface — the
  /// mesh is a voxel coarse — still stands on the ramp.
  int polygonAt(Vector3 at) {
    var best = -1;
    var distance = double.infinity;
    for (final p in polygonsAt(at.x, at.z)) {
      final d = (heightAt(p, at.x, at.z) - at.y).abs();
      if (d < distance) (best, distance) = (p, d);
    }
    return best;
  }

  /// The point of [polygon] nearest [at] in plan, on its surface, into
  /// [out].
  void closestPointOn(int polygon, Vector3 at, Vector3 out) {
    var x = at.x;
    var z = at.z;
    if (!containsPoint(polygon, x, z)) {
      final n = polygonVertexCount(polygon);
      final a = Vector3.zero();
      final b = Vector3.zero();
      var best = double.infinity;
      for (var k = 0; k < n; k++) {
        vertexAt(polygonVertex(polygon, k), a);
        vertexAt(polygonVertex(polygon, (k + 1) % n), b);
        final ex = b.x - a.x;
        final ez = b.z - a.z;
        final t =
            (((at.x - a.x) * ex + (at.z - a.z) * ez) / (ex * ex + ez * ez))
                .clamp(0.0, 1.0);
        final px = a.x + ex * t;
        final pz = a.z + ez * t;
        final d = (px - at.x) * (px - at.x) + (pz - at.z) * (pz - at.z);
        if (d < best) (best, x, z) = (d, px, pz);
      }
    }
    out.setValues(x, heightAt(polygon, x, z), z);
  }

  /// The polygon nearest [at] within [within] metres, its nearest point
  /// into [out]; −1, and [out] untouched, when there is none.
  ///
  /// For a body that is not over the mesh but is near it: on a floor's
  /// eroded rim, where the mesh keeps its centre away from the edge and
  /// the floor still holds it up. Every polygon is looked at, in order, so
  /// the nearest of two equally near is the lower index.
  int nearestPolygon(Vector3 at, Vector3 out, {required double within}) {
    final near = Vector3.zero();
    var best = -1;
    var distance = within * within;
    for (var p = 0; p < polygonCount; p++) {
      closestPointOn(p, at, near);
      final d = near.distanceToSquared(at);
      if (d <= distance) {
        if (best >= 0 && d == distance) continue;
        (best, distance) = (p, d);
        out.setFrom(near);
      }
    }
    return best;
  }

  /// The way from [from] to [to] — see [NavMeshRoute] — or null when [from]
  /// is over no polygon.
  ///
  /// [costOf] prices a metre of each area, one or more; [double.infinity]
  /// keeps a route off an area altogether. [jumps] is the body's reach, and
  /// the [links] within it are taken; without it the route walks.
  NavMeshRoute? route(
    Vector3 from,
    Vector3 to, {
    double Function(int area)? costOf,
    JumpReach? jumps,
  }) => findRoute(this, from, to, costOf: costOf, jumps: jumps);

  /// One number for the whole mesh and what it was baked to.
  ///
  /// Taken of the lattice — whole numbers of cells and voxels — and the
  /// config, through [StateDigest], so it is the same bits on every platform
  /// a run is replayed on. Two bakes of one level agree on it or one of them
  /// is wrong.
  int get digest {
    final digest = StateDigest()
      ..add(config.values)
      ..add(<double>[originX, originY, originZ])
      ..add(_vertices)
      ..add(_polygons)
      ..add(_neighbors)
      ..add(_areas)
      ..add(_columnStart)
      ..add(_floors);
    // Only when there are some, so a walked mesh keeps the digest it had
    // before links existed.
    if (links.isNotEmpty) {
      digest.add(<double>[
        for (final link in links) ...<double>[
          link.from.toDouble(),
          link.to.toDouble(),
          link.start.x,
          link.start.y,
          link.start.z,
          link.end.x,
          link.end.y,
          link.end.z,
        ],
      ]);
    }
    return digest.value;
  }

  /// [digest] as eight hexadecimal digits, the way a test writes it down.
  String get digestHex => digest.toRadixString(16).padLeft(8, '0');

  /// Bakes the level's architecture and its ground.
  ///
  /// Recipes are expanded first, as everything that uses a level does — see
  /// `expandRecipes`.
  static NavMesh bakeLevel(
    Level level, {
    NavMeshSettings config = const NavMeshSettings(),
    int Function(Brush brush)? areaOf,
    int groundArea = NavArea.ground,
    JumpReach? jumps,
    double maxFall = 2.0,
  }) => bake(
    expandRecipes(level).brushes,
    ground: level.heightfield,
    config: config,
    areaOf: areaOf,
    groundArea: groundArea,
    jumps: jumps,
    maxFall: maxFall,
  );

  /// Bakes one mesh per width of body among [bodies] — each a radius and a
  /// height — narrowest first, for `ActorSystem.navMeshes`.
  ///
  /// Two radii the lattice erodes by the same number of cells bake the same
  /// polygons, so their bodies share one mesh, baked for the widest radius
  /// and the tallest height among them — which a body of any of them then
  /// fits. Everything else is [config]'s, and as [bakeLevel].
  static List<NavMesh> bakeLevelFor(
    Level level,
    Iterable<(double radius, double height)> bodies, {
    NavMeshSettings config = const NavMeshSettings(),
    int Function(Brush brush)? areaOf,
    JumpReach? jumps,
    double maxFall = 2.0,
  }) {
    // The widest radius and tallest height of each erosion, by erosion: a
    // map only looked up and then read in sorted order.
    final classes = <int, (double, double)>{};
    for (final (radius, height) in bodies) {
      final erosion = config.withBody(radius: radius, height: height).erosion;
      final (r, h) = classes[erosion] ?? (radius, height);
      classes[erosion] = (math.max(r, radius), math.max(h, height));
    }
    final order = classes.keys.toList()..sort();
    return <NavMesh>[
      for (final erosion in order)
        bakeLevel(
          level,
          config: config.withBody(
            radius: classes[erosion]!.$1,
            height: classes[erosion]!.$2,
          ),
          areaOf: areaOf,
          jumps: jumps,
          maxFall: maxFall,
        ),
    ];
  }

  /// Bakes [brushes] and, when given, [ground] into one mesh.
  ///
  /// [areaOf] names the surface of each brush's top, [NavArea.ground] unless
  /// it says otherwise; [NavArea.none] keeps agents off a brush entirely —
  /// lava, a roof the game does not want walked. [groundArea] is the
  /// terrain's.
  ///
  /// [jumps] adds [links]: the gaps and ledges a body of that reach jumps,
  /// and the drops of at most [maxFall] it jumps down — bake with the most
  /// capable reach a level's bodies have, and let each route filter by its
  /// own body's. Without it the mesh is walked only.
  ///
  /// **From brushes, not from the collision world**, for `NavGrid`'s reason:
  /// the collision world has doors in it, and a mesh baked with a door closed
  /// is a mesh with a wall where the door is.
  static NavMesh bake(
    Iterable<Brush> brushes, {
    Heightfield? ground,
    NavMeshSettings config = const NavMeshSettings(),
    int Function(Brush brush)? areaOf,
    int groundArea = NavArea.ground,
    JumpReach? jumps,
    double maxFall = 2.0,
    NavLattice? lattice,
  }) {
    final grid =
        lattice ?? NavLattice.of(brushes, config: config, ground: ground);
    final (across, down) = _tileCounts(config, grid);
    final all = (x0: 0, z0: 0, x1: across, z1: down);
    final baked = _bakeWindow(
      brushes,
      ground: ground,
      config: config,
      areaOf: areaOf ?? (_) => NavArea.ground,
      groundArea: groundArea,
      lattice: grid,
      window: (x0: 0, z0: 0, x1: grid.columns, z1: grid.rows),
      regionTiles: all,
      contourTiles: all,
    );
    final floors = _standingFloors(baked.open);
    final walked = _assemble(
      config,
      grid,
      baked.contours,
      floors.start,
      floors.floors,
    );
    if (jumps == null) return walked;
    return _assemble(
      config,
      grid,
      baked.contours,
      floors.start,
      floors.floors,
      links: List<NavMeshLink>.unmodifiable(
        bakeMeshLinks(
          baked.open,
          baked.solid,
          config: config,
          reach: jumps,
          maxFall: maxFall,
          polygonAt: walked.polygonAt,
        ),
      ),
    );
  }

  /// This mesh with the part of it over the world rectangle from
  /// `(minX, minZ)` to `(maxX, maxZ)` baked again from [brushes] and
  /// [ground] — the whole level as it now is, and the same [areaOf] and
  /// [groundArea] it was baked with.
  ///
  /// **The same mesh as baking the changed level whole**, on this mesh's
  /// lattice, digest for digest: a tile's regions are its own, so the tiles
  /// the change reaches — the rectangle widened by the agent's erosion — are
  /// baked again, their neighbours outlined again against them, and the
  /// polygons cut again from every outline. Two rings of tiles and the
  /// erosion around them are rasterised for that, a fixed amount whatever
  /// the size of the level.
  ///
  /// Refused for a mesh baked without tiles ([NavMeshSettings.tileSize]),
  /// with jumps, or with [NavMeshSettings.minIslandArea]: an island is a fact
  /// about all of a floor, and a jump about everything within a flight.
  /// The level may not grow past the lattice: what is outside it is not
  /// baked.
  NavMesh rebake(
    Iterable<Brush> brushes, {
    Heightfield? ground,
    int Function(Brush brush)? areaOf,
    int groundArea = NavArea.ground,
    required double minX,
    required double minZ,
    required double maxX,
    required double maxZ,
  }) {
    final size = config.tileSize;
    if (size <= 0) {
      throw StateError(
        'a mesh baked without tiles is baked again whole: set '
        'NavMeshConfig.tileSize to bake a part of it again',
      );
    }
    if (links.isNotEmpty) {
      throw UnsupportedError('a mesh with jumps is baked again whole');
    }
    if (config.minIslandCells > 1) {
      throw UnsupportedError(
        'a mesh that drops islands is baked again whole: an island is a '
        'fact about all of a floor',
      );
    }
    if (lattice.isEmpty) return this;

    final cs = config.cellSize;
    final margin = config.erosion + 1;
    final (across, down) = _tileCounts(config, lattice);
    int column(double x) => ((x - originX) / cs).floor().clamp(0, _columns - 1);
    int row(double z) => ((z - originZ) / cs).floor().clamp(0, _rows - 1);

    // The tiles the change reaches: the rectangle, widened by the erosion,
    // which moves where a floor ends that far.
    final changed = (
      x0: (column(minX) - margin).clamp(0, _columns - 1) ~/ size,
      z0: (row(minZ) - margin).clamp(0, _rows - 1) ~/ size,
      x1: (column(maxX) + margin).clamp(0, _columns - 1) ~/ size + 1,
      z1: (row(maxZ) + margin).clamp(0, _rows - 1) ~/ size + 1,
    );
    ({int x0, int z0, int x1, int z1}) widened(int by) => (
      x0: math.max(0, changed.x0 - by),
      z0: math.max(0, changed.z0 - by),
      x1: math.min(across, changed.x1 + by),
      z1: math.min(down, changed.z1 + by),
    );
    // Outlined again: the changed tiles and the ring round them, whose
    // borders with them may have moved. Given regions: one ring further, for
    // what lies beyond those borders.
    final outlined = widened(1);
    final regioned = widened(2);
    final baked = _bakeWindow(
      brushes,
      ground: ground,
      config: config,
      areaOf: areaOf ?? (_) => NavArea.ground,
      groundArea: groundArea,
      lattice: lattice,
      window: (
        x0: math.max(0, regioned.x0 * size - margin),
        z0: math.max(0, regioned.z0 * size - margin),
        x1: math.min(_columns, regioned.x1 * size + margin),
        z1: math.min(_rows, regioned.z1 * size + margin),
      ),
      regionTiles: regioned,
      contourTiles: outlined,
    );

    final contours = List<List<Contour>>.of(_tileContours);
    var k = 0;
    for (var tz = outlined.z0; tz < outlined.z1; tz++) {
      for (var tx = outlined.x0; tx < outlined.x1; tx++) {
        contours[tz * across + tx] = baked.contours[k++];
      }
    }

    // The standing floors: the changed tiles' columns from the window, the
    // rest as they were, copied a run at a time.
    final open = baked.open;
    final cx0 = changed.x0 * size;
    final cz0 = changed.z0 * size;
    final cx1 = math.min(_columns, changed.x1 * size);
    final cz1 = math.min(_rows, changed.z1 * size);
    final start = Int32List(_columns * _rows + 1);
    final out = <int>[];
    for (var cz = 0; cz < _rows; cz++) {
      for (var cx = 0; cx < _columns; cx++) {
        final c = cz * _columns + cx;
        start[c] = out.length;
        if (cx >= cx0 && cx < cx1 && cz >= cz0 && cz < cz1) {
          final local =
              (cz - open.offsetZ) * open.columns + (cx - open.offsetX);
          for (
            var s = open.cellStart[local];
            s < open.cellStart[local + 1];
            s++
          ) {
            if (open.area[s] != nullArea) out.add(open.floor[s]);
          }
        } else {
          for (var i = _columnStart[c]; i < _columnStart[c + 1]; i++) {
            out.add(_floors[i]);
          }
        }
      }
    }
    start[_columns * _rows] = out.length;
    final floors = (start: start, floors: Int32List.fromList(out));
    return _assemble(config, lattice, contours, floors.start, floors.floors);
  }

  /// How many tiles across and down [lattice] is cut into: one by one when
  /// it is not tiled.
  static (int, int) _tileCounts(NavMeshSettings config, NavLattice lattice) {
    final size = config.tileSize;
    if (size == 0) return (1, 1);
    return (
      (lattice.columns + size - 1) ~/ size,
      (lattice.rows + size - 1) ~/ size,
    );
  }

  /// The stages of a bake over [window] of [lattice], up to the outlines:
  /// regions for the tiles [regionTiles], outlines for [contourTiles], one
  /// list per tile in row order.
  static ({SpanField solid, OpenField open, List<List<Contour>> contours})
  _bakeWindow(
    Iterable<Brush> brushes, {
    required Heightfield? ground,
    required NavMeshSettings config,
    required int Function(Brush brush) areaOf,
    required int groundArea,
    required NavLattice lattice,
    required NavWindow window,
    required ({int x0, int z0, int x1, int z1}) regionTiles,
    required ({int x0, int z0, int x1, int z1}) contourTiles,
  }) {
    final solid =
        SpanField.rasterise(
            brushes,
            config: config,
            ground: ground,
            areaOf: areaOf,
            groundArea: groundArea,
            lattice: lattice,
            window: window,
          )
          ..filterLowHangingObstacles(config.walkableClimb)
          ..filterLowHeight(config.walkableHeight);

    final open = OpenField.build(
      solid,
      height: config.walkableHeight,
      climb: config.walkableClimb,
    );
    erode(open, distanceField(open, config.walkableClimb), config.erosion);
    dropIslands(open, config.minIslandCells);

    final size = config.tileSize;
    final (across, _) = _tileCounts(config, lattice);
    final region = monotoneRegions(
      open,
      tiles: (
        size: size,
        across: across,
        x0: regionTiles.x0,
        z0: regionTiles.z0,
        x1: regionTiles.x1,
        z1: regionTiles.z1,
      ),
    );
    final rects = <({int x0, int z0, int x1, int z1})>[
      for (var tz = contourTiles.z0; tz < contourTiles.z1; tz++)
        for (var tx = contourTiles.x0; tx < contourTiles.x1; tx++)
          size == 0
              ? (x0: 0, z0: 0, x1: open.columns, z1: open.rows)
              : (
                  x0: math.max(0, tx * size - open.offsetX),
                  z0: math.max(0, tz * size - open.offsetZ),
                  x1: math.min(open.columns, (tx + 1) * size - open.offsetX),
                  z1: math.min(open.rows, (tz + 1) * size - open.offsetZ),
                ),
    ];
    return (
      solid: solid,
      open: open,
      contours: buildContours(
        open,
        region,
        maxError: config.maxEdgeError,
        rects: rects,
      ),
    );
  }

  /// The mesh cut from [tileContours], every tile's in tile order.
  static NavMesh _assemble(
    NavMeshSettings config,
    NavLattice lattice,
    List<List<Contour>> tileContours,
    Int32List columnStart,
    Int32List floors, {
    List<NavMeshLink> links = const <NavMeshLink>[],
  }) {
    final parts = buildPolyMesh(<Contour>[
      for (final tile in tileContours) ...tile,
    ], maxCorners: config.maxVerticesPerPolygon);
    return NavMesh._(
      config: config,
      lattice: lattice,
      tileContours: tileContours,
      vertices: parts.vertices,
      polygons: parts.polygons,
      neighbors: parts.neighbors,
      areas: parts.areas,
      columnStart: columnStart,
      floors: floors,
      links: links,
    );
  }

  /// Per-column lists packed into a start index and one array.
  static ({Int32List start, Int32List floors}) _packed(List<List<int>> lists) {
    final start = Int32List(lists.length + 1);
    for (var c = 0; c < lists.length; c++) {
      start[c + 1] = start[c] + lists[c].length;
    }
    return (
      start: start,
      floors: Int32List.fromList(<int>[for (final l in lists) ...l]),
    );
  }

  /// The floors of [open] a body may stand on, column by column.
  static ({Int32List start, Int32List floors}) _standingFloors(
    OpenField open,
  ) => _packed(<List<int>>[
    for (var c = 0; c < open.columns * open.rows; c++)
      <int>[
        for (var s = open.cellStart[c]; s < open.cellStart[c + 1]; s++)
          if (open.area[s] != nullArea) open.floor[s],
      ],
  ]);
}
