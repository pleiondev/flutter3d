/// Compute: storage buffers, compute pipelines and the encoder that dispatches
/// them — `H6`.
///
/// **In the contract whole, before every backend runs it.** Every interface
/// here is implemented by each backend package, which is pinned to this one by
/// a caret range, so a member added in a patch release would break the backend
/// that shipped before it. 0.8.0 therefore carries the whole shape. WebGPU and
/// the software rasteriser run it; WebGL2 and Impeller answer
/// [GraphicsDevice.supportsCompute] with false and refuse the creators with an
/// [UnsupportedError]. Impeller follows when flutter_gpu exposes compute
/// pipelines (flutter/flutter#188480), and the shape follows its proposal
/// (#188474) so that becomes a mapping rather than a redesign.
library;

import 'dart:typed_data';

import 'shader.dart';

/// A buffer a compute stage reads and writes.
///
/// [backend] is the backend's own object, exactly as a `TextureHandle`
/// carries its texture: nothing above the backend looks inside it.
final class StorageBuffer {
  StorageBuffer({
    required this.backend,
    required this.lengthInBytes,
    this.hostReadable = false,
  });

  final Object backend;

  /// The size it was created with, in bytes.
  final int lengthInBytes;

  /// Whether `GraphicsDevice.readBuffer` may read it back. Asked at creation
  /// because a GPU buffer that can be mapped for reading is a different
  /// allocation from one that cannot, on every API that has either.
  final bool hostReadable;
}

/// A compiled compute stage, ready to dispatch.
final class ComputePipelineHandle {
  ComputePipelineHandle({required this.backend, required this.shader});

  final Object backend;

  /// The stage it was built from.
  final ShaderHandle shader;
}

/// Records one compute pass: bindings, then dispatches, then [submit].
///
/// The same shape as a render pass's encoder, and the same rules: a binding
/// the stage does not declare answers false rather than throwing, and
/// [bindPipeline] forgets every binding made before it.
abstract interface class ComputeEncoder {
  /// Makes [pipeline] the one the next [dispatch] runs, and forgets every
  /// binding.
  void bindPipeline(ComputePipelineHandle pipeline);

  /// Binds [buffer] to the storage binding [name] of [stage]. False when the
  /// stage declares no such binding.
  bool bindStorageBuffer(ShaderHandle stage, String name, StorageBuffer buffer);

  /// Binds the uniform block [block] of [stage], by member name, exactly as
  /// `PassEncoder.bindUniformBlock` does. False when the stage declares no
  /// such block.
  bool bindUniformBlock(
    ShaderHandle stage,
    String block,
    Map<String, Float32List> members,
  );

  /// Runs the bound pipeline over a grid of `x × y × z` workgroups.
  void dispatch(int x, [int y = 1, int z = 1]);

  /// Hands the pass to the queue. Nothing recorded after this reaches it.
  void submit();
}
