import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import 'occlusion_test.dart';

/// A small depth-only rasteriser the scene pass culls against — `C2`.
///
/// **The engine's own, on the CPU, and small on purpose.** A 256 × 128 grid of
/// depths is a few hundred occluder triangles' work in a frame and answers a
/// box test in a handful of reads, which is the whole budget an occlusion
/// method has: it earns its place only if what it skips costs more than what
/// it spends. It has to live here rather than borrow `flutter3d_cpu`'s
/// rasteriser, because `flutter3d_core` cannot depend on a backend — so the
/// near clip and the edge functions are the same ones that backend uses,
/// written again for depth alone.
///
/// Depth is the engine's own window depth, `[0, 1]` from the near plane to the
/// far one ([Projection]'s convention), nearer is smaller, and an empty pixel
/// holds infinity: nothing was drawn there, so nothing behind it is hidden.
///
/// **Conservative, which is the one property it cannot trade away.** A false
/// "hidden" is a hole in the picture; a false "visible" is only a draw that
/// was not saved. So an occluder writes a pixel only where it covers all four
/// of the pixel's corners, and writes the *farthest* of the four depths — the
/// pixel's whole square is then behind at most that. Corners rather than the
/// pixel's centre, and per mesh rather than per triangle, so that the two
/// triangles of a wall cover the diagonal between them: a pixel the diagonal
/// crosses has two corners in each and would be left empty by either alone,
/// and a wall with a stripe of holes through it hides little.
///
/// Tiles of 8 × 8 keep the farthest depth under them, so a box behind a
/// whole tile is rejected in one comparison rather than sixty-four.
final class OcclusionBuffer implements OcclusionTest {
  OcclusionBuffer({this.width = defaultWidth, this.height = defaultHeight})
    : assert(
        width % tileSize == 0 && height % tileSize == 0,
        'the grid is whole tiles',
      ),
      _depth = Float64List(width * height),
      _tileMax = Float64List((width ~/ tileSize) * (height ~/ tileSize)),
      _corners = Float64List((width + 1) * (height + 1)) {
    _corners.fillRange(0, _corners.length, double.infinity);
    _depth.fillRange(0, _depth.length, double.infinity);
    _tileMax.fillRange(0, _tileMax.length, double.infinity);
  }

  static const int defaultWidth = 256;
  static const int defaultHeight = 128;

  /// The side of a tile, in pixels.
  static const int tileSize = 8;

  /// How far behind an occluder a box has to be before it counts as hidden,
  /// in window depth. The slack is for a surface lying *on* its own box —
  /// a wall's face is its box's face — whose depth and whose box's nearest
  /// corner are the same number reached by two different sums.
  static const double depthTolerance = 1e-6;

  /// The smallest `w` a vertex may have and still be divided by: the same
  /// plane the software backend clips at.
  static const double _nearW = 1e-5;

  final int width;
  final int height;

  final Float64List _depth;
  final Float64List _tileMax;

  /// Per-mesh scratch: the nearest depth of the mesh at each pixel corner,
  /// infinity where the mesh does not reach. Cleared behind every mesh over
  /// the rectangle it touched.
  final Float64List _corners;

  final Matrix4 _viewProjection = Matrix4.identity();
  final Matrix4 _clipFromLocal = Matrix4.zero();
  Float64List _clip = Float64List(0);

  /// One triangle before the near clip and the polygon after it: up to four
  /// corners of x, y, z, w.
  final Float64List _polygon = Float64List(16);

  bool _tilesStale = false;
  int _triangles = 0;

  // The corner rectangle the current mesh touched, inclusive.
  int _rx0 = 0, _ry0 = 0, _rx1 = -1, _ry1 = -1;

  /// Triangles drawn since [begin], counting each before its clip.
  int get triangles => _triangles;

  /// The matrix [begin] was given.
  Matrix4 get viewProjection => _viewProjection;

