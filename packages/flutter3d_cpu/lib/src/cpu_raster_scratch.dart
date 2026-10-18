/// The lists a draw and a triangle work in, kept by the device rather than
/// made for each.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// What `CpuEncoder` rasterises in: one set per device, for its life.
///
/// **Why it exists: a draw allocated its working lists, and a triangle its
/// own.** Every draw made three varying lists, an attribute list and three
/// clip positions; every triangle four lists of window coordinates and a
/// list to interpolate into, and two more for the derivatives when a mipped
/// texture was bound. A frame of a few hundred draws and tens of thousands of
/// triangles made as many lists, each garbage when its triangle was done.
/// The three GPU backends fill their uniform blocks in a kept buffer for the
/// same reason (`UniformScratch`); this is the rasteriser's share.
///
/// **What a caller promises.** A list answered here is valid until the next
/// call for the same thing, and this backend draws on the calling thread with
/// no draw inside another, so one set serves every pass of the device. Each
/// list starts the way a fresh one did where its reader depends on it: the
/// per-draw ones are zeroed at the draw's start, and the per-triangle ones
/// are written whole before they are read.
final class CpuRasterScratch {
  /// An empty set; each size is made the first time it is asked for.
  CpuRasterScratch();

  /// A draw's three clip positions, one a corner, overwritten by the vertex
  /// stage before they are read.
  final List<Vector4> clip = <Vector4>[
    Vector4.zero(),
    Vector4.zero(),
    Vector4.zero(),
  ];

  final Map<int, List<Float32List>> _varyings = <int, List<Float32List>>{};
  final Map<int, Float32List> _attributes = <int, Float32List>{};
  final Map<int, Float32List> _interpolated = <int, Float32List>{};
  final Map<int, (Float32List, Float32List)> _derivatives =
      <int, (Float32List, Float32List)>{};

  /// A triangle's window x, y and depth and its `1/w`, one a corner. Wide
  /// enough for a line's two.
  final Float64List sx = Float64List(3);

  /// Each corner's window y, in pixels down from the top.
  final Float64List sy = Float64List(3);

  /// Each corner's window depth, as the viewport maps it.
  final Float64List sz = Float64List(3);

  /// Each corner's `1/w`, which perspective-correct interpolation divides by.
  final Float64List invW = Float64List(3);

  /// Three lists of [count] varyings, one a corner, all zero: what a draw's
  /// vertex stage writes into. The rasteriser may reorder the three.
  List<Float32List> varyingsFor(int count) {
    final corners = _varyings[count] ??= <Float32List>[
      Float32List(count),
      Float32List(count),
      Float32List(count),
    ];
    for (final corner in corners) {
      corner.fillRange(0, count, 0);
    }
    return corners;
  }

  /// [stride] floats, all zero: one vertex's attributes as a draw fetches
  /// them.
  Float32List attributesFor(int stride) {
    final list = _attributes[stride] ??= Float32List(stride);
    return list..fillRange(0, stride, 0);
  }

  /// [count] floats to interpolate a fragment's varyings into, written whole
  /// at every fragment before the stage reads them.
  Float32List interpolatedFor(int count) =>
      _interpolated[count] ??= Float32List(count);

  /// Two lists of [count] floats for a triangle's screen-space derivatives,
  /// written whole before they are read.
  (Float32List, Float32List) derivativesFor(int count) =>
      _derivatives[count] ??= (Float32List(count), Float32List(count));
}
