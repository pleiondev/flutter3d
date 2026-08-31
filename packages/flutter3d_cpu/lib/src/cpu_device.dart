/// A `GraphicsDevice` with no GPU behind it.
///
/// The third implementation, and the reason for it: two backends that agree
/// prove less than they seem to when both are hardware rasterisers driven by a
/// C API. This one shares nothing with either — no driver, no shading language,
/// no command buffer — so whatever the interface still assumes about graphics
/// hardware has to show up here.
///
/// It is also useful rather than only instructive. Rendering on this backend
/// needs no device, so the engine's frames can be checked under a plain
/// `flutter test` on the VM, in seconds, where the golden suite currently
/// drives an application for twelve minutes.
///
/// Split across a few files by cohesive concern, all re-exported from here:
/// [CpuShaderLibrary] and `CpuPipeline` are `cpu_shader_library.dart`;
/// [CpuEncoder] — the pass that records state and rasterises on `draw` — is
/// `cpu_encoder.dart`; the widget [present] returns is `cpu_frame_widget.dart`;
/// and the per-vertex attribute assembly instancing needs is
/// `cpu_vertex_fetch.dart`.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'cpu_encoder.dart';
import 'cpu_frame_widget.dart';
import 'cpu_shader.dart';
import 'cpu_shader_library.dart';

export 'cpu_encoder.dart';
export 'cpu_frame_widget.dart';
export 'cpu_shader_library.dart';
export 'cpu_vertex_fetch.dart';

/// The software backend.
final class CpuDevice implements GraphicsDevice {
  CpuDevice({required this.width, required this.height, required this.shaders});

  final int width;
  final int height;

  @override
  final CpuShaderLibrary shaders;

  /// What [present] shows: the last frame handed to it.
  CpuTexture? _presented;

  @override
  // The engine's own convention, and here it is a choice rather than a
  // constraint — nothing underneath has an opinion. Choosing the engine's
  // saves a matrix multiply per frame and, more to the point, means this
  // backend does not quietly become a second test of `toDepthRange`.
  DepthRange get depthRange => DepthRange.zeroToOne;

  @override
  // Row zero is the top, because that is where this backend puts it. There is
  // no framebuffer here to disagree with.
  FramebufferOrigin get framebufferOrigin => FramebufferOrigin.topLeft;

  @override
  TextureFormat get defaultColorFormat => TextureFormat.r8g8b8a8UNormInt;

  @override
  TextureFormat get defaultDepthStencilFormat => TextureFormat.d32FloatS8UInt;

  @override
  // Float everywhere internally, so this costs nothing and is not a lie: the
  // values really are kept beyond one.
  TextureFormat get hdrColorFormat => TextureFormat.r16g16b16a16Float;

  @override
  // No multisampling. Answering one rather than four is the difference between
  // a backend that says what it does and one whose pictures quietly differ.
  int get preferredSampleCount => 1;

  @override
  bool get supportsOffscreenMsaa => false;

  @override
  // Line *primitives* are drawn — debug geometry arrives as those. Wireframe
  // is a different request: it asks for triangles to be drawn as their edges,
  // which means clipping and joining edges this rasteriser has no path for.
  // Answering true and filling them instead would be the silent substitution
  // the contract exists to forbid.
  bool get supportsWireframe => false;

  @override
  // Both halves are here now: the chain is stored as whole textures and the
  // level is chosen from a per-triangle derivative. See `BoundTexture.sample`
  // for why the derivative is a parameter rather than a property of the
  // fragment, which is the one place this backend cannot imitate hardware.
  bool get supportsMipmaps => true;

  @override
  // Nothing to probe: a cube here is six arrays of floats and a table saying
  // which of them a direction lands on.
  bool get supportsCubeTextures => true;

  @override
  TextureHandle? createCubeTextureFromPixels({
    required int size,
    required TextureFormat format,
    required List<ByteData> faces,
    List<List<ByteData>>? mipLevels,
  }) {
    if (faces.length != 6) return null;

    CpuTexture? read(ByteData source, int side) {
      final need = side * side * 4;
      // **Exactly, not "at least".** The interface says null when a face is not
      // the size its description says, and the other two backends enforce it —
      // WebGL because `texSubImage2D` would read past the level, Impeller
      // because `overwrite` throws. This one accepted a longer buffer and used
      // its prefix, which turns a chain built with the wrong arithmetic into a
      // cube that loads and reflects noise.
      if (source.lengthInBytes != need) return null;
      final texture = CpuTexture(side, side, format);
      final bytes = source.buffer.asUint8List(source.offsetInBytes, need);
      for (var i = 0; i < need; i++) {
        texture.pixels[i] = bytes[i] / 255.0;
      }
      return texture;
    }

    final built = <CpuTexture>[];
    for (final face in faces) {
      final texture = read(face, size);
      if (texture == null) return null;
      built.add(texture);
    }

    // **A chain per face, not one chain for the cube.** Each face is sampled as
    // its own square, so the levels have to hang off the face that owns them;
    // hanging them off face zero would give five faces a chain belonging to the
    // sixth, which reads as a seam that moves with the roughness.
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chains = List<List<CpuTexture>>.generate(6, (_) => <CpuTexture>[]);
      var side = size;
      for (final level in mipLevels) {
        if (level.length != 6) return null;
        side = side > 1 ? side >> 1 : 1;
        for (var face = 0; face < 6; face++) {
          final texture = read(level[face], side);
          if (texture == null) return null;
          chains[face].add(texture);
        }
      }
      for (var face = 0; face < 6; face++) {
        built[face].levels = chains[face];
      }
    }