  /// Empties the grid for a frame seen through [viewProjection], in the
  /// engine's `[0, 1]` depth convention.
  void begin(Matrix4 viewProjection) {
    _viewProjection.setFrom(viewProjection);
    _depth.fillRange(0, _depth.length, double.infinity);
    _tileMax.fillRange(0, _tileMax.length, double.infinity);
    _tilesStale = false;
    _triangles = 0;
  }

  /// The depth held at pixel ([x], [y]), row zero at the top; infinity where
  /// nothing was drawn.
  double depthAt(int x, int y) => _depth[y * width + x];

  /// Pulls pixel ([x], [y]) to [depth] if that is nearer than what it holds.
  /// For an occluder that arrives as depths rather than as triangles — the
  /// reprojected readback `C3` fills this with.
  void writeDepth(int x, int y, double depth) {
    final index = y * width + x;
    if (depth < _depth[index]) {
      _depth[index] = depth;
      _tilesStale = true;
    }
  }

  /// Rasterises [mesh] placed by [world]. Returns the triangles drawn.
  ///
  /// [cullBackFaces] follows the material: a single-sided wall seen from
  /// behind is not drawn by the scene pass, so it hides nothing either.
  int draw(MeshData mesh, Matrix4 world, {bool cullBackFaces = true}) {
    final layout = mesh.layout;
    final offset = layout.floatOffsetOf('position');
    if (offset < 0) return 0;
    final stride = layout.floatsPerVertex;
    final count = mesh.vertexCount;
    final vertices = mesh.vertices;

    _clipFromLocal
      ..setFrom(_viewProjection)
      ..multiply(world);
    if (_clip.length < count * 4) _clip = Float64List(count * 4);
    final m = _clipFromLocal.storage;
    for (var v = 0; v < count; v++) {
      final at = v * stride + offset;
      final x = vertices[at], y = vertices[at + 1], z = vertices[at + 2];
      for (var k = 0; k < 4; k++) {
        _clip[v * 4 + k] = m[k] * x + m[4 + k] * y + m[8 + k] * z + m[12 + k];
      }
    }

    // A mirroring transform turns every triangle over on screen; the scene
    // pass flips its winding for the same node for the same reason.
    final mirrored = world.determinant() < 0.0;
    final indices = mesh.indices;
    _rx0 = width + 1;
    _ry0 = height + 1;
    _rx1 = -1;
    _ry1 = -1;
    for (var i = 0; i + 2 < indices.length; i += 3) {
      _triangle(
        indices[i],
        indices[i + 1],
        indices[i + 2],
        cullBackFaces,
        mirrored,
      );
    }
    _resolveMesh();
    final drawn = indices.length ~/ 3;
    _triangles += drawn;
    return drawn;
  }

  /// Clips one triangle against the near plane and rasterises what is left.
  ///
  /// Sutherland-Hodgman against `w = _nearW`, as the software backend does and
  /// for its reason: every other plane only wastes corners the bounding box
  /// rejects anyway, while this one divides by a number at or below zero.
  void _triangle(int a, int b, int c, bool cull, bool mirrored) {
    final wa = _clip[a * 4 + 3], wb = _clip[b * 4 + 3], wc = _clip[c * 4 + 3];
    final behind =
        (wa <= _nearW ? 1 : 0) +
        (wb <= _nearW ? 1 : 0) +
        (wc <= _nearW ? 1 : 0);
    if (behind == 3) return;
    if (behind == 0) {
      _raster(a * 4, b * 4, c * 4, _clip, cull, mirrored);
      return;
    }
    var n = 0;
    final corners = <int>[a * 4, b * 4, c * 4];
    for (var i = 0; i < 3; i++) {
      final p = corners[i], q = corners[(i + 1) % 3];
      final pw = _clip[p + 3], qw = _clip[q + 3];
      final pIn = pw > _nearW, qIn = qw > _nearW;
      if (pIn) {
        for (var k = 0; k < 4; k++) {
          _polygon[n * 4 + k] = _clip[p + k];
        }
        n++;
      }
      if (pIn != qIn) {
        final t = (_nearW - pw) / (qw - pw);
        for (var k = 0; k < 3; k++) {
          _polygon[n * 4 + k] =
              _clip[p + k] + (_clip[q + k] - _clip[p + k]) * t;
        }
        // On the plane by construction; said rather than trusted, for the
        // reason `CpuEncoder._rasterise` gives.
        _polygon[n * 4 + 3] = _nearW;
        n++;
      }
    }
    for (var i = 1; i + 1 < n; i++) {
      _raster(0, i * 4, (i + 1) * 4, _polygon, cull, mirrored);
    }
  }

