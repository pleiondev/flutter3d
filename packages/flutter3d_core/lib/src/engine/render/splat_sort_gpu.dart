/// Putting a cloud in drawing order on the GPU — `H11`, `H6`'s first engine
/// consumer.
///
/// **The same sort as `splat_sort.dart`, moved, not a second one.** The keys
/// are `SplatSorter.quantize`'s, made on the CPU; what moves is the ordering
/// of them: two stable eight-bit radix passes, low byte then high, each a
/// count per tile, a scan of the counts and a scatter. A stable sort of the
/// same keys has one answer, so the order that comes out is the CPU's to the
/// splat — ties in index order on both — and so is the picture.
///
/// **The order never comes back to the CPU.** The last scatter writes the
/// draw's index buffer itself: six indices a splat, pointing at the six
/// vertices `SplatQuads` built for it in the cloud's own order. A readback
/// would cost a frame of latency or a stall; an index buffer written in the
/// queue before the draw that reads it costs neither, and the draw is the
/// same draw through a different index buffer.
///
/// **Where a device has no compute, or no `SplatSort` stages, nothing here
/// runs** and the cloud is sorted on the CPU, which is every backend but
/// WebGPU today: WebGL2 and Impeller answer `supportsCompute` false, and the
/// software rasteriser computes but does not carry these stages, so its
/// clouds stay on the sort the GPU's is held to.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The compute stages the GPU sort dispatches, in the order it does.
const List<String> splatSortStages = <String>[
  'SplatSortCount',
  'SplatSortScan',
  'SplatSortScatter',
];

/// The most splats the GPU sort takes; a larger cloud is sorted on the CPU.
///
/// The index buffer it writes is 24 bytes a splat, and 2²² of them is 96 MiB,
/// under the 128 MiB a WebGPU device binds as storage unless asked for more.
/// It also keeps every count the stages are handed exact in the 32-bit floats
/// their uniform block carries.
const int splatGpuSortLimit = 1 << 22;

/// Keys a tile, and invocations a workgroup, in all three stages.
const int _tile = 256;

/// How many index buffers one cloud keeps at most. One is drawn from per
/// frame; another is only needed when the cloud is sorted again for a second
/// view of the same frame, whose draw would otherwise read the first view's
/// order out from under it.
const int _maxOutputs = 4;

/// One index buffer the sort writes and a draw reads.
final class _Output {
  _Output(this.buffer, this.capacity);

  final StorageBuffer buffer;

  /// Splats it holds the indices of.
  final int capacity;

  /// The frame a draw last bound it in; until that frame's passes are
  /// submitted, writing it again would change what that draw reads.
  int drawnIn = -1;
}

/// Sorts one cloud's keys on [device] and keeps the index buffer the draw
/// binds. One per drawn cloud, as `SplatSorter` is.
final class SplatGpuSort {
  /// [readable] makes every index buffer readable back, for a test that holds
  /// the order to the CPU's.
  SplatGpuSort(this.device, {this.readable = false});

  final GraphicsDevice device;
  final bool readable;

  /// Whether [device] can run this: compute, and all three stages.
  static bool availableOn(GraphicsDevice device) =>
      device.features.has(DeviceFeature.compute) &&
      splatSortStages.every((name) => device.shaders[name] != null);

  List<ComputePipelineHandle>? _pipelines;

  /// The second pass's input, written by the first: keys and splat indices.
  StorageBuffer? _keysB;
  StorageBuffer? _orderB;

  /// Counts per (digit, tile), scanned in place into first slots.
  StorageBuffer? _counts;
  int _scratchCapacity = 0;

  /// This sort's keys, kept until the next sort: the pass that reads them was
  /// submitted, but nothing is gained by betting on how soon it runs.
  StorageBuffer? _keys;

  final List<_Output> _outputs = <_Output>[];
  _Output? _current;
  int _count = 0;

  /// How many times [sort] has dispatched.
  int get sorts => _sorts;
  int _sorts = 0;

  /// Forgets the pipelines, for a device whose shaders were swapped.
  void relink() => _pipelines = null;

