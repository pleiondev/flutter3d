/// How one vertex's attributes are collected before a stage sees them.
///
/// Two implementations, and the split is the whole of this backend's support
/// for instancing. A vertex stage here receives one `Float32List` and reads it
/// by position — that never changes. What changes is where those floats came
/// from.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

abstract interface class VertexFetch {
  /// How many floats one vertex amounts to.
  int get floatsPerVertex;

  /// Fills [out] for [vertex], or answers false when a buffer is too short.
  ///
  /// False rather than a throw because a short buffer is a caller's arithmetic
  /// mistake that this backend has always answered by drawing nothing, and
  /// changing that here would turn a blank scene into a crash in the middle of
  /// a golden run.
  bool into(Float32List out, int vertex);
}

/// One interleaved buffer, in the order the shader declares its inputs.
///
/// Every draw this engine made before instancing, and every draw it still makes
/// except the instanced ones. The layout is not described anywhere: it is the
/// shader's `in` order, which is the same contract flutter_gpu works from.
final class PackedFetch implements VertexFetch {
  PackedFetch(ByteData bytes, this.floatsPerVertex)
    : _floats = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );

  final Float32List _floats;

  @override
  final int floatsPerVertex;

  @override
  bool into(Float32List out, int vertex) {
    final base = vertex * floatsPerVertex;
    if (base + floatsPerVertex > _floats.length) return false;
    for (var f = 0; f < floatsPerVertex; f++) {
      out[f] = _floats[base + f];
    }
    return true;
  }
}

/// Several buffers, some stepping per vertex and some per instance.
///
/// **The assembled order is the layout's order** — every attribute of slot 0,
/// then every attribute of slot 1, and so on — and the vertex stage must
/// declare its inputs to match. That is the same kind of contract the packed
/// path already lives under, where the order is the shader's own; it is written
/// down here because with two buffers there is no single obvious order to fall
/// back on, and a stage that disagreed would read a position as a colour and
/// draw something rather than failing.
final class LayoutFetch implements VertexFetch {
  LayoutFetch._(
    this._views,
    this._strides,
    this._element,
    this._offsets,
    this._counts,
    this.floatsPerVertex,
  );

  /// Resolves [layout] against the bound buffers for one instance.
  ///
  /// Built per draw rather than per vertex: the arithmetic below depends only
  /// on the layout and the instance, and doing it three times per triangle was
  /// measurably the wrong shape when the same mistake was made in the packed
  /// path's ancestor.
  factory LayoutFetch.build(
    VertexLayoutSpec layout,
    ByteData slotZero,
    Map<int, ByteData>? slots,
    int instance,
  ) {
    final views = <Float32List>[];
    final strides = <int>[];
    final element = <int>[];
    final offsets = <List<int>>[];
    final counts = <List<int>>[];
    var total = 0;

    for (var slot = 0; slot < layout.buffers.length; slot++) {
      final buffer = layout.buffers[slot];
      final bytes = slot == 0 ? slotZero : slots?[slot];
      if (bytes == null) {
        throw StateError(
          'the pipeline\'s layout describes slot $slot and nothing was bound '
          'to it. Every slot the layout names has to be filled before a draw.',
        );
      }
      views.add(
        bytes.buffer.asFloat32List(
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ 4,
        ),
      );
      if (buffer.strideInBytes % 4 != 0) {
        throw UnsupportedError(
          'slot $slot has a stride of ${buffer.strideInBytes} bytes. This '
          'backend reads floats, so a stride has to be a multiple of four.',
        );
      }
      strides.add(buffer.strideInBytes ~/ 4);
      // The one line instancing is actually about: a per-instance buffer is
      // read at the instance index and stays there for every vertex of it.
      element.add(buffer.stepMode == VertexStepMode.instance ? instance : -1);

      final theseOffsets = <int>[];
      final theseCounts = <int>[];
      for (final attribute in buffer.attributes) {
        theseOffsets.add(attribute.offsetInBytes ~/ 4);
        theseCounts.add(attribute.format.componentCount);
        total += attribute.format.componentCount;
      }
      offsets.add(theseOffsets);
      counts.add(theseCounts);
    }

    return LayoutFetch._(views, strides, element, offsets, counts, total);
  }

  final List<Float32List> _views;
  final List<int> _strides;

  /// The fixed element index for a per-instance buffer, or -1 for a per-vertex
  /// one, which takes the vertex it is asked for.
  final List<int> _element;

  final List<List<int>> _offsets;
  final List<List<int>> _counts;

  @override
  final int floatsPerVertex;

  @override
  bool into(Float32List out, int vertex) {
    var at = 0;
    for (var slot = 0; slot < _views.length; slot++) {
      final view = _views[slot];
      final fixed = _element[slot];
      final base = (fixed < 0 ? vertex : fixed) * _strides[slot];
      final offsets = _offsets[slot];
      final counts = _counts[slot];
      for (var a = 0; a < offsets.length; a++) {
        final from = base + offsets[a];
        final count = counts[a];
        if (from + count > view.length) return false;
        for (var c = 0; c < count; c++) {
          out[at++] = view[from + c];
        }
      }
    }
    return true;
  }
}
