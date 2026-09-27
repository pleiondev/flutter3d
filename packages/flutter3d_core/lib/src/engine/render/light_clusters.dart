/// Which of the frame's lights reach each cell of the view — `L6`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/light_buffer.dart';

/// The view cut into 16 × 9 tiles across and 24 slices deep, each cell with
/// the list of lights whose range reaches into it.
///
/// **What it replaces.** A draw hands the shader eight slots and a tail of
/// twenty-four rows, all ranked against the draw's bounding sphere. For a
/// ground plane that sphere touches every torch on the map, so the list is
/// the thirty-two brightest anywhere and the far half of the floor is lit by
/// the wrong ones. A cell is a few metres of the view, so its list is the
/// lights that actually reach that part of it, whatever draws it.
///
/// **Slices by the clip w, logarithmic.** The w row of the matrix is linear
/// in the world position, so the w range of a light's sphere is its centre's
/// w plus and minus the range times the length of that row: exact, with no
/// special case per projection. For a perspective camera w is the distance
/// along the view axis; for an orthographic one it is one everywhere, and the
/// grid degenerates to its tiles, which is still right, only coarser.
///
/// **Conservative, and never more than that.** A light is entered in every
/// cell of the box its sphere's projection covers, tiles by the eight corners
/// of the sphere's box and slices by the w range. A light too near the eye
/// plane for its corners to project covers every tile. A cell may list a
/// light that misses it by a corner; the attenuation reaches nought at the
/// range, so an extra entry costs a loop iteration and no pixel.
///
/// Directional lights are not entered: they have no range to place, and the
/// per-draw slots take them first.
final class LightClusters {
  static const int tilesX = 16;
  static const int tilesY = 9;
  static const int slices = 24;
  static const int count = tilesX * tilesY * slices;

  /// Floats in one texel and one row of the light list texture.
  static const int _texel = 4;
  static const int _row = 16;

  /// Clusters, then index entries, per row of the texture: one texel a
  /// cluster's header, one float an entry.
  static const int headersPerRow = _row ~/ _texel;
  static const int entriesPerRow = _row;

  final Int32List _counts = Int32List(count);
  final Int32List _offsets = Int32List(count);
  Int32List _entries = Int32List(256);
  Int32List _boxes = Int32List(6 * 16);
  int _total = 0;

  /// The view-projection the cells were cut with, for the shader to cut the
  /// same way.
  final Matrix4 viewProjection = Matrix4.identity();

  /// Where slices begin, and slices per unit of `ln(w / near)`.
  double near = 0.1;
  double sliceScale = 1.0;

  /// Entries across every cell; what the index rows hold.
  int get total => _total;

  /// Rows of the light list texture the headers take.
  static int get headerRows => (count + headersPerRow - 1) ~/ headersPerRow;

  /// Rows the index list takes.
  int get entryRows =>
      math.max((_total + entriesPerRow - 1) ~/ entriesPerRow, 1);

  /// How many lights [cluster] holds — for a profiler or a debugger
  /// overlay that shows where the cells are crowded.
  int countAt(int cluster) => _counts[cluster];

  /// The lights of [cluster], as candidate indices of the table it was built
  /// from, in scene order.
  Iterable<int> lightsAt(int cluster) sync* {
    final offset = _offsets[cluster];
    for (var i = 0; i < _counts[cluster]; i++) {
      yield _entries[offset + i];
    }
  }

  /// Which cell [world] falls in, as the shader finds it.
  int clusterOf(Vector3 world) {
    final s = viewProjection.storage;
    final x = s[0] * world.x + s[4] * world.y + s[8] * world.z + s[12];
    final y = s[1] * world.x + s[5] * world.y + s[9] * world.z + s[13];
    final w = s[3] * world.x + s[7] * world.y + s[11] * world.z + s[15];
    final inv = 1.0 / math.max(w, 1e-6);
    final tx = _tile(x * inv, tilesX);
    final ty = _tile(y * inv, tilesY);
    return tx + ty * tilesX + _slice(w) * tilesX * tilesY;
  }

