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

import 'geometry_buffer.dart';
import 'graphics_device.dart';
import 'resources.dart';
import 'sampler.dart';
import 'shader.dart';
import 'texture.dart';

/// A buffer a compute stage reads and writes.
///
/// [backend] is the backend's own object, exactly as a `TextureHandle`
/// carries its texture: nothing above the backend looks inside it.
final class StorageBuffer {
  StorageBuffer._(
    this._release, {
    required this.backend,
    required this.lengthInBytes,
    this.hostReadable = false,
    this.asIndices,
    this.asVertices,
    this.usage = BufferUsage.standardStorage,
  });

  final void Function(StorageBuffer)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// The same memory as a vertex buffer a draw can bind, when it was made
  /// with [BufferUsage.vertex] through `GraphicsDevice.createBuffer` — a
  /// compute pass writes particles and a draw reads them, nothing crossing
  /// back to the CPU. Null otherwise. Released with this buffer.
  final GeometryBuffer? asVertices;

  /// What it was made for. [BufferUsage.standardStorage] for every buffer
  /// `createStorageBuffer` makes; whatever `createBuffer` was asked for
  /// otherwise.
  final BufferUsage usage;

  final Object backend;

  /// The size it was created with, in bytes.
  final int lengthInBytes;

  /// Whether `GraphicsDevice.readBuffer` may read it back. Asked at creation
  /// because a GPU buffer that can be mapped for reading is a different
  /// allocation from one that cannot, on every API that has either.
  final bool hostReadable;

  /// The same memory as an index buffer a draw can bind, when it was asked
  /// for with `bindableAsIndices` — `H11`: a compute pass writes a draw's
  /// order and the draw reads it, and nothing crosses back to the CPU. Null
  /// otherwise. Released with this buffer, never through `releaseGeometry`.
  ///
  /// Asked at creation for [hostReadable]'s reason: WebGPU names `INDEX` in
  /// a buffer's usage when it is made, as `uploadGeometry` already found.
  final GeometryBuffer? asIndices;
}

/// A compiled compute stage, ready to dispatch.
final class ComputePipelineHandle {
  ComputePipelineHandle._(
    this._release, {
    required this.backend,
    required this.shader,
  });

  final void Function(ComputePipelineHandle)? _release;

  /// Gives this back to the device that made it, once: what `dispose` means
  /// on every handle. A second call does nothing. A handle a backend made
  /// without naming its device (a test's fake) has nothing to give back.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _release?.call(this);
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  final Object backend;

  /// The stage it was built from.
  final ShaderHandle shader;
}

/// Records one compute pass: bindings, then dispatches, then [submit].
///
/// The same shape as a render pass's encoder, and the same rules: a binding
/// the stage does not declare answers false rather than throwing, and
/// [bindPipeline] forgets every binding made before it.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
abstract base class ComputeEncoder {
  /// Makes [pipeline] the one the next [dispatch] runs, and forgets every
  /// binding.
  void bindPipeline(ComputePipelineHandle pipeline);

  /// Binds [buffer] to the storage binding [name] of [stage]. False when the
  /// stage declares no such binding.
  ///
  /// [offsetInBytes] and [sizeInBytes] bind a range of it — a multiple of
  /// `DeviceLimits.minStorageBufferOffsetAlignment` from the start, to the end
  /// by default. Since 0.9; every backend that binds storage at all honours
  /// the range, and refuses one that does not lie inside the buffer with a
  /// [RangeError].
  bool bindStorageBuffer(
    ShaderHandle stage,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  });

  /// Binds [texture] to the sampled-texture binding [name] of [stage], with
  /// [sampler] (null meaning `SamplerDescriptor.linearRepeat`, as for a render
  /// pass). False when the stage declares no such binding.
  bool bindTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  });

  /// Binds level [mipLevel] of [texture] as the storage texture [name] of
  /// [stage]. False when the stage declares no such binding.
  ///
  /// `DeviceFeature.storageTextures`, and `readWriteStorageTextures` for
  /// [StorageTextureAccess.readWrite]; the texture's format must answer
  /// `storage` (or `storageReadWrite`) in `textureFormatSupport`, and it must
  /// have been made with [TextureUsage.storage]. A backend without the
  /// feature throws `UnsupportedCapability`.
  bool bindStorageTexture(
    ShaderHandle stage,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  });

  /// Fills the uniform block [block] of [stage] from [bytes], laid out the
  /// way the compiled stage lays the block out (std140 for the engine's
  /// bundles). For integer and packed members a float map cannot carry.
  /// False when the stage declares no such block. `DeviceFeature.uniformBytes`.
  bool bindUniformBytes(ShaderHandle stage, String block, ByteData bytes);

  /// Runs the bound pipeline over the grid [arguments] holds at
  /// [offsetInBytes] — see `dispatchIndirectArguments` for the twelve bytes.
  /// The buffer must have been made with [BufferUsage.indirect].
  /// `DeviceFeature.indirectDispatch`.
  void dispatchIndirect(StorageBuffer arguments, {int offsetInBytes = 0});

  /// Starts counting into query [queryIndex] of [querySet], a
  /// [QueryType.pipelineStatistics] set —
  /// `DeviceFeature.pipelineStatisticsQuery`. Only
  /// [PipelineStatistic.computeShaderInvocations] counts in a compute pass.
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex);

  /// Stops the query [beginPipelineStatisticsQuery] opened.
  void endPipelineStatisticsQuery();

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

  // ------------------------------------------------------------------------
  // 1.0: debug groups. Bodies that do nothing, so an encoder written before
  // them keeps compiling, and a backend whose API has no markers is right to
  // leave them alone.
  // ------------------------------------------------------------------------

  /// Opens a named group around the commands recorded until the matching
  /// [popDebugGroup], for a GPU debugger or a frame capture to show as one
  /// node. Groups nest. Does nothing on a backend without markers.
  void pushDebugGroup(String label) {}

  /// Closes the group the last [pushDebugGroup] opened.
  void popDebugGroup() {}

  /// Marks one point in the command stream with [label].
  void insertDebugMarker(String label) {}
}

/// A [StorageBuffer] over a backend's own [backend] buffer — for a backend,
/// from `package:flutter3d_hardware/backend.dart`. [owner]'s
/// `releaseStorageBuffer` is what the handle's `dispose` calls.
StorageBuffer wrapStorageBuffer({
  required Object backend,
  required int lengthInBytes,
  bool hostReadable = false,
  GeometryBuffer? asIndices,
  GeometryBuffer? asVertices,
  BufferUsage usage = BufferUsage.standardStorage,
  GraphicsDevice? owner,
}) => StorageBuffer._(
  owner?.releaseStorageBuffer,
  backend: backend,
  lengthInBytes: lengthInBytes,
  hostReadable: hostReadable,
  asIndices: asIndices,
  asVertices: asVertices,
  usage: usage,
);

/// A [ComputePipelineHandle] over a backend's own [backend] pipeline, for a
/// backend; see [wrapStorageBuffer].
ComputePipelineHandle wrapComputePipeline({
  required Object backend,
  required ShaderHandle shader,
  GraphicsDevice? owner,
}) => ComputePipelineHandle._(
  owner?.releaseComputePipeline,
  backend: backend,
  shader: shader,
);
