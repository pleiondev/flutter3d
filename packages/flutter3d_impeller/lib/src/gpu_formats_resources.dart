/// Storage modes, texture types and pixel formats: the engine's vocabulary for
/// what a texture *is*, translated to and from flutter_gpu's.
///
/// See the library comment on `gpu_formats.dart` for the two rules every
/// mapping here is held to, and for why a reverse mapping exists for these and
/// not for pass and pipeline state.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Maps the engine's [StorageMode] to its `package:flutter_gpu` equivalent.
extension StorageModeToGpu on StorageMode {
  gpu.StorageMode toGpu() => switch (this) {
    StorageMode.hostVisible => gpu.StorageMode.hostVisible,
    StorageMode.devicePrivate => gpu.StorageMode.devicePrivate,
    StorageMode.deviceTransient => gpu.StorageMode.deviceTransient,
  };
}

/// Maps `package:flutter_gpu`'s storage mode back to the engine's
/// [StorageMode].
extension StorageModeFromGpu on gpu.StorageMode {
  StorageMode toEngine() => switch (this) {
    gpu.StorageMode.hostVisible => StorageMode.hostVisible,
    gpu.StorageMode.devicePrivate => StorageMode.devicePrivate,
    gpu.StorageMode.deviceTransient => StorageMode.deviceTransient,
  };
}

/// Maps the engine's [TextureType] to its `package:flutter_gpu` equivalent —
/// one-way, unlike its neighbours: [TextureHandle] carries the engine's type,
/// so nothing ever reads one back off a device.
extension TextureTypeToGpu on TextureType {
  gpu.TextureType toGpu() => switch (this) {
    TextureType.texture2D => gpu.TextureType.texture2D,
    TextureType.texture2DMultisample => gpu.TextureType.texture2DMultisample,
    TextureType.textureCube => gpu.TextureType.textureCube,
    TextureType.textureExternalOES => gpu.TextureType.textureExternalOES,
  };
}

/// Maps the engine's [TextureFormat] to `package:flutter_gpu`'s
/// `PixelFormat` — same values, different name on that side.
extension TextureFormatToGpu on TextureFormat {
  gpu.PixelFormat toGpu() => switch (this) {
    TextureFormat.unknown => gpu.PixelFormat.unknown,
    TextureFormat.a8UNormInt => gpu.PixelFormat.a8UNormInt,
    TextureFormat.r8UNormInt => gpu.PixelFormat.r8UNormInt,
    TextureFormat.r8g8UNormInt => gpu.PixelFormat.r8g8UNormInt,
    TextureFormat.r8g8b8a8UNormInt => gpu.PixelFormat.r8g8b8a8UNormInt,
    TextureFormat.r8g8b8a8UNormIntSRGB => gpu.PixelFormat.r8g8b8a8UNormIntSRGB,
    TextureFormat.b8g8r8a8UNormInt => gpu.PixelFormat.b8g8r8a8UNormInt,
    TextureFormat.b8g8r8a8UNormIntSRGB => gpu.PixelFormat.b8g8r8a8UNormIntSRGB,
    TextureFormat.r32g32b32a32Float => gpu.PixelFormat.r32g32b32a32Float,
    TextureFormat.r16g16b16a16Float => gpu.PixelFormat.r16g16b16a16Float,
    TextureFormat.r32Float => gpu.PixelFormat.r32Float,
    TextureFormat.s8UInt => gpu.PixelFormat.s8UInt,
    TextureFormat.d24UnormS8Uint => gpu.PixelFormat.d24UnormS8Uint,
    TextureFormat.d32FloatS8UInt => gpu.PixelFormat.d32FloatS8UInt,
    TextureFormat.bc1RGBAUNormInt => gpu.PixelFormat.bc1RGBAUNormInt,
    TextureFormat.bc1RGBAUNormIntSRGB => gpu.PixelFormat.bc1RGBAUNormIntSRGB,
    TextureFormat.bc3RGBAUNormInt => gpu.PixelFormat.bc3RGBAUNormInt,
    TextureFormat.bc3RGBAUNormIntSRGB => gpu.PixelFormat.bc3RGBAUNormIntSRGB,
    TextureFormat.bc5RGUNormInt => gpu.PixelFormat.bc5RGUNormInt,
    TextureFormat.bc7RGBAUNormInt => gpu.PixelFormat.bc7RGBAUNormInt,
    TextureFormat.bc7RGBAUNormIntSRGB => gpu.PixelFormat.bc7RGBAUNormIntSRGB,
    TextureFormat.etc2RGB8UNormInt => gpu.PixelFormat.etc2RGB8UNormInt,
    TextureFormat.etc2RGB8UNormIntSRGB => gpu.PixelFormat.etc2RGB8UNormIntSRGB,
    TextureFormat.etc2RGBA8UNormInt => gpu.PixelFormat.etc2RGBA8UNormInt,
    TextureFormat.etc2RGBA8UNormIntSRGB =>
      gpu.PixelFormat.etc2RGBA8UNormIntSRGB,
    TextureFormat.astc4x4LDR => gpu.PixelFormat.astc4x4LDR,
    TextureFormat.astc4x4LDRSRGB => gpu.PixelFormat.astc4x4LDRSRGB,
    TextureFormat.astc8x8LDR => gpu.PixelFormat.astc8x8LDR,
    TextureFormat.astc8x8LDRSRGB => gpu.PixelFormat.astc8x8LDRSRGB,
    TextureFormat.astc4x4HDR => gpu.PixelFormat.astc4x4HDR,
    TextureFormat.astc8x8HDR => gpu.PixelFormat.astc8x8HDR,
  };
}