  /// Orders the first [count] of [keys] ascending, carrying each splat's
  /// index, and writes the draw's index buffer from that order.
  ///
  /// [frameIndex] is the frame being encoded: an index buffer a draw of this
  /// frame has bound is never the one written.
  void sort(Uint32List keys, int count, {required int frameIndex}) {
    if (count == 0 || count > splatGpuSortLimit) {
      throw ArgumentError.value(
        count,
        'count',
        'the GPU sort takes 1 to $splatGpuSortLimit splats',
      );
    }
    final pipelines = _pipelines ??= <ComputePipelineHandle>[
      for (final name in splatSortStages)
        device.createComputePipeline(device.shaders[name]!),
    ];
    final tiles = (count + _tile - 1) ~/ _tile;
    _growScratch(tiles * _tile);
    final output = _current = _outputFor(count, frameIndex);
    _count = count;

    final previousKeys = _keys;
    if (previousKeys != null) device.releaseStorageBuffer(previousKeys);
    final keysA = _keys = device.createStorageBuffer(
      keys.buffer.asByteData(keys.offsetInBytes, count * 4),
    );
    final keysB = _keysB!, orderB = _orderB!, counts = _counts!;
    final [countStage, scanStage, scatterStage] = <ShaderHandle>[
      for (final p in pipelines) p.shader,
    ];

    final pass = device.beginComputePass(label: 'splat sort');
    for (final shift in const <int>[0, 8]) {
      final last = shift == 8;
      final info = <String, Float32List>{
        'sort': Float32List.fromList(<double>[
          count.toDouble(),
          shift.toDouble(),
          tiles.toDouble(),
          // 0: a key's splat is its own index; 2: write the index buffer.
          last ? 2.0 : 0.0,
        ]),
      };
      final keysIn = last ? keysB : keysA;
      pass
        ..bindPipeline(pipelines[0])
        ..bindStorageBuffer(countStage, 'SortKeys', keysIn)
        ..bindStorageBuffer(countStage, 'SortCounts', counts)
        ..bindUniformBlock(countStage, 'SortInfo', info)
        ..dispatch(tiles)
        ..bindPipeline(pipelines[1])
        ..bindStorageBuffer(scanStage, 'SortCounts', counts)
        ..bindUniformBlock(scanStage, 'SortInfo', info)
        ..dispatch(1)
        ..bindPipeline(pipelines[2])
        ..bindStorageBuffer(scatterStage, 'SortKeysIn', keysIn)
        // Not read by the first pass, and bound to its own keys: a binding
        // has to be there, and a read-only one beside a read-only one is the
        // one pairing that cannot collide with a write.
        ..bindStorageBuffer(scatterStage, 'SortOrderIn', last ? orderB : keysA)
        ..bindStorageBuffer(scatterStage, 'SortOffsets', counts)
        // The last pass writes no keys; its output binding goes to the
        // first pass's input, which nothing reads any more.
        ..bindStorageBuffer(scatterStage, 'SortKeysOut', last ? keysA : keysB)
        ..bindStorageBuffer(
          scatterStage,
          'SortOrderOut',
          last ? output.buffer : orderB,
        )
        ..bindUniformBlock(scatterStage, 'SortInfo', info)
        ..dispatch(tiles);
    }
    pass.submit();
    _sorts++;
  }

  /// The index buffer the last [sort] wrote, `6 × count` 32-bit indices,
  /// marked as drawn from in [frameIndex]. Null before the first sort.
  GeometryBuffer? drawn(int frameIndex) {
    _current?.drawnIn = frameIndex;
    return indices;
  }

  /// The index buffer the last [sort] wrote, for a second draw of the same
  /// frame that [drawn] already marked. Null before the first sort.
  GeometryBuffer? get indices =>
      _current?.buffer.asIndices!.slice(length: _count * 6 * 4);

  /// The last [sort]'s index buffer read back, `6 × count` indices. Only on
  /// a sorter made [readable].
  Future<Uint32List> readIndices() async {
    final current = _current;
    if (current == null) return Uint32List(0);
    final bytes = await device.readBuffer(current.buffer);
    return Uint32List.fromList(
      bytes.buffer.asUint32List(bytes.offsetInBytes, _count * 6),
    );
  }

  /// Gives every buffer back to [device]; the next [sort] makes new ones.
  void release() {
    for (final buffer in <StorageBuffer?>[
      _keys,
      _keysB,
      _orderB,
      _counts,
      for (final o in _outputs) o.buffer,
    ]) {
      if (buffer != null) device.releaseStorageBuffer(buffer);
    }
    _keys = _keysB = _orderB = _counts = null;
    _scratchCapacity = 0;
    _outputs.clear();
    _current = null;
  }

  void _growScratch(int keys) {
    if (keys <= _scratchCapacity) return;
    var capacity = _scratchCapacity == 0 ? 4 * _tile : _scratchCapacity;
    while (capacity < keys) {
      capacity *= 2;
    }
    // Only compute passes already submitted have read these, so they can go
    // at once.
    for (final buffer in <StorageBuffer?>[_keysB, _orderB, _counts]) {
      if (buffer != null) device.releaseStorageBuffer(buffer);
    }
    _keysB = device.createStorageBuffer(ByteData(capacity * 4));
    _orderB = device.createStorageBuffer(ByteData(capacity * 4));
    // 256 digits a tile, and `capacity` is whole tiles.
    _counts = device.createStorageBuffer(ByteData(capacity * 4));
    _scratchCapacity = capacity;
  }

  /// An index buffer of at least [count] splats that no draw of
  /// [frameIndex] has bound: the current one when it qualifies, then any
  /// other, then a new one.
  _Output _outputFor(int count, int frameIndex) {
    _Output? free;
    for (final o in <_Output>[?_current, ..._outputs]) {
      if (o.drawnIn != frameIndex) {
        free = o;
        break;
      }
    }
    if (free != null && free.capacity >= count) return free;
    if (free != null) {
      // Too small, and drawn only in frames already submitted.
      device.releaseStorageBuffer(free.buffer);
      _outputs.remove(free);
    } else if (_outputs.length >= _maxOutputs) {
      // Outside a renderer every frame is frame 0; past the cap the oldest
      // goes, which is the order a renderer would have finished them in.
      device.releaseStorageBuffer(_outputs.removeAt(0).buffer);
    }
    var capacity = 1024;
    while (capacity < count) {
      capacity *= 2;
    }
    final made = _Output(
      device.createStorageBuffer(
        ByteData(capacity * 6 * 4),
        hostReadable: readable,
        bindableAsIndices: true,
      ),
      capacity,
    );
    _outputs.add(made);
    return made;
  }
}
