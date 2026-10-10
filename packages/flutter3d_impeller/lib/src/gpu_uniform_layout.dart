/// What one uniform block of a compiled stage looks like, asked of
/// flutter_gpu once.
library;

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'host_buffer_grid.dart';

/// A uniform block's slot, size and member offsets, kept per stage by the
/// device.
///
/// **Asked once, not per draw.** `getUniformSlot` makes a new slot object
/// and `getMemberOffsetInBytes` crosses into the engine, and the encoder
/// asked both for every member of every block of every draw. The answers
/// are a property of the compiled stage, which does not change, so the
/// device keeps them beside the stage.
final class GpuUniformLayout {
  /// A layout read through [offsetLookup], which is asked at most once for
  /// each member name.
  GpuUniformLayout({
    required this.slot,
    required this.sizeInBytes,
    required int granule,
    required int? Function(String member) offsetLookup,
  }) : emplacedSize = roundedTo(sizeInBytes, granule),
       _lookup = offsetLookup;

  /// The layout of [blockName] in [shader], or null when the stage has no
  /// such block or it is empty — the case the contract answers false.
  static GpuUniformLayout? of(
    gpu.Shader shader,
    String blockName, {
    required int granule,
  }) {
    final slot = shader.getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return null;
    return GpuUniformLayout(
      slot: slot,
      sizeInBytes: size,
      granule: granule,
      offsetLookup: slot.getMemberOffsetInBytes,
    );
  }

  /// The slot a pass binds the block to; an [Object] here so a test can
  /// stand one in, and the `gpu.UniformSlot` the device asked for otherwise.
  final Object slot;

  /// The block's size as the stage declares it.
  final int sizeInBytes;

  /// [sizeInBytes] rounded up to the device's granule: the length the block
  /// is written at, so `HostBuffer.emplace` takes it as it is.
  final int emplacedSize;

  final int? Function(String member) _lookup;
  final Map<String, int?> _offsets = <String, int?>{};

  /// Where [member] starts, in bytes, or null when the block has no such
  /// member.
  int? offsetOf(String member) =>
      _offsets.putIfAbsent(member, () => _lookup(member));
}
