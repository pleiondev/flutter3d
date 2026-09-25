import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'occlusion_buffer.dart';
import 'occlusion_test.dart';

/// `OcclusionMode.hiZ`: last frame's depths, read back from the GPU and
/// reprojected into this frame's view — `C3`.
///
/// The `DepthPyramid` pass reduces the surface buffer to [width] × [height]
/// cells, each holding the *farthest* view depth under it and whether every
/// pixel under it was drawn at all; the renderer reads that back and hands it
/// to [accept] with the camera it was seen through. A frame later [prepare]
/// carries each cell to where this frame's camera sees it and writes it into
/// an [OcclusionBuffer], which then answers exactly as the software method's
/// does.
///
/// **Farthest, so the reading is only ever too pessimistic.** A cell's depth
/// is at or behind every surface in it, and the encoding rounds up, so a box
/// the reading hides is behind everything that was in the cell. A cell with
/// one empty pixel is no occluder at all: sky through a gap hides nothing.
///
/// **Moved as one plane, so only while it still is one.** A cell is carried
/// at its farthest depth, but what it saw may not have been flat: a post in
/// front of a doorway, the doorway's depth taken from the wall beside it.
/// Nobody saw what is behind the post, and when the camera steps sideways the
/// post slides off it faster than the wall does. The reading also keeps each
/// cell's nearest depth, and [prepare] leaves out a cell whose nearest and
/// farthest land more than [parallaxLimit] of a cell apart in the new view —
/// which a flat cell never does, and a still camera never makes any cell do.
/// And a pixel counts as covered only when the moved cells' union covers
/// all of it: two cells stacked over half a pixel are not one cell over the
/// whole of it.
///
/// What it cannot know is what moved since. A door that swung open last frame
/// still stands in the reading, so what is behind it waits a frame or two to
/// appear — the price of an answer that costs no occluders and no CPU
/// rasteriser, and the reason the answer is "visible" whenever the camera
/// jumps ([cutDistance], [cutCosine]) or the reading was taken through
/// another camera.
final class HiZOcclusion {
  /// The reading's size in cells, which is the `DepthPyramid` target's size.
  static const int width = 256;
  static const int height = 128;

  /// How far the eye may have moved since the reading, in metres, before the
  /// reading is thrown away as a cut rather than reprojected.
  static const double cutDistance = 2.0;

  /// The cosine of the widest turn since the reading that still reprojects:
  /// thirty degrees.
  static const double cutCosine = 0.8660254037844387;

  /// How far apart, in cells of this frame's view, a cell's nearest and
  /// farthest depths may land before the cell is no occluder: the widest
  /// sliver of what the reading never saw that it may still claim.
  static const double parallaxLimit = 0.25;

  /// The most moved cells one pixel keeps for its coverage test. A pixel
  /// more of them overlap — the camera backing away from a near wall — is
  /// left uncovered rather than tested.
  static const int _hitsPerPixel = 16;

  /// Steps in the 24-bit depth, which the pass writes as a fraction of the
  /// camera's far plane.
  static const int depthSteps = 0xFFFFFF;

  final OcclusionBuffer buffer = OcclusionBuffer(width: width, height: height);

  /// Each cell's depth in metres, NaN where it holds no occluder.
  final Float64List _cells = Float64List(width * height);

  /// Each cell's nearest depth in metres, at or in front of the nearest
  /// surface in it.
  final Float64List _nearCells = Float64List(width * height);

  /// For each cell corner, the reading's ray through it: its point on the
  /// near plane, its point on the far plane, and the view depth of each.
  final Float64List _rays = Float64List((width + 1) * (height + 1) * 8);

  final Vector3 _eye = Vector3.zero();
  final Vector3 _forward = Vector3.zero();
  Object? _camera;
  bool _hasReading = false;
  int _readings = 0;

  /// Whether a reading has arrived since the last [reset] — for a caller
  /// that wants to know whether culling is live yet or still drawing all.
  bool get hasReading => _hasReading;

  /// Readings accepted since this was made.
  int get readings => _readings;

