/// Copies between buffers and textures, recorded and submitted as one pass —
/// `GraphicsDevice.beginTransferPass`.
///
/// **A pass of its own, for the reason a render pass and a compute pass are
/// separate.** Every encoder in this contract fuses a command buffer with the
/// one pass recorded into it (see `command_encoder.dart`, divergence 1), and
/// ordering between passes is by submission. A copy has to be ordered against
/// the passes that write its source and read its destination, so it is a pass
/// too: submitted after the compute pass that filled a buffer, before the
/// render pass that draws from what it was copied into.
///
/// Every copy is gated by its own `DeviceFeature`, and a backend without it
/// throws `UnsupportedCapability` from the copy — opening the pass itself is
/// never refused, so a caller can ask per copy rather than per pass.
library;

import 'compute.dart';
import 'resources.dart';
import 'texture.dart';

/// A texel position in one level of one texture: the corner a copy starts
/// from or lands at.
final class TextureCopyLocation {
  const TextureCopyLocation(
    this.texture, {
    this.mipLevel = 0,
    this.x = 0,
    this.y = 0,
    this.z = 0,
  });

  final TextureHandle texture;
  final int mipLevel;
  final int x;
  final int y;

  /// The layer, cube face or 3D slice.
  final int z;
}

/// Records copies; [submit] hands them to the queue.
///
/// **A copy names no aspect.** A texture with both depth and stencil cannot
/// be copied to or from a buffer as one block of bytes, and every backend
/// refuses such a copy with an [ArgumentError]; a depth-only format copies
/// its depth. Texture-to-texture copies of a combined format copy both.
///
/// **Implementable outside this package, and stays so through 1.x.** It does
/// not grow within a major: a capability added later arrives beside it — a
/// second interface an implementation opts into, or a member with a default
/// on a base class — so an implementation written against 1.0 keeps
/// compiling.
abstract base class TransferEncoder {
  /// Copies [size] bytes from [source] at [sourceOffset] into [destination]
  /// at [destinationOffset]. Offsets and size are multiples of four.
  /// `DeviceFeature.bufferCopy`.
  void copyBufferToBuffer(
    StorageBuffer source,
    int sourceOffset,
    StorageBuffer destination,
    int destinationOffset,
    int size,
  );

  /// Zeroes [sizeInBytes] bytes (to the end by default) of [buffer] from
  /// [offsetInBytes]. `DeviceFeature.bufferCopy`.
  void clearBuffer(
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  });

  /// Copies a [width] × [height] × [depthOrArrayLayers] box of texels from
  /// [source] to [destination]. The two textures share a format (or differ
  /// only in sRGB-ness) and a sample count. `DeviceFeature.textureCopy`.
  void copyTextureToTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  });

  /// Copies texels laid out in [source] as [layout] into [destination].
  /// `DeviceFeature.bufferTextureCopy`.
  void copyBufferToTexture(
    StorageBuffer source,
    BufferTextureLayout layout,
    TextureCopyLocation destination, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  });

  /// Copies texels from [source] into [destination], laid out as [layout].
  /// `DeviceFeature.bufferTextureCopy`.
  void copyTextureToBuffer(
    TextureCopyLocation source,
    StorageBuffer destination,
    BufferTextureLayout layout, {
    required int width,
    required int height,
    int depthOrArrayLayers = 1,
  });

  /// Resolves the multisampled [source] into the single-sample
  /// [destination] of the same size and format — the explicit form of a
  /// pass's `ColorTarget.resolveTexture`, for a target several passes drew
  /// into. `DeviceFeature.offscreenMultisample`. WebGL2's
  /// `blitFramebuffer`; WebGPU does it with an empty pass that resolves.
  void resolveTexture(
    TextureCopyLocation source,
    TextureCopyLocation destination,
  );

  /// Hands the copies to the queue. Nothing recorded after this reaches it.
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
