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

  /// Steps in the 24-bit depth, which the pass writes as a fraction of the
  /// camera's far plane.
  static const int depthSteps = 0xFFFFFF;

  final OcclusionBuffer buffer = OcclusionBuffer(width: width, height: height);

  /// Each cell's depth in metres, NaN where it holds no occluder.
  final Float64List _cells = Float64List(width * height);

  /// For each cell corner, the reading's ray through it: its point on the
  /// near plane, its point on the far plane, and the view depth of each.
  final Float64List _rays = Float64List((width + 1) * (height + 1) * 8);

  final Vector3 _eye = Vector3.zero();
  final Vector3 _forward = Vector3.zero();
  Object? _camera;
  bool _hasReading = false;
  int _readings = 0;

  /// Whether a reading has arrived since the last [reset].
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
  /// alpha at one where every pixel under the cell was drawn.
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
      if (bytes.getUint8(o + 3) < 128) {
        _cells[i] = double.nan;
        continue;
      }
      final steps =
          bytes.getUint8(o) * 65536 +
          bytes.getUint8(o + 1) * 256 +
          bytes.getUint8(o + 2);
      _cells[i] = steps / depthSteps * far;
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
        final depth = _cells[y * width + x];
        if (depth.isNaN) continue;
        var far = -double.infinity;
        var usable = true;
        for (var k = 0; k < 4 && usable; k++) {
          final base = ((y + (k >> 1)) * (width + 1) + x + (k & 1)) * 8;
          final dn = _rays[base + 6], df = _rays[base + 7];
          if (df == dn) {
            usable = false;
            continue;
          }
          // Where along the reading's ray the view depth is the cell's.
          final t = (depth - dn) / (df - dn);
          final px = _rays[base] + (_rays[base + 3] - _rays[base]) * t;
          final py = _rays[base + 1] + (_rays[base + 4] - _rays[base + 1]) * t;
          final pz = _rays[base + 2] + (_rays[base + 5] - _rays[base + 2]) * t;
          final w = m[3] * px + m[7] * py + m[11] * pz + m[15];
          if (!(w > 1e-5)) {
            usable = false;
            continue;
          }
          sx[k] =
              ((m[0] * px + m[4] * py + m[8] * pz + m[12]) / w * 0.5 + 0.5) *
              width;
          sy[k] =
              (0.5 - (m[1] * px + m[5] * py + m[9] * pz + m[13]) / w * 0.5) *
              height;
          final sz = (m[2] * px + m[6] * py + m[10] * pz + m[14]) / w;
          if (sz > far) far = sz;
        }
        if (!usable) continue;
        // The rectangle the moved cell still covers for certain: inside its
        // left corners' rightmost x and its right corners' leftmost, and the
        // same for rows. A cell that turned over or shrank to nothing covers
        // none.
        final left = math.max(sx[0], sx[2]), right = math.min(sx[1], sx[3]);
        final top = math.max(sy[0], sy[1]), bottom = math.min(sy[2], sy[3]);
        if (!(right > left) || !(bottom > top)) continue;
        // Shared out over the pixels it overlaps, by area. A camera that
        // moved by part of a cell leaves no pixel inside any one cell, so
        // coverage is summed across neighbours; each pixel keeps the
        // farthest depth of whatever covered it.
        final x0 = math.max(0, left.floor());
        final x1 = math.min(width - 1, right.ceil() - 1);
        final y0 = math.max(0, top.floor());
        final y1 = math.min(height - 1, bottom.ceil() - 1);
        for (var py = y0; py <= y1; py++) {
          final rows =
              math.min(bottom, py + 1.0) - math.max(top, py.toDouble());
          if (rows <= 0.0) continue;
          for (var px = x0; px <= x1; px++) {
            final columns =
                math.min(right, px + 1.0) - math.max(left, px.toDouble());
            if (columns <= 0.0) continue;
            final index = py * width + px;
            _covered[index] += rows * columns;
            if (far > _farthest[index]) _farthest[index] = far;
          }
        }
      }
    }
    // Only a pixel the moved cells cover whole is an occluder: one with part
    // of it uncovered may be showing what the reading never saw — the
    // ground coming out from behind a wall the camera stepped past.
    for (var i = 0; i < width * height; i++) {
      if (_covered[i] >= 1.0 - 1e-6) {
        buffer.writeDepth(i % width, i ~/ width, _farthest[i]);
      }
    }
    _covered.fillRange(0, _covered.length, 0.0);
    _farthest.fillRange(0, _farthest.length, -double.infinity);
    return buffer;
  }

  /// Per pixel of [buffer] during [prepare]: how much of it the moved cells
  /// cover, and the farthest depth among them.
  final Float64List _covered = Float64List(width * height);
  final Float64List _farthest = Float64List(width * height)
    ..fillRange(0, width * height, -double.infinity);
}
