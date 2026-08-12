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
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// A library of Dart stages, by the names the engine asks for.
final class CpuShaderLibrary implements ShaderLibrary {
  CpuShaderLibrary(this.stages);

  final Map<String, CpuStage> stages;

  @override
  ShaderHandle? operator [](String name) {
    final stage = stages[name];
    if (stage == null) return null;
    return ShaderHandle(backend: stage, name: name);
  }
}

/// A vertex and a fragment stage, paired.
final class _CpuPipeline {
  const _CpuPipeline(this.vertex, this.fragment);
  final CpuVertexShader vertex;
  final CpuFragmentShader fragment;
}

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
  // A software rasteriser could draw lines, and does not yet. Answering true
  // and filling the triangles would be the silent substitution the contract
  // exists to forbid.
  bool get supportsWireframe => false;

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
  }) {
    final expected = width * height * 4;
    if (pixels.lengthInBytes < expected) return null;
    final texture = CpuTexture(width, height, format);
    final bytes = pixels.buffer.asUint8List(pixels.offsetInBytes, expected);
    for (var i = 0; i < expected; i++) {
      texture.pixels[i] = bytes[i] / 255.0;
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
  PipelineHandle createPipeline(ShaderHandle vertex, ShaderHandle fragment) {
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
      backend: _CpuPipeline(v, f),
      name: '${vertex.name}+${fragment.name}',
    );
  }

  @override
  void beginFrame() {
    // Nothing rotates here. Implemented as nothing, which is the answer the
    // contract asks for rather than the absence of one.
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
    return _CpuFrame(texture: _presented!, fit: fit, quality: quality);
  }
}

/// Shows a [CpuTexture] by decoding it into an image.
///
/// The round trip this backend cannot avoid and the other two can: the pixels
/// are already in CPU memory, so getting them onto the screen means handing
/// them to Flutter, which is what `decodeImageFromPixels` is. On a GPU backend
/// the same journey is what made `imageOf` the wrong contract.
final class _CpuFrame extends StatefulWidget {
  const _CpuFrame({
    required this.texture,
    required this.fit,
    required this.quality,
  });

  final CpuTexture texture;
  final BoxFit fit;
  final FilterQuality quality;

  @override
  State<_CpuFrame> createState() => _CpuFrameState();
}

class _CpuFrameState extends State<_CpuFrame> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_CpuFrame old) {
    super.didUpdateWidget(old);
    if (!identical(old.texture, widget.texture)) _decode();
  }

  void _decode() {
    final t = widget.texture;
    final bytes = Uint8List(t.width * t.height * 4);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (t.pixels[i].clamp(0.0, 1.0) * 255.0).round();
    }
    ui.decodeImageFromPixels(
      bytes,
      t.width,
      t.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (mounted) setState(() => _image = image);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.shrink();
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: widget.quality,
    );
  }
}

/// Records state and rasterises on `draw`.
final class CpuEncoder implements CommandEncoder {
  CpuEncoder(this._descriptor) {
    for (final color in _descriptor.colors) {
      final texture = color.texture.backend as CpuTexture;
      if (color.loadAction != LoadAction.clear) continue;
      final value = color.clearValue ?? Vector4.zero();
      // The whole attachment, whatever the scissor says. Here that is the
      // natural way to write it, which is the point of the rule being stated
      // rather than inherited from what one API happened to do.
      for (var i = 0; i < texture.pixels.length; i += 4) {
        texture.pixels[i] = value.x;
        texture.pixels[i + 1] = value.y;
        texture.pixels[i + 2] = value.z;
        texture.pixels[i + 3] = value.w;
      }
    }
    final depth = _descriptor.depth;
    if (depth != null) {
      final texture = depth.texture.backend as CpuTexture;
      texture.depthBuffer().fillRange(0, texture.width * texture.height,
          depth.clearValue);
      _depthTarget = texture;
    }
  }

  final RenderPassDescriptor _descriptor;
  CpuTexture? _depthTarget;

  ScreenRect? _viewport;
  ScreenRect? _scissor;
  PrimitiveType _primitive = PrimitiveType.triangle;
  CullMode _cull = CullMode.none;
  WindingOrder _winding = WindingOrder.counterClockwise;
  bool _depthWrite = true;
  CompareFunction _depthCompare = CompareFunction.less;
  BlendState? _blend;
  _CpuPipeline? _pipeline;

  ByteData? _vertices;
  int _vertexCount = 0;
  ByteData? _indices;
  IndexType _indexType = IndexType.int16;
  int _indexCount = 0;

  final Map<String, Map<String, Float32List>> _blocks =
      <String, Map<String, Float32List>>{};
  final Map<String, CpuTexture> _textures = <String, CpuTexture>{};

  @override
  void setViewport(ScreenRect rect) => _viewport = rect;