  /// Forgets the reading, so every answer is "visible" until the next one.
  void reset() {
    _hasReading = false;
    _camera = null;
  }

  /// Takes a reading: [bytes] as the pass wrote them and `readback` returned
  /// them, row zero at the top, four bytes a cell — depth as a 24-bit
  /// fraction of [far] in red, green and blue, most significant first, and
  /// alpha below 128 where some pixel under the cell was not drawn, and
  /// otherwise 128 plus the nearest depth as 127ths of the farthest.
  ///
  /// [viewProjection] (engine `[0, 1]` depth), [eye] and [forward] are the
  /// view it was drawn through, and [camera] identifies it, so that a reading
  /// is never reprojected into a different camera's frame.
  void accept(
    ByteData bytes, {
    required Matrix4 viewProjection,
    required Vector3 eye,
    required Vector3 forward,
    required double far,
    required Object camera,
  }) {
    final inverse = Matrix4.zero();
    if (bytes.lengthInBytes < width * height * 4 ||
        inverse.copyInverse(viewProjection) == 0.0) {
      reset();
      return;
    }
    for (var i = 0; i < width * height; i++) {
      final o = i * 4;
      final alpha = bytes.getUint8(o + 3);
      if (alpha < 128) {
        _cells[i] = double.nan;
        continue;
      }
      final steps =
          bytes.getUint8(o) * 65536 +
          bytes.getUint8(o + 1) * 256 +
          bytes.getUint8(o + 2);
      final depth = steps / depthSteps * far;
      _cells[i] = depth;
      _nearCells[i] = (alpha - 128) / 127 * depth;
    }

    _eye.setFrom(eye);
    _forward.setFrom(forward);
    final m = inverse.storage;
    for (var y = 0; y <= height; y++) {
      final ndcY = 1.0 - y / height * 2.0;
      for (var x = 0; x <= width; x++) {
        final ndcX = x / width * 2.0 - 1.0;
        final base = (y * (width + 1) + x) * 8;
        for (var end = 0; end < 2; end++) {
          final ndcZ = end.toDouble();
          final w = m[3] * ndcX + m[7] * ndcY + m[11] * ndcZ + m[15];
          final px = (m[0] * ndcX + m[4] * ndcY + m[8] * ndcZ + m[12]) / w;
          final py = (m[1] * ndcX + m[5] * ndcY + m[9] * ndcZ + m[13]) / w;
          final pz = (m[2] * ndcX + m[6] * ndcY + m[10] * ndcZ + m[14]) / w;
          final at = base + end * 3;
          _rays[at] = px;
          _rays[at + 1] = py;
          _rays[at + 2] = pz;
          _rays[base + 6 + end] =
              (px - eye.x) * forward.x +
              (py - eye.y) * forward.y +
              (pz - eye.z) * forward.z;
        }
      }
    }
    _camera = camera;
    _hasReading = true;
    _readings++;
  }

