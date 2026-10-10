/// `GraphicsDevice.beginTransferPass` on flutter_gpu: the one copy it can do
/// whole, and a named refusal for each it cannot.
///
/// flutter_gpu's `CommandBuffer` has three copies — buffer to texture,
/// texture to buffer and texture to texture — and none of them is the whole
/// of the contract's copy of the same name: the texture-to-texture and
/// texture-to-buffer copies take level 0 and slice 0 only, the second writes
/// into a `DeviceBuffer` nothing can read back, and there is no buffer to
/// buffer copy or fill at all. A feature is reported whole or not at all, so
/// the four copies refuse; `writeTexture` is where `copyBufferToTexture` is
/// used, because there it covers everything the call promises.
///
/// What this encoder does do is resolve, which flutter_gpu offers as a render
/// pass with nothing drawn in it: the multisampled texture loaded, resolved
/// into the single-sample one, and kept.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'gpu_capabilities.dart';
import 'gpu_texture.dart';

/// The copies of one transfer pass, recorded as work and handed to the queue
/// in order at [submit].
final class GpuTransferEncoder extends TransferEncoder {
  GpuTransferEncoder(this._features, {required this.onRejectedSubmission});

  final DeviceFeatures _features;

  /// The device's counter of refused command buffers.
  final void Function() onRejectedSubmission;

  /// Each recorded copy, run at [submit] in the order it was recorded.
  final List<void Function()> _work = <void Function()>[];

  bool _submitted = false;

  void _record(void Function() work) {
    if (_submitted) {
      throw StateError('this transfer pass has already been submitted');
    }
    _work.add(work);
  }

  @override
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  ) =>
      // TODO(impeller): flutter_gpu's CommandBuffer has no buffer-to-buffer
      // copy — unblocked by an upstream CommandBuffer.copyBufferToBuffer.
      _features.require(
        DeviceFeature.bufferCopy,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no buffer-to-buffer copy',
      );

  @override
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) =>
      // TODO(impeller): flutter_gpu has no buffer fill on a command buffer —
      // unblocked by an upstream CommandBuffer.clearBuffer (or a buffer copy).
      _features.require(
        DeviceFeature.bufferCopy,
        backend: impellerBackendName,
        reason: 'flutter_gpu has no buffer fill',
      );

  @override
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) =>
      // TODO(impeller): flutter_gpu's copyTextureToTexture refuses every mip
      // level and slice but 0 and formats that differ in sRGB-ness —
      // unblocked by upstream lifting "Only mipLevel 0 and slice 0 are
      // currently supported for texture-to-texture copies".
      _features.require(
        DeviceFeature.textureCopy,
        backend: impellerBackendName,
        reason:
            'flutter_gpu copies a texture into another at level 0 and slice '
            '0 only',
      );

  @override
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) =>
      // TODO(impeller): flutter_gpu has this direction whole, but the feature
      // is the pair and the other direction is not — unblocked by what
      // unblocks copyTextureToBuffer below.
      _features.require(
        DeviceFeature.bufferTextureCopy,
        backend: impellerBackendName,
        reason:
            'flutter_gpu copies a texture into a buffer at level 0 and slice '
            '0 only, and into a DeviceBuffer nothing can read back',
      );

  @override
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  }) =>
      // TODO(impeller): flutter_gpu's copyTextureToBuffer takes level 0 slice
      // 0 only, and a DeviceBuffer has no read path — unblocked by upstream
      // lifting that restriction and adding a DeviceBuffer read/map.
      _features.require(
        DeviceFeature.bufferTextureCopy,
        backend: impellerBackendName,
        reason:
            'flutter_gpu copies a texture into a buffer at level 0 and slice '
            '0 only, and into a DeviceBuffer nothing can read back',
      );

  /// A render pass with nothing drawn: [source] loaded, resolved into
  /// [destination] and stored, so the multisampled texture survives for the
  /// passes that keep drawing into it. Level 0, layer 0 and the whole of
  /// both textures, which is what flutter_gpu's resolve attachment is.
  @override
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  ) {
    _features.require(
      DeviceFeature.offscreenMultisample,
      backend: impellerBackendName,
      reason: 'flutter_gpu reports no offscreen MSAA on this context',
    );
    final from = source.texture;
    final into = destination.texture;
    if (from.sampleCount <= 1 || into.sampleCount != 1) {
      throw ArgumentError(
        'resolveTexture: the source must be multisampled and the destination '
        'single-sample; got x${from.sampleCount} into x${into.sampleCount}',
      );
    }
    if (from.width != into.width ||
        from.height != into.height ||
        from.format != into.format) {
      throw ArgumentError(
        'resolveTexture: $from and $into differ in size or format',
      );
    }
    if (from.format.isDepthOrStencil) {
      throw ArgumentError(
        'resolveTexture: ${from.format.name} is a depth format, and '
        'flutter_gpu resolves colour attachments only',
      );
    }
    final corners = <int>[
      source.x,
      source.y,
      source.z,
      source.mipLevel,
      destination.x,
      destination.y,
      destination.z,
      destination.mipLevel,
    ];
    if (corners.any((int at) => at != 0)) {
      throw ArgumentError(
        'resolveTexture: a resolve covers level 0, layer 0 of both textures '
        'from the corner, which is what a resolve attachment is',
      );
    }
    _record(() {
      final buffer = gpu.gpuContext.createCommandBuffer();
      buffer.createRenderPass(
        gpu.RenderTarget(
          colorAttachments: <gpu.ColorAttachment>[
            gpu.ColorAttachment(
              texture: from.gpuTexture,
              resolveTexture: into.gpuTexture,
              loadAction: gpu.LoadAction.load,
              storeAction: gpu.StoreAction.storeAndMultisampleResolve,
            ),
          ],
        ),
      );
      buffer.submit(
        completionCallback: (bool ok) {
          if (!ok) onRejectedSubmission();
        },
      );
    });
  }

  @override
  void submit() {
    if (_submitted) {
      throw StateError('this transfer pass has already been submitted');
    }
    _submitted = true;
    for (final work in _work) {
      work();
    }
    _work.clear();
  }
}
