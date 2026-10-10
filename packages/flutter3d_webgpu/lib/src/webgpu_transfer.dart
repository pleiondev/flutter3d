/// Copies between buffers and textures on WebGPU — `TransferEncoder`.
///
/// **One `GPUCommandEncoder` with no pass open in it**, which is what a copy
/// is in this API: the five copy commands and `clearBuffer` are recorded on
/// the command encoder itself, between passes, and ordering is by submission
/// as everywhere else in the contract. The one copy that is not a copy is
/// [WebGpuTransferEncoder.resolveTexture], which WebGPU spells as an empty
/// render pass whose attachment resolves.
///
/// Every refusal the browser would make asynchronously — an unaligned offset,
/// a row stride that is not a multiple of 256, a range past a buffer, a
/// usage the resource was not made with — is made here first, by name.
library;

import 'dart:js_interop';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_compute.dart' show WebGpuStorage;
import 'webgpu_formats.dart';
import 'webgpu_interop.dart';
import 'webgpu_resources.dart';
import 'webgpu_types.dart';

const String _backend = 'WebGPU';

/// A transfer pass, recorded into one command encoder and submitted whole.
final class WebGpuTransferEncoder extends TransferEncoder {
  WebGpuTransferEncoder(
    this._gpu, {
    required this._features,
    required this._guard,
    String? label,
  }) : _label = label ?? 'flutter3d transfer',
       _encoder = _gpu.createCommandEncoder();

  final GPUDevice _gpu;
  final DeviceFeatures _features;
  final T Function<T>(String what, T Function() body) _guard;
  final String _label;
  final GPUCommandEncoder _encoder;

  @override
  void pushDebugGroup(String label) => _encoder.pushDebugGroup(label);

  @override
  void popDebugGroup() => _encoder.popDebugGroup();

  @override
  void insertDebugMarker(String label) => _encoder.insertDebugMarker(label);
  bool _submitted = false;

  void _open() {
    if (_submitted) throw StateError('this transfer pass has been submitted');
  }

  static void _aligned(int value, String name) {
    if (value % 4 != 0) {
      throw ArgumentError.value(value, name, 'is not a multiple of 4');
    }
  }

  static void _inside(StorageBuffer buffer, int offset, int size, String n) {
    if (offset < 0 || size < 0 || offset + size > buffer.lengthInBytes) {
      throw RangeError(
        '$n: $size bytes from $offset leave the '
        '${buffer.lengthInBytes}-byte buffer',
      );
    }
  }