  /// Cuts the view [viewProjection] into cells, between [near] and [far], and
  /// enters [table]'s candidates into the ones they reach.
  void build(
    LightBuffer table,
    Matrix4 viewProjection, {
    required double near,
    required double far,
  }) {
    this.viewProjection.setFrom(viewProjection);
    this.near = math.max(near, 1e-4);
    sliceScale =
        slices /
        math.max(math.log(math.max(far, this.near * 1.01) / this.near), 1e-6);

    final data = table.candidateData;
    final lights = table.candidates.length;
    if (_boxes.length < lights * 6) _boxes = Int32List(lights * 6);
    _counts.fillRange(0, count, 0);

    // First the box each light covers, counting as it goes; then offsets;
    // then the entries, in scene order within each cell.
    for (var i = 0; i < lights; i++) {
      final at = i * LightBuffer.candidateStride;
      final box = i * 6;
      if (data[at + 5] > 0.5 || !_boxOf(data, at, box)) {
        _boxes[box] = 1;
        _boxes[box + 1] = 0;
        continue;
      }
      _visit(box, (cluster) => _counts[cluster]++);
    }
    var running = 0;
    for (var c = 0; c < count; c++) {
      _offsets[c] = running;
      running += _counts[c];
    }
    _total = running;
    if (_entries.length < running) _entries = Int32List(running);
    final cursor = Int32List.fromList(_offsets);
    for (var i = 0; i < lights; i++) {
      _visit(i * 6, (cluster) => _entries[cursor[cluster]++] = i);
    }
  }

  /// Writes the headers and then the entries into [out] at [at], sixteen
  /// floats a row, as `surface.glsl` reads them after the light rows.
  void write(Float32List out, int at) {
    for (var c = 0; c < count; c++) {
      final o = at + c * _texel;
      out[o] = _offsets[c].toDouble();
      out[o + 1] = _counts[c].toDouble();
      out[o + 2] = 0.0;
      out[o + 3] = 0.0;
    }
    final entries = at + headerRows * _row;
    for (var i = 0; i < entryRows * entriesPerRow; i++) {
      out[entries + i] = i < _total ? _entries[i].toDouble() : 0.0;
    }
  }

  /// Floats [write] fills.
  int get floats => (headerRows + entryRows) * _row;

  void _visit(int box, void Function(int cluster) enter) {
    final x0 = _boxes[box], x1 = _boxes[box + 1];
    final y0 = _boxes[box + 2], y1 = _boxes[box + 3];
    final z0 = _boxes[box + 4], z1 = _boxes[box + 5];
    for (var z = z0; z <= z1; z++) {
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          enter(x + y * tilesX + z * tilesX * tilesY);
        }
      }
    }
  }

  /// The tiles and slices light [at] covers, into [_boxes] at [box]; false
  /// when it reaches no part of the view.
  bool _boxOf(Float32List data, int at, int box) {
    final s = viewProjection.storage;
    final px = data[at], py = data[at + 1], pz = data[at + 2];
    final range = data[at + 3];

    // No range is no limit: every cell.
    if (range <= 0.0) {
      _setBox(box, 0, tilesX - 1, 0, tilesY - 1, 0, slices - 1);
      return true;
    }

    final wRow = math.sqrt(s[3] * s[3] + s[7] * s[7] + s[11] * s[11]);
    final wCentre = s[3] * px + s[7] * py + s[11] * pz + s[15];
    final wNear = wCentre - range * wRow;
    final wFar = wCentre + range * wRow;
    if (wFar <= 0.0) return false;
    final z0 = _slice(wNear);
    final z1 = _slice(wFar);

    // Too close to the eye plane for the corners to project: every tile.
    if (wNear <= 1e-4) {
      _setBox(box, 0, tilesX - 1, 0, tilesY - 1, z0, z1);
      return true;
    }
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (var corner = 0; corner < 8; corner++) {
      final cx = px + ((corner & 1) == 0 ? -range : range);
      final cy = py + ((corner & 2) == 0 ? -range : range);
      final cz = pz + ((corner & 4) == 0 ? -range : range);
      final w = s[3] * cx + s[7] * cy + s[11] * cz + s[15];
      if (w <= 1e-4) {
        _setBox(box, 0, tilesX - 1, 0, tilesY - 1, z0, z1);
        return true;
      }
      final x = (s[0] * cx + s[4] * cy + s[8] * cz + s[12]) / w;
      final y = (s[1] * cx + s[5] * cy + s[9] * cz + s[13]) / w;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    if (maxX < -1.0 || minX > 1.0 || maxY < -1.0 || minY > 1.0) return false;
    _setBox(
      box,
      _tile(minX, tilesX),
      _tile(maxX, tilesX),
      _tile(minY, tilesY),
      _tile(maxY, tilesY),
      z0,
      z1,
    );
    return true;
  }

  void _setBox(int box, int x0, int x1, int y0, int y1, int z0, int z1) {
    _boxes[box] = x0;
    _boxes[box + 1] = x1;
    _boxes[box + 2] = y0;
    _boxes[box + 3] = y1;
    _boxes[box + 4] = z0;
    _boxes[box + 5] = z1;
  }

  static int _tile(double ndc, int tiles) =>
      ((ndc * 0.5 + 0.5) * tiles).floor().clamp(0, tiles - 1);

  int _slice(double w) => w <= near
      ? 0
      : (math.log(w / near) * sliceScale).floor().clamp(0, slices - 1);
}
