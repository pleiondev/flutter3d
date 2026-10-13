/// A kernel language kernel as a compute stage of the software
/// rasteriser: the CPU placement — 1.0.
///
/// The kernel is read and translated to Dart by `flutter3d_shaders`, the
/// same parse WebGPU and the wgpu sidecar translate to WGSL; this file only
/// hands it what the encoder bound, by name: storage buffers as their
/// bytes, a sampled texture and a storage texture through the two small
/// adapters below.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/kernel.dart';

import 'cpu_shader.dart';
import 'cpu_texel_codec.dart' show settleTexel;

/// A kernel's compute stage. A reload points [kernel] at the new source
/// under the handle already handed out.
final class CpuKernelStage extends CpuComputeShader with CpuStorageReader {
  CpuKernelStage(this.source, this.kernel);

  /// The text the kernel was read from, so a reload whose source did not
  /// change keeps the stage as it is.
  String source;

  /// What runs.
  DartKernel kernel;

  @override
  (int, int, int) get workgroupSize {
    final size = kernel.kernel.workgroupSize;
    return (size.x, size.y, size.z);
  }

  /// The buffers and images the kernel declares: a bind of anything else
  /// answers false, as on a backend that reflects its stages.
  @override
  Set<String> get storageBindings => <String>{
    for (final b in kernel.kernel.bindings)
      if (b.kind != KernelBindingKind.texture) b.name,
  };

  @override
  void runWorkgroup((int, int, int) group, CpuComputeBindings bindings) {
    kernel.runWorkgroup(
      group,
      KernelInputs(
        buffers: bindings.storage,
        textures: <String, KernelTexture>{
          for (final MapEntry(:key, :value) in bindings.textures.entries)
            key: _CpuKernelTexture(value.texture),
        },
        images: <String, KernelImage>{
          for (final MapEntry(:key, :value) in bindings.storageTextures.entries)
            key: _CpuKernelImage(value),
        },
      ),
    );
  }
}

/// The base level of a texture, read texel by texel as a kernel's `load`.
final class _CpuKernelTexture extends KernelTexture {
  _CpuKernelTexture(this._texture);

  final CpuTexture _texture;

  @override
  int get width => _texture.width;

  @override
  int get height => _texture.height;

  @override
  void load(int x, int y, Float32List rgba) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      rgba.fillRange(0, 4, 0);
      return;
    }
    final at = (y * width + x) * 4;
    final p = _texture.pixels;
    for (var c = 0; c < 4; c++) {
      rgba[c] = p[at + c];
    }
  }
}

/// A storage texture written texel by texel as a kernel's `store`: an
/// RGBA8 texel rounded to its level as a GPU rounds it, any other format
/// as its own codec keeps it.
final class _CpuKernelImage extends KernelImage {
  _CpuKernelImage(this._image);

  final CpuStorageTexture _image;

  @override
  int get width => _image.width;

  @override
  int get height => _image.height;

  @override
  void store(int x, int y, Float32List rgba) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final plane = _image.planes.first;
    final at = (y * plane.width + x) * 4;
    final p = plane.pixels;
    final unorm8 =
        _image.format == TextureFormat.r8g8b8a8UNormInt ||
        _image.format == TextureFormat.b8g8r8a8UNormInt;
    for (var c = 0; c < 4; c++) {
      p[at + c] = unorm8 ? unormValue(unormLevel(rgba[c])) : rgba[c];
    }
    if (!unorm8) settleTexel(_image.format, p, at);
  }
}

/// The kernels [bundle] carries, as stages: [kept] reused where the source
/// did not change. Throws [ShaderBundleException] naming the bundle for a
/// kernel that does not read.
Map<String, CpuKernelStage> cpuKernelStages(
  ShaderBundle bundle,
  Map<String, CpuKernelStage> kept,
) => <String, CpuKernelStage>{
  for (final MapEntry(key: name, value: kernel) in kernelsOf(bundle).entries)
    name: switch (kept[name]) {
      final previous? when previous.source == kernel.source => previous,
      _ => CpuKernelStage(kernel.source, kernel.toDartKernel()),
    },
};
