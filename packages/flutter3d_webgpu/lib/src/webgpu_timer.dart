/// What the GPU spent on each labelled pass, on WebGPU — `H2`.
///
/// A frame's labelled passes each get two queries in a set of their own,
/// written at the start and the end of the pass. At the start of the next
/// frame the set is resolved into a buffer, copied to one that can be mapped,
/// and read when the GPU gets there — which is why a frame's timings reach
/// `GraphicsDevice.onGpuTimings` a frame or two after it was drawn.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_interop.dart';

final class WebGpuTimer {
  WebGpuTimer(this._gpu);

  final GPUDevice _gpu;

  /// Two queries a pass, so this many passes a frame are timed; the rest are
  /// drawn untimed rather than refused.
  static const int maxPasses = 64;

  GPUQuerySet? _set;
  final List<String> _labels = <String>[];
  int _frame = 0;

  /// The writes for a pass labelled [label], or null when this frame's set
  /// is full.
  GPURenderPassTimestampWrites? next(String label) {
    if (_labels.length >= maxPasses) return null;
    final set = _set ??= _gpu.createQuerySet(
      GPUQuerySetDescriptor(
        type: 'timestamp',
        count: maxPasses * 2,
        label: 'pass timings, frame $_frame',
      ),
    );
    final index = _labels.length * 2;
    _labels.add(label);
    return GPURenderPassTimestampWrites(
      querySet: set,
      beginningOfPassWriteIndex: index,
      endOfPassWriteIndex: index + 1,
    );
  }

  /// Resolves the frame just finished and hands its timings to [listener]
  /// once the GPU has written them; starts the next frame's set.
  void endFrame(void Function(GpuFrameTimings timings)? listener) {
    final set = _set;
    final labels = List<String>.of(_labels);
    final frame = _frame++;
    _set = null;
    _labels.clear();
    if (set == null || labels.isEmpty) return;
    if (listener == null) {
      set.destroy();
      return;
    }

    final bytes = labels.length * 2 * 8;
    final resolved = _gpu.createBuffer(
      GPUBufferDescriptor(
        size: bytes,
        usage: GpuBufferUsage.queryResolve | GpuBufferUsage.copySrc,
        label: 'pass timings resolved, frame $frame',
      ),
    );
    final staging = _gpu.createBuffer(
      GPUBufferDescriptor(
        size: bytes,
        usage: GpuBufferUsage.copyDst | GpuBufferUsage.mapRead,
        label: 'pass timings read, frame $frame',
      ),
    );
    final encoder = _gpu.createCommandEncoder()
      ..resolveQuerySet(set, 0, labels.length * 2, resolved, 0)
      ..copyBufferToBuffer(resolved, 0, staging, 0, bytes);
    _gpu.queue.submit(<GPUCommandBuffer>[encoder.finish()].toJS);

    unawaited(
      staging.mapAsync(GpuMapMode.read).toDart.then((JSAny? _) {
        final data = ByteData.sublistView(
          Uint8List.fromList(staging.getMappedRange().toDart.asUint8List()),
        );
        staging.unmap();
        // 64-bit nanoseconds, read as two halves: `getUint64` is not there
        // when this is compiled to JavaScript, and a double holds any
        // difference of two frame timestamps exactly.
        double ns(int query) =>
            data.getUint32(query * 8 + 4, Endian.little) * 4294967296.0 +
            data.getUint32(query * 8, Endian.little);
        listener(
          GpuFrameTimings(
            frame: frame,
            // A pair that is not a start before an end is left out rather
            // than reported: on Metal a pass that drew nothing writes no end
            // at all, and the difference would be the machine's uptime,
            // negative.
            passes: <GpuPassTiming>[
              for (var i = 0; i < labels.length; i++)
                if (ns(i * 2) > 0 && ns(i * 2 + 1) >= ns(i * 2))
                  GpuPassTiming(
                    label: labels[i],
                    micros: ((ns(i * 2 + 1) - ns(i * 2)) / 1000.0).round(),
                  ),
            ],
          ),
        );
        set.destroy();
        resolved.destroy();
        staging.destroy();
      }),
    );
  }
}