/// Maps `package:flutter_gpu`'s `PixelFormat` back to the engine's
/// [TextureFormat].
extension TextureFormatFromGpu on gpu.PixelFormat {
  TextureFormat toEngine() => switch (this) {
    gpu.PixelFormat.unknown => TextureFormat.unknown,
    gpu.PixelFormat.a8UNormInt => TextureFormat.a8UNormInt,
    gpu.PixelFormat.r8UNormInt => TextureFormat.r8UNormInt,
    gpu.PixelFormat.r8g8UNormInt => TextureFormat.r8g8UNormInt,
    gpu.PixelFormat.r8g8b8a8UNormInt => TextureFormat.r8g8b8a8UNormInt,
    gpu.PixelFormat.r8g8b8a8UNormIntSRGB => TextureFormat.r8g8b8a8UNormIntSRGB,
    gpu.PixelFormat.b8g8r8a8UNormInt => TextureFormat.b8g8r8a8UNormInt,
    gpu.PixelFormat.b8g8r8a8UNormIntSRGB => TextureFormat.b8g8r8a8UNormIntSRGB,
    gpu.PixelFormat.r32g32b32a32Float => TextureFormat.r32g32b32a32Float,
    gpu.PixelFormat.r16g16b16a16Float => TextureFormat.r16g16b16a16Float,
    gpu.PixelFormat.r32Float => TextureFormat.r32Float,
    gpu.PixelFormat.s8UInt => TextureFormat.s8UInt,
    gpu.PixelFormat.d24UnormS8Uint => TextureFormat.d24UnormS8Uint,
    gpu.PixelFormat.d32FloatS8UInt => TextureFormat.d32FloatS8UInt,
    gpu.PixelFormat.bc1RGBAUNormInt => TextureFormat.bc1RGBAUNormInt,
    gpu.PixelFormat.bc1RGBAUNormIntSRGB => TextureFormat.bc1RGBAUNormIntSRGB,
    gpu.PixelFormat.bc3RGBAUNormInt => TextureFormat.bc3RGBAUNormInt,
    gpu.PixelFormat.bc3RGBAUNormIntSRGB => TextureFormat.bc3RGBAUNormIntSRGB,
    gpu.PixelFormat.bc5RGUNormInt => TextureFormat.bc5RGUNormInt,
    gpu.PixelFormat.bc7RGBAUNormInt => TextureFormat.bc7RGBAUNormInt,
    gpu.PixelFormat.bc7RGBAUNormIntSRGB => TextureFormat.bc7RGBAUNormIntSRGB,
    gpu.PixelFormat.etc2RGB8UNormInt => TextureFormat.etc2RGB8UNormInt,
    gpu.PixelFormat.etc2RGB8UNormIntSRGB => TextureFormat.etc2RGB8UNormIntSRGB,
    gpu.PixelFormat.etc2RGBA8UNormInt => TextureFormat.etc2RGBA8UNormInt,
    gpu.PixelFormat.etc2RGBA8UNormIntSRGB =>
      TextureFormat.etc2RGBA8UNormIntSRGB,
    gpu.PixelFormat.astc4x4LDR => TextureFormat.astc4x4LDR,
    gpu.PixelFormat.astc4x4LDRSRGB => TextureFormat.astc4x4LDRSRGB,
    gpu.PixelFormat.astc8x8LDR => TextureFormat.astc8x8LDR,
    gpu.PixelFormat.astc8x8LDRSRGB => TextureFormat.astc8x8LDRSRGB,
    gpu.PixelFormat.astc4x4HDR => TextureFormat.astc4x4HDR,
    gpu.PixelFormat.astc8x8HDR => TextureFormat.astc8x8HDR,
  };
}