  /// The reading carried into a frame seen through [viewProjection], or null
  /// when there is nothing to carry: no reading yet, a reading through
  /// another camera, or a cut since it was taken.
  OcclusionTest? prepare(
    Matrix4 viewProjection, {
    required Vector3 eye,
    required Vector3 forward,
    required Object camera,
  }) {
    if (!_hasReading || !identical(camera, _camera)) return null;
    if (eye.distanceTo(_eye) > cutDistance) return null;
    if (forward.dot(_forward) < cutCosine) return null;

    buffer.begin(viewProjection);
    final m = viewProjection.storage;
    final sx = Float64List(4), sy = Float64List(4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final cell = y * width + x;
        final depth = _cells[cell];
        if (depth.isNaN) continue;
        final near = _nearCells[cell];
        var far = -double.infinity;
        var usable = true;
        for (var k = 0; k < 4 && usable; k++) {
          final base = ((y + (k >> 1)) * (width + 1) + x + (k & 1)) * 8;
          final dn = _rays[base + 6], df = _rays[base + 7];
          if (df == dn) {
            usable = false;
            continue;
          }
          // Where along the reading's ray the view depth is the cell's
          // farthest, and where its nearest — no nearer than the near plane,
          // which every surface drawn is behind.
          final t = (depth - dn) / (df - dn);
          final tNear = math.max(0.0, (near - dn) / (df - dn));
          final p = _points;
          if (!_toScreen(m, base, t, 0) || !_toScreen(m, base, tNear, 3)) {
            usable = false;
            continue;
          }
          // The cell's nearest and farthest surfaces parted by more than
          // the limit: what was behind the nearer is out in the open by
          // that much, and the plane at the farthest would cover it.
          if ((p[3] - p[0]).abs() > parallaxLimit ||
              (p[4] - p[1]).abs() > parallaxLimit) {
            usable = false;
            continue;
          }
          sx[k] = p[0];
          sy[k] = p[1];
          if (p[2] > far) far = p[2];
        }
        if (!usable) continue;
        // The rectangle the moved cell still covers for certain: inside its
        // left corners' rightmost x and its right corners' leftmost, and the
        // same for rows. A cell that turned over or shrank to nothing covers
        // none.
        final left = math.max(sx[0], sx[2]), right = math.min(sx[1], sx[3]);
        final top = math.max(sy[0], sy[1]), bottom = math.min(sy[2], sy[3]);
        if (!(right > left) || !(bottom > top)) continue;
        final r = cell * 4;
        _rects
          ..[r] = left
          ..[r + 1] = right
          ..[r + 2] = top
          ..[r + 3] = bottom;
        // Handed to every pixel it overlaps. A camera that moved by part of
        // a cell leaves no pixel inside any one cell, so a pixel is covered
        // by its neighbours together; each pixel keeps the farthest depth
        // of whatever covered it.
        final x0 = math.max(0, left.floor());
        final x1 = math.min(width - 1, right.ceil() - 1);
        final y0 = math.max(0, top.floor());
        final y1 = math.min(height - 1, bottom.ceil() - 1);
        for (var py = y0; py <= y1; py++) {
          if (!(math.min(bottom, py + 1.0) > math.max(top, py.toDouble()))) {
            continue;
          }
          for (var px = x0; px <= x1; px++) {
            if (!(math.min(right, px + 1.0) > math.max(left, px.toDouble()))) {
              continue;
            }
            final index = py * width + px;
            if (far > _farthest[index]) _farthest[index] = far;
            final hits = _hitCount[index];
            if (left <= px &&
                right >= px + 1.0 &&
                top <= py &&
                bottom >= py + 1.0) {
              _hitCount[index] = _whole;
            } else if (hits < _hitsPerPixel) {
              _hits[index * _hitsPerPixel + hits] = cell;
              _hitCount[index] = hits + 1;
            } else if (hits == _hitsPerPixel) {
              _hitCount[index] = _overflow;
            }
          }
        }
      }
    }
    // Only a pixel the moved cells cover whole is an occluder: one with part
    // of it uncovered may be showing what the reading never saw — the
    // ground coming out from behind a wall the camera stepped past.
    for (var i = 0; i < width * height; i++) {
      final hits = _hitCount[i];
      final covered = switch (hits) {
        _whole => true,
        _overflow => false,
        _ =>
          hits > 0 && _covers(i % width, i ~/ width, i * _hitsPerPixel, hits),
      };
      if (covered) buffer.writeDepth(i % width, i ~/ width, _farthest[i]);
    }
    _hitCount.fillRange(0, _hitCount.length, 0);
    _farthest.fillRange(0, _farthest.length, -double.infinity);
    return buffer;
  }

  /// Puts where the point a fraction [t] of the way along the reading's
  /// corner ray at [base] lands in the frame [m] sees — its pixel x and y and
  /// its depth — into [_points] from [at]. False when it is at or behind the
  /// eye.
  bool _toScreen(Float32List m, int base, double t, int at) {
    final px = _rays[base] + (_rays[base + 3] - _rays[base]) * t;
    final py = _rays[base + 1] + (_rays[base + 4] - _rays[base + 1]) * t;
    final pz = _rays[base + 2] + (_rays[base + 5] - _rays[base + 2]) * t;
    final w = m[3] * px + m[7] * py + m[11] * pz + m[15];
    if (!(w > 1e-5)) return false;
    _points
      ..[at] =
          ((m[0] * px + m[4] * py + m[8] * pz + m[12]) / w * 0.5 + 0.5) * width
      ..[at + 1] =
          (0.5 - (m[1] * px + m[5] * py + m[9] * pz + m[13]) / w * 0.5) * height
      ..[at + 2] = (m[2] * px + m[6] * py + m[10] * pz + m[14]) / w;
    return true;
  }

  /// Whether the [count] moved cells listed from [first] in [_hits] cover
  /// pixel ([x], [y]) together, with no part of it left out.
  ///
  /// Their edges inside the pixel cut it into a grid of pieces, each of
  /// which is inside a cell or outside all of them, so testing one point of
  /// each piece is exact. Pieces thinner than a millionth of a pixel are
  /// the seams between cells that meet, and are let go.
  bool _covers(int x, int y, int first, int count) {
    final xs = _edgesX, ys = _edgesY;
    xs[0] = x.toDouble();
    ys[0] = y.toDouble();
    var nx = 1, ny = 1;
    for (var h = 0; h < count; h++) {
      final r = _hits[first + h] * 4;
      for (var e = 0; e < 2; e++) {
        final ex = _rects[r + e], ey = _rects[r + 2 + e];
        if (ex > x && ex < x + 1.0) xs[nx++] = ex;
        if (ey > y && ey < y + 1.0) ys[ny++] = ey;
      }
    }
    xs[nx++] = x + 1.0;
    ys[ny++] = y + 1.0;
    _sort(xs, nx);
    _sort(ys, ny);
    for (var j = 0; j + 1 < ny; j++) {
      if (ys[j + 1] - ys[j] < 1e-6) continue;
      final my = (ys[j] + ys[j + 1]) * 0.5;
      for (var i = 0; i + 1 < nx; i++) {
        if (xs[i + 1] - xs[i] < 1e-6) continue;
        final mx = (xs[i] + xs[i + 1]) * 0.5;
        var inside = false;
        for (var h = 0; h < count && !inside; h++) {
          final r = _hits[first + h] * 4;
          inside =
              _rects[r] < mx &&
              mx < _rects[r + 1] &&
              _rects[r + 2] < my &&
              my < _rects[r + 3];
        }
        if (!inside) return false;
      }
    }
    return true;
  }

  /// Sorts the first [n] of [values] in place: a handful, so by insertion.
  static void _sort(Float64List values, int n) {
    for (var i = 1; i < n; i++) {
      final v = values[i];
      var j = i - 1;
      for (; j >= 0 && values[j] > v; j--) {
        values[j + 1] = values[j];
      }
      values[j + 1] = v;
    }
  }

  /// [_hitCount] of a pixel one moved cell covers whole, which needs no
  /// further test, and of one more cells overlap than [_hits] keeps.
  static const int _whole = 255, _overflow = 254;

  /// Per pixel of [buffer] during [prepare]: how many moved cells overlap it
  /// (or [_whole] or [_overflow]), which ones, and the farthest depth among
  /// them.
  final Uint8List _hitCount = Uint8List(width * height);
  final Uint16List _hits = Uint16List(width * height * _hitsPerPixel);
  final Float64List _farthest = Float64List(width * height)
    ..fillRange(0, width * height, -double.infinity);

  /// Each moved cell's rectangle during [prepare]: left, right, top, bottom
  /// in pixels.
  final Float64List _rects = Float64List(width * height * 4);

  /// Scratch for [_toScreen]: a corner at the cell's farthest depth, then
  /// at its nearest.
  final Float64List _points = Float64List(6);

  /// Scratch for [_covers]: a pixel's edges and the cells' edges inside it.
  final Float64List _edgesX = Float64List(_hitsPerPixel * 2 + 2);
  final Float64List _edgesY = Float64List(_hitsPerPixel * 2 + 2);
}