  static void _uses(StorageBuffer buffer, BufferUsage usage, String name) {
    if (!buffer.usage.contains(usage)) {
      throw ArgumentError.value(buffer.usage, name, 'needs $usage');
    }
  }

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) {
    _features.require(DeviceFeature.bufferCopy, backend: _backend);
    _open();
    _aligned(sourceOffset, 'sourceOffset');
    _aligned(destinationOffset, 'destinationOffset');
    _aligned(size, 'size');
    _inside(source, sourceOffset, size, 'source');
    _inside(destination, destinationOffset, size, 'destination');
    _uses(source, BufferUsage.copySource, 'source');
    _uses(destination, BufferUsage.copyDestination, 'destination');
    _encoder.copyBufferToBuffer(
      (source.backend as WebGpuStorage).buffer,
      sourceOffset,
      (destination.backend as WebGpuStorage).buffer,
      destinationOffset,
      size,
    );
  }

  /// Zeroes the range. A range that runs to the end of a buffer whose length
  /// is not a multiple of four is rounded up into the padding the buffer was
  /// allocated with, which nothing reads.
  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _features.require(DeviceFeature.bufferCopy, backend: _backend);
    _open();
    final size = sizeInBytes ?? buffer.lengthInBytes - offsetInBytes;
    _inside(buffer, offsetInBytes, size, 'clearBuffer');
    _aligned(offsetInBytes, 'offsetInBytes');
    final toEnd = offsetInBytes + size == buffer.lengthInBytes;
    if (!toEnd) _aligned(size, 'sizeInBytes');
    _uses(buffer, BufferUsage.copyDestination, 'buffer');
    _encoder.clearBuffer(
      (buffer.backend as WebGpuStorage).buffer,
      offsetInBytes,
      (size + 3) & ~3,
    );
  }

  static GPUTexelCopyTextureInfo _info(TextureCopyLocation at) =>
      GPUTexelCopyTextureInfo(
        texture: (at.texture.backend as WebGpuTexture).texture,
        mipLevel: at.mipLevel,
        origin: GPUOrigin3DDict(x: at.x, y: at.y, z: at.z),
        aspect: 'all',
      );

  /// [at] and the box from it checked against the texture, its level and the
  /// format's blocks; [usage] is the `GpuTextureUsage` bit the side needs.
  static void _checkTexture(
    TextureCopyLocation at,
    int width,
    int height,
    int depth, {
    required int usage,
    required bool intoTexture,
  }) {
    final texture = (at.texture.backend as WebGpuTexture).texture;
    if (texture.usage & usage == 0) {
      throw ArgumentError.value(
        at.texture,
        intoTexture ? 'destination' : 'source',
        intoTexture
            ? 'was not made with TextureUsage.copyDestination'
            : 'was not made with TextureUsage.copySource',
      );
    }
    final block = gpuCopyBlock(at.texture.format, intoTexture: intoTexture);
    if (block == null) {
      throw ArgumentError.value(
        at.texture.format,
        'format',
        'has no byte layout WebGPU copies ${intoTexture ? 'into' : 'out of'}',
      );
    }
    webgpuCheckRegion(
      texture,
      at.texture.format,
      at.mipLevel,
      TextureRegion(
        x: at.x,
        y: at.y,
        z: at.z,
        width: width,
        height: height,
        depthOrArrayLayers: depth,
      ),
      block: block,
    );
  }

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.textureCopy, backend: _backend);
    _open();
    final a = source.texture;
    final b = destination.texture;
    final sameFormat =
        a.format == b.format ||
        gpuTextureFormat(a.format)?.replaceAll('-srgb', '') ==
            gpuTextureFormat(b.format)?.replaceAll('-srgb', '');
    if (!sameFormat || a.sampleCount != b.sampleCount) {
      throw ArgumentError(
        'copyTextureToTexture: ${a.format.name} x${a.sampleCount} and '
        '${b.format.name} x${b.sampleCount} differ in more than sRGB-ness',
      );
    }
    _checkTexture(
      source,
      width,
      height,
      depthOrArrayLayers,
      usage: GpuTextureUsage.copySrc,
      intoTexture: false,
    );
    _checkTexture(
      destination,
      width,
      height,
      depthOrArrayLayers,
      usage: GpuTextureUsage.copyDst,
      intoTexture: true,
    );
    _encoder.copyTextureToTexture(
      _info(source),
      _info(destination),
      GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: depthOrArrayLayers,
      ),
    );
  }

  /// The buffer side of a buffer–texture copy: the 256-byte row rule, the
  /// rows the box needs fitting in the buffer, and the layout as the API
  /// takes it.
  static GPUTexelCopyBufferInfo _bufferSide(
    StorageBuffer buffer,
    BufferTextureLayout layout,
    TextureFormat format,
    int width,
    int height,
    int depth, {
    required bool intoTexture,
  }) {
    gpuCheckCopyBytesPerRow(layout.bytesPerRow);
    final block = gpuCopyBlock(format, intoTexture: intoTexture)!;
    final across = (width + block.blockWidth - 1) ~/ block.blockWidth;
    final rows = (height + block.blockHeight - 1) ~/ block.blockHeight;
    final rowsPerImage = layout.rowsPerImage ?? rows;
    if (layout.bytesPerRow < across * block.bytesPerBlock ||
        rowsPerImage < rows) {
      throw ArgumentError.value(
        layout,
        'layout',
        'holds rows shorter or fewer than the copy needs',
      );
    }
    if (layout.offsetInBytes % block.bytesPerBlock != 0) {
      throw ArgumentError.value(
        layout.offsetInBytes,
        'offsetInBytes',
        'is not a multiple of the ${block.bytesPerBlock}-byte block',
      );
    }
    final needed =
        layout.bytesPerRow * rowsPerImage * (depth - 1) +
        layout.bytesPerRow * (rows - 1) +
        across * block.bytesPerBlock;
    _inside(buffer, layout.offsetInBytes, needed, 'the copy\'s buffer');
    return GPUTexelCopyBufferInfo(
      buffer: (buffer.backend as WebGpuStorage).buffer,
      offset: layout.offsetInBytes,
      bytesPerRow: layout.bytesPerRow,
      rowsPerImage: rowsPerImage,
    );
  }

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.bufferTextureCopy, backend: _backend);
    _open();
    _uses(source, BufferUsage.copySource, 'source');
    _checkTexture(
      destination,
      width,
      height,
      depthOrArrayLayers,
      usage: GpuTextureUsage.copyDst,
      intoTexture: true,
    );
    _encoder.copyBufferToTexture(
      _bufferSide(
        source,
        layout,
        destination.texture.format,
        width,
        height,
        depthOrArrayLayers,
        intoTexture: true,
      ),
      _info(destination),
      GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: depthOrArrayLayers,
      ),
    );
  }

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) {
    _features.require(DeviceFeature.bufferTextureCopy, backend: _backend);
    _open();
    _uses(destination, BufferUsage.copyDestination, 'destination');
    _checkTexture(
      source,
      width,
      height,
      depthOrArrayLayers,
      usage: GpuTextureUsage.copySrc,
      intoTexture: false,
    );
    _encoder.copyTextureToBuffer(
      _info(source),
      _bufferSide(
        destination,
        layout,
        source.texture.format,
        width,
        height,
        depthOrArrayLayers,
        intoTexture: false,
      ),
      GPUExtent3DDict(
        width: width,
        height: height,
        depthOrArrayLayers: depthOrArrayLayers,
      ),
    );
  }

  /// An empty render pass whose one attachment is [source] — loaded and
  /// kept, so the multisampled contents survive — resolving into
  /// [destination]. Nothing is drawn; the resolve is the pass's end.
  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) {
    _features.require(DeviceFeature.offscreenMultisample, backend: _backend);
    _open();
    final a = source.texture;
    final b = destination.texture;
    if (a.sampleCount <= 1 ||
        b.sampleCount != 1 ||
        a.format != b.format ||
        a.width >> source.mipLevel != b.width >> destination.mipLevel ||
        a.height >> source.mipLevel != b.height >> destination.mipLevel) {
      throw ArgumentError(
        'resolveTexture: the source must be multisampled, the destination '
        'single-sampled, and the two one format and size',
      );
    }
    final from = a.backend as WebGpuTexture;
    final into = b.backend as WebGpuTexture;
    _encoder
        .beginRenderPass(
          GPURenderPassDescriptor(
            label: '$_label resolve',
            colorAttachments: <GPURenderPassColorAttachment>[
              GPURenderPassColorAttachment.resolving(
                view: from.attachmentView(
                  level: source.mipLevel,
                  layer: source.z,
                ),
                resolveTarget: into.attachmentView(
                  level: destination.mipLevel,
                  layer: destination.z,
                ),
                clearValue: GPUColorDict(r: 0, g: 0, b: 0, a: 0),
                loadOp: 'load',
                storeOp: 'store',
              ),
            ].toJS,
          ),
        )
        .end();
  }

  @override
  void submit() {
    _open();
    _submitted = true;
    _guard(
      'the transfer pass "$_label"',
      () => _gpu.queue.submit(<GPUCommandBuffer>[_encoder.finish()].toJS),
    );
  }
}
