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
    required this.originX,
    required this.originY,
    required this.originZ,
    required this._vertices,
    required this._polygons,
    required this._neighbours,
    required this._areas,
    this.links = const <NavMeshLink>[],
  });

  /// What the mesh was baked to. Part of [digest].
  final NavMeshConfig config;

  /// The world position of lattice point `(0, 0, 0)`.
  final double originX;
  final double originY;
  final double originZ;

  final Int32List _vertices;
  final Int32List _polygons;
  final Int32List _neighbours;
  final Uint8List _areas;

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
  int neighbourAt(int polygon, int k) =>
      _neighbours[polygon * maxVerticesPerPolygon + k];

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
  List<int> polygonsAt(double x, double z) => <int>[
    for (var p = 0; p < polygonCount; p++)
      if (containsPoint(p, x, z)) p,
  ];

  /// The height of [polygon]'s surface over `(x, z)`, from the triangle of
  /// its fan that the point is over — a ramp's polygon is not flat, and its
  /// corners are the only heights the mesh has.
  ///
  /// A point outside the polygon in plan gets the height of the triangle
  /// nearest it, extended; [closestPointOn] keeps its points inside.
  double heightAt(int polygon, double x, double z) {
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
      ..add(_neighbours)
      ..add(_areas);
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
    NavMeshConfig config = const NavMeshConfig(),
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
    NavMeshConfig config = const NavMeshConfig(),
    int Function(Brush brush)? areaOf,
    int groundArea = NavArea.ground,
    JumpReach? jumps,
    double maxFall = 2.0,
  }) {
    final solid =
        SpanField.rasterise(
            brushes,
            config: config,
            ground: ground,
            areaOf: areaOf ?? (_) => NavArea.ground,
            groundArea: groundArea,
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

    final regions = monotoneRegions(open);
    final contours = buildContours(
      open,
      regions.region,
      maxError: config.maxEdgeError,
    );
    final parts = buildPolyMesh(
      contours,
      maxCorners: config.maxVerticesPerPolygon,
    );

    NavMesh mesh({List<NavMeshLink> links = const <NavMeshLink>[]}) =>
        NavMesh._(
          config: config,
          originX: solid.originX,
          originY: solid.originY,
          originZ: solid.originZ,
          vertices: parts.vertices,
          polygons: parts.polygons,
          neighbours: parts.neighbours,
          areas: parts.areas,
          links: links,
        );

    final walked = mesh();
    if (jumps == null) return walked;
    return mesh(
      links: List<NavMeshLink>.unmodifiable(
        bakeMeshLinks(
          open,
          solid,
          config: config,
          reach: jumps,
          maxFall: maxFall,
          polygonAt: walked.polygonAt,
        ),
      ),
    );
  }
}
