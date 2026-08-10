import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import '../gpu/gpu_formats.dart';
import '../graphics/formats.dart';

/// A texture generated in code.
///
/// An abstraction rather than a set of free functions returning [ByteData], so
/// that "which texture" is a value the demo can hold and the upload path is
/// written once. [upload] is the only place that touches the GPU, which keeps
/// [encode] testable on its own.
abstract class ProceduralTexture {
  const ProceduralTexture();

  /// Edge length in pixels; procedural textures here are square.
  int get size;

  /// RGBA8 pixels, row-major from the top-left.
  ByteData encode();

  /// Uploads the pixels as a host-visible GPU texture.
  gpu.Texture upload() {
    final texture = gpu.gpuContext.createTexture(
      StorageMode.hostVisible.toGpu(),
      size,
      size,
      format: TextureFormat.r8g8b8a8UNormInt.toGpu(),
      // The data is uploaded from the host, so use the host coordinate system.
      coordinateSystem: TextureCoordinateSystem.uploadFromHost.toGpu(),
    );
    texture.overwrite(encode());
    return texture;
  }
}

/// A single flat colour.
///
/// A 1x1 white instance stands in for a missing base-colour texture: a shader
/// that declares a sampler must have something bound to it, so "no texture" has
/// to be expressed as a neutral texture rather than an absent binding.
class SolidColorTexture extends ProceduralTexture {
  const SolidColorTexture(this.color, {this.size = 1});

  /// Non-linear (sRGB-encoded) RGBA in the 0..1 range, matching how texture
  /// pixels are authored.
  final Vector4 color;

  @override
  final int size;

  static SolidColorTexture get white =>
      SolidColorTexture(Vector4(1.0, 1.0, 1.0, 1.0));

  /// The neutral tangent-space normal, `(0, 0, 1)` encoded into 0..1.
  ///
  /// What the renderer binds when a material has no normal map. Sampling it
  /// perturbs nothing, so the shader needs no branch and the engine needs no
  /// "has a normal map" flag to keep in step with the GLSL.
  static SolidColorTexture get flatNormal =>
      SolidColorTexture(Vector4(0.5, 0.5, 1.0, 1.0));

  @override
  ByteData encode() {
    final bytes = Uint8List(size * size * 4);
    final r = (color.x.clamp(0.0, 1.0) * 255).round();
    final g = (color.y.clamp(0.0, 1.0) * 255).round();
    final b = (color.z.clamp(0.0, 1.0) * 255).round();
    final a = (color.w.clamp(0.0, 1.0) * 255).round();
    for (var i = 0; i < bytes.length; i += 4) {
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = a;
    }
    return bytes.buffer.asByteData();
  }
}

/// Two-tone checkerboard.
///
/// Used for procedural shapes that carry no material of their own, because a flat
/// colour is exactly where UV mistakes hide.
///
/// flutter_gpu exposes no compressed pixel formats and no mip levels, so this is
/// plain RGBA8 with a single level. Without mips, minification aliases: visible
/// as shimmer on faces seen at a grazing angle.
class CheckerboardTexture extends ProceduralTexture {
  const CheckerboardTexture({
    this.size = 64,
    this.cell = 8,
    this.light = 0xE8E2D4,
    this.dark = 0x6A6E7A,
  });

  @override
  final int size;

  /// Edge length of one square, in pixels.
  final int cell;

  /// 0xRRGGBB. The dark tone is mid-grey rather than near-black so that shading
  /// stays readable on it once the scene is lit.
  final int light;
  final int dark;

  @override
  ByteData encode() {
    final bytes = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final isLight = ((x ~/ cell) + (y ~/ cell)).isEven;
        final rgb = isLight ? light : dark;
        final o = (y * size + x) * 4;
        bytes[o] = (rgb >> 16) & 0xFF;
        bytes[o + 1] = (rgb >> 8) & 0xFF;
        bytes[o + 2] = rgb & 0xFF;
        bytes[o + 3] = 0xFF;
      }
    }
    return bytes.buffer.asByteData();
  }
}