  /// Writes one triangle, already in front of the near plane, into the corner
  /// scratch: every corner inside it or on its edge takes the nearer of what
  /// it held and the triangle's depth there.
  void _raster(
    int p0,
    int p1,
    int p2,
    Float64List v,
    bool cull,
    bool mirrored,
  ) {
    double sx(int p) => (v[p] / v[p + 3] * 0.5 + 0.5) * width;
    double sy(int p) => (0.5 - v[p + 1] / v[p + 3] * 0.5) * height;
    double sz(int p) => v[p + 2] / v[p + 3];

    final signed =
        (sx(p1) - sx(p0)) * (sy(p2) - sy(p0)) -
        (sx(p2) - sx(p0)) * (sy(p1) - sy(p0));
    if (signed == 0.0 || !signed.isFinite) return;
    // Window space runs y down, so a counter-clockwise front face — the
    // engine's — has a negative area here.
    final front = mirrored ? signed > 0.0 : signed < 0.0;
    if (cull && !front) return;
    // Wound so the interior is where every edge function is positive.
    final (q1, q2) = signed < 0.0 ? (p2, p1) : (p1, p2);
    final area = signed.abs();
    final x0 = sx(p0), y0 = sy(p0), z0 = sz(p0);
    final x1 = sx(q1), y1 = sy(q1), z1 = sz(q1);
    final x2 = sx(q2), y2 = sy(q2), z2 = sz(q2);

    final cx0 = math.max(0, math.min(x0, math.min(x1, x2)).ceil());
    final cx1 = math.min(width, math.max(x0, math.max(x1, x2)).floor());
    final cy0 = math.max(0, math.min(y0, math.min(y1, y2)).ceil());
    final cy1 = math.min(height, math.max(y0, math.max(y1, y2)).floor());
    if (cx0 > cx1 || cy0 > cy1) return;

    // Inclusive of the edge, and a hair past it: a corner on the diagonal
    // two triangles share has to land in at least one of them, and the two
    // sums that decide it round independently.
    final slack = -1e-9 * area;
    final inverse = 1.0 / area;
    for (var y = cy0; y <= cy1; y++) {
      final py = y.toDouble();
      for (var x = cx0; x <= cx1; x++) {
        final px = x.toDouble();
        final e12 = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1);
        if (e12 < slack) continue;
        final e20 = (x0 - x2) * (py - y2) - (y0 - y2) * (px - x2);
        if (e20 < slack) continue;
        final e01 = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0);
        if (e01 < slack) continue;
        // Window depth is linear in window space, so the barycentric blend
        // of the three is exact.
        final z = (e12 * z0 + e20 * z1 + e01 * z2) * inverse;
        final index = y * (width + 1) + x;
        if (z < _corners[index]) _corners[index] = z;
      }
    }
    if (cx0 < _rx0) _rx0 = cx0;
    if (cy0 < _ry0) _ry0 = cy0;
    if (cx1 > _rx1) _rx1 = cx1;
    if (cy1 > _ry1) _ry1 = cy1;
  }

  /// Turns the current mesh's corners into pixels and clears them.
  void _resolveMesh() {
    if (_rx1 < _rx0 || _ry1 < _ry0) return;
    final stride = width + 1;
    for (var y = _ry0; y < _ry1; y++) {
      for (var x = _rx0; x < _rx1; x++) {
        final c = y * stride + x;
        final a = _corners[c], b = _corners[c + 1];
        final d = _corners[c + stride], e = _corners[c + stride + 1];
        // Infinity in any corner is a corner the mesh missed, and the max
        // below is then infinity: nothing is written.
        final far = math.max(math.max(a, b), math.max(d, e));
        if (far == double.infinity) continue;
        final index = y * width + x;
        if (far < _depth[index]) {
          _depth[index] = far;
          _tilesStale = true;
        }
      }
    }
    for (var y = _ry0; y <= _ry1; y++) {
      _corners.fillRange(
        y * stride + _rx0,
        y * stride + _rx1 + 1,
        double.infinity,
      );
    }
  }

  void _refreshTiles() {
    final tilesX = width ~/ tileSize;
    for (var t = 0; t < _tileMax.length; t++) {
      final left = (t % tilesX) * tileSize, top = (t ~/ tilesX) * tileSize;
      var far = -double.infinity;
      for (var y = top; y < top + tileSize; y++) {
        for (var x = left; x < left + tileSize; x++) {
          final d = _depth[y * width + x];
          if (d > far) far = d;
        }
      }
      _tileMax[t] = far;
    }
    _tilesStale = false;
  }

  /// Whether [box] reaches in front of the grid anywhere it covers.
  ///
  /// The box's eight corners give a rectangle and the nearest depth any
  /// part of it can have; it is hidden only if every pixel of that
  /// rectangle holds something nearer still. A corner at or behind the eye
  /// makes the rectangle meaningless and the answer is yes.
  @override
  bool mayBeVisible(Aabb3 box) {
    final m = _viewProjection.storage;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    var nearest = double.infinity;
    for (var i = 0; i < 8; i++) {
      final x = (i & 1) == 0 ? box.min.x : box.max.x;
      final y = (i & 2) == 0 ? box.min.y : box.max.y;
      final z = (i & 4) == 0 ? box.min.z : box.max.z;
      final w = m[3] * x + m[7] * y + m[11] * z + m[15];
      if (!(w > _nearW)) return true;
      final sx =
          ((m[0] * x + m[4] * y + m[8] * z + m[12]) / w * 0.5 + 0.5) * width;
      final sy =
          (0.5 - (m[1] * x + m[5] * y + m[9] * z + m[13]) / w * 0.5) * height;
      final sz = (m[2] * x + m[6] * y + m[10] * z + m[14]) / w;
      if (sx < minX) minX = sx;
      if (sx > maxX) maxX = sx;
      if (sy < minY) minY = sy;
      if (sy > maxY) maxY = sy;
      if (sz < nearest) nearest = sz;
    }
    if (!nearest.isFinite || !minX.isFinite || !maxX.isFinite) return true;
    if (!minY.isFinite || !maxY.isFinite) return true;

    // Every pixel the rectangle touches, however little: pixel `i` spans
    // `[i, i + 1)`, and a sliver of box in it is a sliver the GPU may draw.
    final x0 = math.max(0, minX.floor());
    final x1 = math.min(width - 1, maxX.ceil() - 1);
    final y0 = math.max(0, minY.floor());
    final y1 = math.min(height - 1, maxY.ceil() - 1);
    // Off the grid, or thinner than a pixel on it: the grid has nothing to
    // say, and nothing to say is "visible".
    if (x0 > x1 || y0 > y1) return true;

    if (_tilesStale) _refreshTiles();
    final limit = nearest - depthTolerance;
    final tilesX = width ~/ tileSize;
    for (var ty = y0 ~/ tileSize; ty <= y1 ~/ tileSize; ty++) {
      for (var tx = x0 ~/ tileSize; tx <= x1 ~/ tileSize; tx++) {
        // The whole tile is nearer than the box: nothing under it can show.
        if (limit > _tileMax[ty * tilesX + tx]) continue;
        final top = math.max(y0, ty * tileSize);
        final bottom = math.min(y1, ty * tileSize + tileSize - 1);
        final left = math.max(x0, tx * tileSize);
        final right = math.min(x1, tx * tileSize + tileSize - 1);
        for (var y = top; y <= bottom; y++) {
          for (var x = left; x <= right; x++) {
            if (!(limit > _depth[y * width + x])) return true;
          }
        }
      }
    }
    return false;
  }
}