  @override
  void setScissor(ScreenRect rect) => _scissor = rect;

  @override
  void setPrimitiveType(PrimitiveType type) => _primitive = type;

  @override
  void setPolygonMode(PolygonMode mode) {
    if (mode == PolygonMode.line) {
      throw UnsupportedError(
        'this backend answers false to supportsWireframe and means it. Filling '
        'the triangles instead would be a picture nobody asked for.',
      );
    }
  }

  @override
  void setCullMode(CullMode mode) => _cull = mode;

  @override
  void setWindingOrder(WindingOrder order) => _winding = order;

  @override
  void setDepthWrite(bool enabled) => _depthWrite = enabled;

  @override
  void setDepthCompare(CompareFunction compare) => _depthCompare = compare;

  @override
  void setBlend(BlendState? state, {int attachment = 0}) => _blend = state;

  @override
  void bindPipeline(PipelineHandle pipeline) =>
      _pipeline = pipeline.backend as _CpuPipeline;

  @override
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _vertices = backend.bytes;
    _vertexCount = vertexCount;
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount) {
    _vertices = bytes;
    _vertexCount = vertexCount;
  }

  @override
  void bindIndexBuffer(GeometryBuffer buffer, IndexType type, int indexCount) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _indices = backend.bytes;
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  void bindIndexData(ByteData bytes, IndexType type, int indexCount) {
    _indices = bytes;
    _indexType = type;
    _indexCount = indexCount;
  }

  @override
  bool bindUniformBlock(
    ShaderHandle shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    _blocks[blockName] = members;
    return true;
  }

  @override
  void bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerOptions? sampler,
  }) =>
      _textures[slot] = texture.backend as CpuTexture;

  @override
  void clearBindings() {
    _blocks.clear();
    _textures.clear();
  }

  @override
  void submit() {
    // Nothing deferred, so nothing to flush. Draws happened as they arrived,
    // which is a different execution model from a command buffer and one the
    // contract allows: it promises passes execute in submission order, not
    // that anything is buffered.
  }

  @override
  void draw() {
    final pipeline = _pipeline;
    final vertices = _vertices;
    if (pipeline == null || vertices == null) return;
    if (_primitive != PrimitiveType.triangle) return;
    if (_descriptor.colors.isEmpty) return;

    final target = _descriptor.colors.first.texture.backend as CpuTexture;
    final view = _viewport ??
        ScreenRect(x: 0, y: 0, width: target.width, height: target.height);

    final stride = _floatsPerVertex(vertices, _vertexCount);
    final floats = vertices.buffer
        .asFloat32List(vertices.offsetInBytes, vertices.lengthInBytes ~/ 4);
    final bindings = ShaderBindings(_blocks, _textures);
    final varyingCount = pipeline.vertex.varyingCount;

    final clip = <Vector4>[Vector4.zero(), Vector4.zero(), Vector4.zero()];
    final varyings = <Float32List>[
      Float32List(varyingCount),
      Float32List(varyingCount),
      Float32List(varyingCount),
    ];
    final attributes = Float32List(stride);

    final triangles = _indices != null ? _indexCount ~/ 3 : _vertexCount ~/ 3;
    for (var t = 0; t < triangles; t++) {
      for (var corner = 0; corner < 3; corner++) {
        final vertex = _indices != null
            ? _indexAt(t * 3 + corner)
            : t * 3 + corner;
        final base = vertex * stride;
        if (base + stride > floats.length) return;
        for (var f = 0; f < stride; f++) {
          attributes[f] = floats[base + f];
        }
        clip[corner] = pipeline.vertex.run(attributes, bindings, varyings[corner]);
      }
      _rasterise(pipeline, target, view, clip, varyings, varyingCount, bindings);
    }
  }

  /// How many floats one vertex is, from the buffer and the count.
  int _floatsPerVertex(ByteData vertices, int count) =>
      count == 0 ? 0 : (vertices.lengthInBytes ~/ 4) ~/ count;

  int _indexAt(int i) => _indexType == IndexType.int16
      ? _indices!.getUint16(i * 2, Endian.little)
      : _indices!.getUint32(i * 4, Endian.little);

  void _rasterise(
    _CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    // No clipping against the near plane: a triangle with any vertex behind the
    // eye is dropped whole. Crude, and honest about it — the alternative is a
    // clipper, and nothing here yet needs one.
    for (final c in clip) {
      if (c.w <= 1e-6) return;
    }

    final sx = <double>[0, 0, 0];
    final sy = <double>[0, 0, 0];
    final sz = <double>[0, 0, 0];
    final invW = <double>[0, 0, 0];
    for (var i = 0; i < 3; i++) {
      invW[i] = 1.0 / clip[i].w;
      final ndcX = clip[i].x * invW[i];
      final ndcY = clip[i].y * invW[i];
      sz[i] = clip[i].z * invW[i];
      // NDC to the viewport, with +Y up in clip space and row zero at the top.
      sx[i] = view.x + (ndcX * 0.5 + 0.5) * view.width;
      sy[i] = view.y + (0.5 - ndcY * 0.5) * view.height;
    }

    var area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
    if (area == 0.0) return;

    // Winding is measured in window space, where y runs down, so a
    // counter-clockwise triangle has negative area here.
    final frontFacing =
        _winding == WindingOrder.counterClockwise ? area < 0 : area > 0;
    if (_cull == CullMode.backFace && !frontFacing) return;
    if (_cull == CullMode.frontFace && frontFacing) return;

    final clipRect = _scissor;
    var minX = sx.reduce((a, b) => a < b ? a : b).floor();
    var maxX = sx.reduce((a, b) => a > b ? a : b).ceil();
    var minY = sy.reduce((a, b) => a < b ? a : b).floor();
    var maxY = sy.reduce((a, b) => a > b ? a : b).ceil();
    minX = minX.clamp(clipRect?.x ?? view.x, target.width - 1);
    maxX = maxX.clamp(0, ((clipRect?.x ?? view.x) + (clipRect?.width ?? view.width)) - 1);
    minY = minY.clamp(clipRect?.y ?? view.y, target.height - 1);
    maxY = maxY.clamp(0, ((clipRect?.y ?? view.y) + (clipRect?.height ?? view.height)) - 1);

    final depth = _depthTarget?.depthBuffer();
    final interpolated = Float32List(varyingCount);

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        var w0 = (sx[1] - sx[0]) * (py - sy[0]) - (sy[1] - sy[0]) * (px - sx[0]);
        var w1 = (sx[2] - sx[1]) * (py - sy[1]) - (sy[2] - sy[1]) * (px - sx[1]);
        var w2 = (sx[0] - sx[2]) * (py - sy[2]) - (sy[0] - sy[2]) * (px - sx[2]);
        if (area > 0) {
          if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        } else {
          if (w0 > 0 || w1 > 0 || w2 > 0) continue;
        }

        // Barycentric, named for the corner each weight belongs to rather than
        // for the edge it came from — the two are rotated by one, which is a
        // classic way to get a picture that is almost right.
        final b0 = w1 / area;
        final b1 = w2 / area;
        final b2 = w0 / area;

        final z = sz[0] * b0 + sz[1] * b1 + sz[2] * b2;
        final index = y * target.width + x;
        if (depth != null && !_depthPasses(z, depth[index])) continue;

        // Perspective-correct: interpolate over 1/w and divide back.
        final iw = invW[0] * b0 + invW[1] * b1 + invW[2] * b2;
        for (var v = 0; v < varyingCount; v++) {
          interpolated[v] = (varyings[0][v] * invW[0] * b0 +
                  varyings[1][v] * invW[1] * b1 +
                  varyings[2][v] * invW[2] * b2) /
              iw;
        }

        final colour = pipeline.fragment.run(interpolated, bindings);
        if (colour == null) continue;

        final at = index * 4;
        if (_blend == null) {
          target.pixels[at] = colour.x;
          target.pixels[at + 1] = colour.y;
          target.pixels[at + 2] = colour.z;
          target.pixels[at + 3] = colour.w;
        } else {
          // Only the two the engine uses: source-over and additive. A general
          // blend equation nothing asks for would be a guess about a call site.
          final srcAlpha = _blend!.sourceColorFactor == BlendFactor.sourceAlpha
              ? colour.w
              : 1.0;
          final dstFactor =
              _blend!.destinationColorFactor == BlendFactor.oneMinusSourceAlpha
                  ? 1.0 - colour.w
                  : 1.0;
          target.pixels[at] = colour.x * srcAlpha + target.pixels[at] * dstFactor;
          target.pixels[at + 1] =
              colour.y * srcAlpha + target.pixels[at + 1] * dstFactor;
          target.pixels[at + 2] =
              colour.z * srcAlpha + target.pixels[at + 2] * dstFactor;
          target.pixels[at + 3] =
              colour.w * srcAlpha + target.pixels[at + 3] * dstFactor;
        }

        if (depth != null && _depthWrite) depth[index] = z;
      }
    }
  }

  bool _depthPasses(double incoming, double stored) => switch (_depthCompare) {
        CompareFunction.never => false,
        CompareFunction.always => true,
        CompareFunction.less => incoming < stored,
        CompareFunction.lessEqual => incoming <= stored,
        CompareFunction.greater => incoming > stored,
        CompareFunction.greaterEqual => incoming >= stored,
        CompareFunction.equal => incoming == stored,
        CompareFunction.notEqual => incoming != stored,
      };
}