    // The handle's own texture is face zero, so anything that samples this as
    // an ordinary 2D texture gets +X rather than nothing. The six live beside
    // it, and `BoundTexture.sampleCube` is what reaches them.
    final cube = built[0]..faces = built;
    return TextureHandle(
      backend: cube,
      width: size,
      height: size,
      format: format,
      type: TextureType.textureCube,
    );
  }

  @override
  TextureHandle createTexture(RenderTargetSpec spec) => TextureHandle(
        backend: CpuTexture(spec.width, spec.height, spec.format),
        width: spec.width,
        height: spec.height,
        format: spec.format,
        sampleCount: 1,
        storageMode: spec.storageMode,
      );

  @override
  TextureHandle? createTextureFromPixels({
    required int width,
    required int height,
    required TextureFormat format,
    required ByteData pixels,
    List<ByteData>? mipLevels,
  }) {
    final expected = width * height * 4;
    if (pixels.lengthInBytes < expected) return null;
    final texture = CpuTexture(width, height, format);
    final bytes = pixels.buffer.asUint8List(pixels.offsetInBytes, expected);
    for (var i = 0; i < expected; i++) {
      texture.pixels[i] = bytes[i] / 255.0;
    }
    if (mipLevels != null && mipLevels.isNotEmpty) {
      final chain = <CpuTexture>[];
      var w = width;
      var h = height;
      for (final level in mipLevels) {
        w = w > 1 ? w >> 1 : 1;
        h = h > 1 ? h >> 1 : 1;
        final small = CpuTexture(w, h, format);
        final need = w * h * 4;
        if (level.lengthInBytes < need) return null;
        final from = level.buffer.asUint8List(level.offsetInBytes, need);
        for (var i = 0; i < need; i++) {
          small.pixels[i] = from[i] / 255.0;
        }
        chain.add(small);
      }
      texture.levels = chain;
    }
    return TextureHandle(
      backend: texture,
      width: width,
      height: height,
      format: format,
      sampleCount: 1,
      storageMode: StorageMode.devicePrivate,
    );
  }

  @override
  GeometryBuffer uploadGeometry(ByteData bytes, GeometryUsage usage) {
    // The usage is recorded rather than acted on: nothing here binds a buffer
    // to anything for life. Recorded anyway, because a backend that forgets
    // which it was told would pass the conformance check for the wrong reason.
    final copy = Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    return GeometryBuffer(
      backend: (bytes: ByteData.sublistView(copy), usage: usage),
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  @override
  PipelineHandle createPipeline(
    ShaderHandle vertex,
    ShaderHandle fragment, {
    VertexLayoutSpec? layout,
  }) {
    // Every format this backend can read is floats. The integer ones exist in
    // the vocabulary because flutter_gpu has them; a stage here receives one
    // `Float32List`, so a `uint32` attribute would have to be reinterpreted,
    // and reinterpreting it silently is how a joint index becomes 1.4e-45.
    if (layout != null) {
      for (final buffer in layout.buffers) {
        for (final attribute in buffer.attributes) {
          if (!attribute.format.name.startsWith('float')) {
            throw UnsupportedError(
              'attribute "${attribute.name}" is ${attribute.format.name}. This '
              'backend hands a vertex stage a list of floats, so it reads only '
              'the float formats.',
            );
          }
        }
      }
    }
    final v = (vertex.backend as CpuStage).vertex;
    final f = (fragment.backend as CpuStage).fragment;
    if (v == null || f == null) {
      throw StateError(
        'createPipeline("${vertex.name}", "${fragment.name}"): the stages are '
        'the wrong way round, or one of them is not the kind it is being used '
        'as.',
      );
    }
    return PipelineHandle(
      backend: CpuPipeline(v, f, layout),
      name: '${vertex.name}+${fragment.name}',
    );
  }

  @override
  void beginFrame() {
    // Nothing rotates here. Implemented as nothing, which is the answer the
    // contract asks for rather than the absence of one.
  }

  @override
  void onFrameComplete(void Function() whenDone) {
    // Straight away, and honestly: this backend rasterises on the calling
    // thread, so by the time anybody could ask, the frame is finished.
    whenDone();
  }

  @override
  CommandEncoder beginRenderPass(RenderPassDescriptor descriptor) =>
      CpuEncoder(descriptor);

  @override
  Future<ByteData?> readPixels(TextureHandle texture) async {
    final backend = texture.backend as CpuTexture;
    final out = Uint8List(backend.width * backend.height * 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = (backend.pixels[i].clamp(0.0, 1.0) * 255.0).round();
    }
    return ByteData.sublistView(out);
  }

  @override
  Widget present(
    TextureHandle frame, {
    BoxFit fit = BoxFit.fill,
    FilterQuality quality = FilterQuality.none,
  }) {
    _presented = frame.backend as CpuTexture;
    return CpuFrame(texture: _presented!, fit: fit, quality: quality);
  }

  /// A no-op, and honestly one: every texture and buffer this backend hands
  /// out is a plain Dart object — a [CpuTexture] wrapping a `Float32List`, a
  /// record wrapping a `ByteData` — with nothing external to release. The
  /// garbage collector already does the whole of what this method would do on
  /// a backend with a driver underneath it.
  @override
  void dispose() {}
}
