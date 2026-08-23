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

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
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
  const _CpuPipeline(this.vertex, this.fragment, this.layout);
  final CpuVertexShader vertex;
  final CpuFragmentShader fragment;

  /// Where the vertex stage's inputs come from, or null to read one
  /// interleaved buffer in shader order — see `_drawOnce`.
  final VertexLayoutSpec? layout;
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
  }) {
    if (faces.length != 6) return null;
    final expected = size * size * 4;

    final built = <CpuTexture>[];
    for (final face in faces) {
      if (face.lengthInBytes < expected) return null;
      final texture = CpuTexture(size, size, format);
      final bytes = face.buffer.asUint8List(face.offsetInBytes, expected);
      for (var i = 0; i < expected; i++) {
        texture.pixels[i] = bytes[i] / 255.0;
      }
      built.add(texture);
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
      backend: _CpuPipeline(v, f, layout),
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
  // False, matching a fresh `flutter_gpu` RenderPass, whose
  // `DepthAttachmentDescriptor` starts with writes disabled. That default is a
  // property of the descriptor rather than of the setter 3.47 fixed, so it is
  // unchanged — and `depth_write_test.dart` still pins it, because a default
  // nobody states is a default that drifts.
  bool _depthWrite = false;
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
  final Map<String, BoundTexture> _textures = <String, BoundTexture>{};

  /// Whether anything bound to this pass has levels to choose between.
  ///
  /// Asked per triangle rather than cached per bind because the bindings change
  /// inside a pass and the map is small — almost every draw here binds two
  /// textures or none. The point is only to keep the gradient arithmetic off
  /// the twenty-seven scenes that have no mip chain anywhere in them.
  bool _hasMippedTexture() {
    for (final bound in _textures.values) {
      if (bound.texture.levels != null) return true;
    }
    return false;
  }

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

  /// Turns depth writes on or off, which is all it has ever meant to say.
  ///
  /// For most of this backend's life it ignored its argument and turned writes
  /// on regardless, because `flutter_gpu`'s native setter assigned the literal
  /// `true` and a software backend that behaved correctly would have put the
  /// two backends five and ten percent apart on the particle scenes — a gap
  /// loud enough to hide a real regression behind. flutter_gpu 3.47 assigns the
  /// argument, so the mirror is gone.
  ///
  /// **The sentence worth keeping from all that**: when a backend has to choose
  /// between being right and being comparable, comparable wins, and the choice
  /// gets a test that fails the day it stops being necessary. That is what
  /// `test/depth_write_test.dart` was for, and it is why this line changed on
  /// the day the SDK did rather than months later.
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
  void bindVertexBuffer(GeometryBuffer buffer, int vertexCount,
      {int slot = 0}) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _bindSlot(slot, backend.bytes, vertexCount);
  }

  @override
  void bindVertexData(ByteData bytes, int vertexCount, {int slot = 0}) =>
      _bindSlot(slot, bytes, vertexCount);

  /// Slot zero stays in [_vertices] and the rest go in [_slots].
  ///
  /// Two fields rather than one map because slot zero is every draw this engine
  /// has ever made and the map would be allocated for all of them to hold one
  /// entry. The layout-less path never looks at [_slots] at all.
  void _bindSlot(int slot, ByteData bytes, int count) {
    if (slot == 0) {
      _vertices = bytes;
      _vertexCount = count;
      return;
    }
    (_slots ??= <int, ByteData>{})[slot] = bytes;
  }

  Map<int, ByteData>? _slots;

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
      // linearRepeat for a null sampler, which is now written down in
      // `CommandEncoder.bindTexture` — it was not, and this backend picked the
      // constructor's own defaults instead, nearest and clamped. Both hardware
      // backends had independently chosen linearRepeat, so the two agreed and
      // the rule stayed unstated until a third implementation read the
      // interface and answered differently. It cost two percent of every
      // textured golden and looked like a rendering bug.
      _textures[slot] = BoundTexture(texture.backend as CpuTexture,
          sampler ?? SamplerOptions.linearRepeat);

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
  void draw({int instanceCount = 1}) {
    // Honestly, and to no advantage — which is the point. A scene the software
    // backend refuses to draw is a scene with no cross-backend check, and the
    // two most expensive bugs this repository has found were both found by
    // exactly that check.
    //
    // With no attribute stepping per instance there is nothing to vary yet, so
    // every repetition puts the same triangles in the same places. That is not
    // a stub: it is what an instanced draw of geometry with no per-instance
    // attributes means on any backend. The instance *index* arrives with the
    // vertex layouts that give a stage something to read it for.
    for (var instance = 0; instance < instanceCount; instance++) {
      _drawOnce(instance);
    }
  }

  void _drawOnce(int instance) {
    final pipeline = _pipeline;
    final vertices = _vertices;
    if (pipeline == null || vertices == null) return;
    if (_descriptor.colors.isEmpty) return;
    if (_primitive != PrimitiveType.triangle &&
        _primitive != PrimitiveType.line) {
      throw UnsupportedError(
        'this backend rasterises triangles and lines. $_primitive would have '
        'to be drawn as something else, and drawing a primitive as a '
        'different one is how a picture comes back plausible and wrong.',
      );
    }

    final target = _descriptor.colors.first.texture.backend as CpuTexture;
    final view = _viewport ??
        ScreenRect(x: 0, y: 0, width: target.width, height: target.height);

    final layout = pipeline.layout;
    final fetch = layout == null
        ? _PackedFetch(vertices, _floatsPerVertex(vertices, _vertexCount))
        : _LayoutFetch.build(layout, vertices, _slots, instance);
    final stride = fetch.floatsPerVertex;
    final bindings = ShaderBindings(_blocks, _textures);
    final varyingCount = pipeline.vertex.varyingCount;

    final clip = <Vector4>[Vector4.zero(), Vector4.zero(), Vector4.zero()];
    final varyings = <Float32List>[
      Float32List(varyingCount),
      Float32List(varyingCount),
      Float32List(varyingCount),
    ];
    final attributes = Float32List(stride);

    final perPrimitive = _primitive == PrimitiveType.line ? 2 : 3;
    final count = _indices != null
        ? _indexCount ~/ perPrimitive
        : _vertexCount ~/ perPrimitive;

    for (var t = 0; t < count; t++) {
      for (var corner = 0; corner < perPrimitive; corner++) {
        final vertex = _indices != null
            ? _indexAt(t * perPrimitive + corner)
            : t * perPrimitive + corner;
        if (!fetch.into(attributes, vertex)) return;
        clip[corner] = pipeline.vertex.run(attributes, bindings, varyings[corner]);
      }
      if (perPrimitive == 2) {
        _rasteriseLine(
            pipeline, target, view, clip, varyings, varyingCount, bindings);
      } else {
        _rasterise(
            pipeline, target, view, clip, varyings, varyingCount, bindings);
      }
    }
  }

  /// One line, a pixel wide.
  ///
  /// Bresenham on the window-space endpoints, with depth and the varyings
  /// interpolated along the run. Width is one and there is no cap or join:
  /// `PrimitiveType.line` in this engine draws debug geometry — bounds, axes,
  /// light gizmos — and a wide line would have to invent a joining rule that
  /// nothing here specifies.
  ///
  /// Deliberately separate from the triangle path rather than a degenerate
  /// case of it. A zero-area triangle has no barycentric coordinates, so the
  /// shared version would divide by zero and the clever fix for that is where
  /// a rasteriser stops being readable.
  void _rasteriseLine(
    _CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    for (var i = 0; i < 2; i++) {
      if (clip[i].w <= 1e-6) return;
    }

    final sx = <double>[0, 0];
    final sy = <double>[0, 0];
    final sz = <double>[0, 0];
    final invW = <double>[0, 0];
    for (var i = 0; i < 2; i++) {
      invW[i] = 1.0 / clip[i].w;
      sx[i] = view.x + (clip[i].x * invW[i] * 0.5 + 0.5) * view.width;
      sy[i] = view.y + (0.5 - clip[i].y * invW[i] * 0.5) * view.height;
      sz[i] = clip[i].z * invW[i];
    }

    final dx = sx[1] - sx[0];
    final dy = sy[1] - sy[0];
    final steps = math.max(dx.abs(), dy.abs()).ceil();
    if (steps <= 0) return;

    final depth = _depthTarget?.depthBuffer();
    final interpolated = Float32List(varyingCount);
    final context = FragmentContext();

    // Screen-space gradients, once for the whole triangle, and only when a
    // bound texture actually has levels to choose between. Solved from the
    // three window positions and the three varying values: the standard
    // two-by-two system whose determinant is the signed area already computed
    // above.
    if (_hasMippedTexture()) {
      final det =
          (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
      if (det != 0.0) {
        final inv = 1.0 / det;
        final ddx = context.ddx = Float32List(varyingCount);
        final ddy = context.ddy = Float32List(varyingCount);
        for (var k = 0; k < varyingCount; k++) {
          final v0 = varyings[0][k];
          final d1 = varyings[1][k] - v0;
          final d2 = varyings[2][k] - v0;
          ddx[k] = (d1 * (sy[2] - sy[0]) - d2 * (sy[1] - sy[0])) * inv;
          ddy[k] = (d2 * (sx[1] - sx[0]) - d1 * (sx[2] - sx[0])) * inv;
        }
      }
    }
    final scissor = _scissor;

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final x = (sx[0] + dx * t).floor();
      final y = (sy[0] + dy * t).floor();
      if (x < 0 || y < 0 || x >= target.width || y >= target.height) continue;
      if (scissor != null &&
          (x < scissor.x ||
              y < scissor.y ||
              x >= scissor.x + scissor.width ||
              y >= scissor.y + scissor.height)) {
        continue;
      }

      final z = sz[0] + (sz[1] - sz[0]) * t;
      final index = y * target.width + x;
      if (depth != null && !_depthPasses(z, depth[index])) continue;

      final iw = invW[0] + (invW[1] - invW[0]) * t;
      for (var v = 0; v < varyingCount; v++) {
        interpolated[v] =
            (varyings[0][v] * invW[0] * (1 - t) + varyings[1][v] * invW[1] * t) /
                iw;
      }

      context.coord.setValues(x + 0.5, y + 0.5, z, iw);
      context.surface = null;
      final colour = pipeline.fragment.run(interpolated, bindings, context);
      if (colour == null) continue;

      final at = index * 4;
      target.pixels[at] = colour.x;
      target.pixels[at + 1] = colour.y;
      target.pixels[at + 2] = colour.z;
      target.pixels[at + 3] = colour.w;
      if (depth != null && _depthWrite) depth[index] = z;
    }
  }

  /// How many floats one vertex is, from the buffer and the count.
  int _floatsPerVertex(ByteData vertices, int count) =>
      count == 0 ? 0 : (vertices.lengthInBytes ~/ 4) ~/ count;

  int _indexAt(int i) => _indexType == IndexType.int16
      ? _indices!.getUint16(i * 2, Endian.little)
      : _indices!.getUint32(i * 4, Endian.little);

  /// Smallest `w` a vertex may have and still be divided by.
  static const double _nearEpsilon = 1e-5;

  /// Clips against the near plane and rasterises what survives.
  ///
  /// The earlier version of this dropped any triangle with a vertex behind the
  /// eye, with a comment saying nothing needed a clipper yet. Something did:
  /// `cube-shadow-gap` widens its ground plane to five and a half radii —
  /// every other scene uses three — so one corner of it crosses behind the
  /// camera, both of its triangles were discarded, and the golden came back a
  /// teapot floating in black with no floor and no shadow under it. The
  /// picture did not look like a clipping bug. It looked like the ground had
  /// not been added to the scene.
  ///
  /// Sutherland-Hodgman against `w = _nearEpsilon`, which is the only plane
  /// worth clipping here: the others merely waste fragments the scissor and
  /// the bounding box already reject, while this one divides by a number at or
  /// below zero and turns the projection inside out.
  void _rasterise(
    _CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
    var behind = 0;
    for (final c in clip) {
      if (c.w <= _nearEpsilon) behind++;
    }
    if (behind == 3) return;
    if (behind == 0) {
      _rasteriseTriangle(
          pipeline, target, view, clip, varyings, varyingCount, bindings);
      return;
    }

    final poly = <Vector4>[];
    final polyVaryings = <Float32List>[];
    for (var i = 0; i < 3; i++) {
      final j = (i + 1) % 3;
      final a = clip[i];
      final b = clip[j];
      final aIn = a.w > _nearEpsilon;
      final bIn = b.w > _nearEpsilon;
      if (aIn) {
        poly.add(a);
        polyVaryings.add(varyings[i]);
      }
      if (aIn != bIn) {
        // Where the edge crosses the plane. Linear in clip space, which is
        // where it is genuinely linear — interpolating after the divide is the
        // classic way to get a seam that moves as the camera does.
        final t = (_nearEpsilon - a.w) / (b.w - a.w);
        final cutVertex = a + (b - a) * t;
        // Say where it is rather than trusting the arithmetic that put it
        // there. By construction this vertex lies *on* the plane, but `Vector4`
        // is float32-backed and the interpolation rounds — sometimes to a hair
        // below the plane, and sometimes to exactly zero. Dividing x by that
        // zero gives infinity, and the bounding box's `ceil()` throws
        // "Infinity or NaN toInt" from inside a rasteriser, which is a long way
        // from where anybody would look.
        //
        // Found by pointing a camera at a level's floor from three metres up:
        // one brush a hundred and twenty metres across is one pair of triangles
        // straddling the eye, and every frame from inside such a level crashed.
        cutVertex.w = _nearEpsilon;
        poly.add(cutVertex);
        final cut = Float32List(varyingCount);
        for (var k = 0; k < varyingCount; k++) {
          cut[k] = varyings[i][k] + (varyings[j][k] - varyings[i][k]) * t;
        }
        polyVaryings.add(cut);
      }
    }
    if (poly.length < 3) return;

    // A fan from the first vertex. Clipping one plane off a triangle leaves
    // three or four corners, so this is one triangle or two.
    for (var i = 1; i + 1 < poly.length; i++) {
      _rasteriseTriangle(
        pipeline,
        target,
        view,
        <Vector4>[poly[0], poly[i], poly[i + 1]],
        <Float32List>[polyVaryings[0], polyVaryings[i], polyVaryings[i + 1]],
        varyingCount,
        bindings,
      );
    }
  }

  void _rasteriseTriangle(
    _CpuPipeline pipeline,
    CpuTexture target,
    ScreenRect view,
    List<Vector4> clip,
    List<Float32List> varyings,
    int varyingCount,
    ShaderBindings bindings,
  ) {
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

    // Wound so the interior is where every edge function is positive, which
    // the fill rule below depends on. Done after culling, which is what needs
    // the original winding.
    if (area < 0) {
      final t = sx[1]; sx[1] = sx[2]; sx[2] = t;
      final ty = sy[1]; sy[1] = sy[2]; sy[2] = ty;
      final tz = sz[1]; sz[1] = sz[2]; sz[2] = tz;
      final tw = invW[1]; invW[1] = invW[2]; invW[2] = tw;
      final tv = varyings[1]; varyings[1] = varyings[2]; varyings[2] = tv;
      area = -area;
    }

    // The top-left fill rule: a pixel centre landing exactly on a shared edge
    // belongs to one of the two triangles rather than to both.
    //
    // Here because it is the correct rule and costs nothing, **not** because
    // it fixed anything. It was written to explain the particle burst, which
    // is drawn as additive quads and came out five percent brighter than
    // Impeller's — double coverage along every quad's diagonal was the obvious
    // culprit, since opaque geometry hides it and additive blending does not.
    // The rule changed the picture by exactly zero pixels. With floating-point
    // window coordinates a pixel centre essentially never lands on an edge, so
    // the case the rule governs did not arise. The burst is still unexplained.
    //
    // In window space, where y runs down and the interior is w > 0: a
    // horizontal edge is a *top* edge when the interior lies below it, which
    // is when it runs left to right; any edge running upwards is a *left*
    // edge. Those two include their zeros, everything else excludes them.
    bool topLeft(double ax, double ay, double bx, double by) =>
        (ay == by && bx > ax) || by < ay;
    final fill0 = topLeft(sx[0], sy[0], sx[1], sy[1]);
    final fill1 = topLeft(sx[1], sy[1], sx[2], sy[2]);
    final fill2 = topLeft(sx[2], sy[2], sx[0], sy[0]);

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
    final context = FragmentContext();

    // The surface buffer, when the pass declared one. Only the second is
    // handled: the engine opens no pass with a third, and inventing a general
    // multi-target path for a call site that does not exist would be inventing
    // the semantics too.
    final extra = _descriptor.colors.length > 1
        ? _descriptor.colors[1].texture.backend as CpuTexture
        : null;

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final w0 =
            (sx[1] - sx[0]) * (py - sy[0]) - (sy[1] - sy[0]) * (px - sx[0]);
        final w1 =
            (sx[2] - sx[1]) * (py - sy[1]) - (sy[2] - sy[1]) * (px - sx[1]);
        final w2 =
            (sx[0] - sx[2]) * (py - sy[2]) - (sy[0] - sy[2]) * (px - sx[2]);
        if (w0 < 0 || (w0 == 0 && !fill0)) continue;
        if (w1 < 0 || (w1 == 0 && !fill1)) continue;
        if (w2 < 0 || (w2 == 0 && !fill2)) continue;

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

        // gl_FragCoord: pixel centre, window depth, and 1/w. Rebuilt rather
        // than reused between fragments, because a stage that kept a reference
        // to it would see the next fragment's values.
        context.coord.setValues(px, py, z, iw);
        context.surface = null;
        final colour = pipeline.fragment.run(interpolated, bindings, context);
        if (colour == null) continue;

        // Attachment one, when the stage wrote it and the pass has one. Both
        // conditions matter: the lit models always write it and the shadow
        // passes never do, and a pass may have a single attachment either way.
        final surface = context.surface;
        if (surface != null && extra != null) {
          final e = index * 4;
          extra.pixels[e] = surface.x;
          extra.pixels[e + 1] = surface.y;
          extra.pixels[e + 2] = surface.z;
          extra.pixels[e + 3] = surface.w;
        }

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

/// How one vertex's attributes are collected before a stage sees them.
///
/// Two implementations, and the split is the whole of this backend's support
/// for instancing. A vertex stage here receives one `Float32List` and reads it
/// by position — that never changes. What changes is where those floats came
/// from.
abstract interface class _VertexFetch {
  /// How many floats one vertex amounts to.
  int get floatsPerVertex;

  /// Fills [out] for [vertex], or answers false when a buffer is too short.
  ///
  /// False rather than a throw because a short buffer is a caller's arithmetic
  /// mistake that this backend has always answered by drawing nothing, and
  /// changing that here would turn a blank scene into a crash in the middle of
  /// a golden run.
  bool into(Float32List out, int vertex);
}

/// One interleaved buffer, in the order the shader declares its inputs.
///
/// Every draw this engine made before instancing, and every draw it still makes
/// except the instanced ones. The layout is not described anywhere: it is the
/// shader's `in` order, which is the same contract flutter_gpu works from.
final class _PackedFetch implements _VertexFetch {
  _PackedFetch(ByteData bytes, this.floatsPerVertex)
      : _floats = bytes.buffer
            .asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);

  final Float32List _floats;

  @override
  final int floatsPerVertex;

  @override
  bool into(Float32List out, int vertex) {
    final base = vertex * floatsPerVertex;
    if (base + floatsPerVertex > _floats.length) return false;
    for (var f = 0; f < floatsPerVertex; f++) {
      out[f] = _floats[base + f];
    }
    return true;
  }
}

/// Several buffers, some stepping per vertex and some per instance.
///
/// **The assembled order is the layout's order** — every attribute of slot 0,
/// then every attribute of slot 1, and so on — and the vertex stage must
/// declare its inputs to match. That is the same kind of contract the packed
/// path already lives under, where the order is the shader's own; it is written
/// down here because with two buffers there is no single obvious order to fall
/// back on, and a stage that disagreed would read a position as a colour and
/// draw something rather than failing.
final class _LayoutFetch implements _VertexFetch {
  _LayoutFetch._(
    this._views,
    this._strides,
    this._element,
    this._offsets,
    this._counts,
    this.floatsPerVertex,
  );

  /// Resolves [layout] against the bound buffers for one instance.
  ///
  /// Built per draw rather than per vertex: the arithmetic below depends only
  /// on the layout and the instance, and doing it three times per triangle was
  /// measurably the wrong shape when the same mistake was made in the packed
  /// path's ancestor.
  factory _LayoutFetch.build(
    VertexLayoutSpec layout,
    ByteData slotZero,
    Map<int, ByteData>? slots,
    int instance,
  ) {
    final views = <Float32List>[];
    final strides = <int>[];
    final element = <int>[];
    final offsets = <List<int>>[];
    final counts = <List<int>>[];
    var total = 0;

    for (var slot = 0; slot < layout.buffers.length; slot++) {
      final buffer = layout.buffers[slot];
      final bytes = slot == 0 ? slotZero : slots?[slot];
      if (bytes == null) {
        throw StateError(
          'the pipeline\'s layout describes slot $slot and nothing was bound '
          'to it. Every slot the layout names has to be filled before a draw.',
        );
      }
      views.add(bytes.buffer
          .asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4));
      if (buffer.strideInBytes % 4 != 0) {
        throw UnsupportedError(
          'slot $slot has a stride of ${buffer.strideInBytes} bytes. This '
          'backend reads floats, so a stride has to be a multiple of four.',
        );
      }
      strides.add(buffer.strideInBytes ~/ 4);
      // The one line instancing is actually about: a per-instance buffer is
      // read at the instance index and stays there for every vertex of it.
      element.add(buffer.stepMode == VertexStepMode.instance ? instance : -1);

      final theseOffsets = <int>[];
      final theseCounts = <int>[];
      for (final attribute in buffer.attributes) {
        theseOffsets.add(attribute.offsetInBytes ~/ 4);
        theseCounts.add(attribute.format.componentCount);
        total += attribute.format.componentCount;
      }
      offsets.add(theseOffsets);
      counts.add(theseCounts);
    }

    return _LayoutFetch._(views, strides, element, offsets, counts, total);
  }

  final List<Float32List> _views;
  final List<int> _strides;

  /// The fixed element index for a per-instance buffer, or -1 for a per-vertex
  /// one, which takes the vertex it is asked for.
  final List<int> _element;

  final List<List<int>> _offsets;
  final List<List<int>> _counts;

  @override
  final int floatsPerVertex;

  @override
  bool into(Float32List out, int vertex) {
    var at = 0;
    for (var slot = 0; slot < _views.length; slot++) {
      final view = _views[slot];
      final fixed = _element[slot];
      final base = (fixed < 0 ? vertex : fixed) * _strides[slot];
      final offsets = _offsets[slot];
      final counts = _counts[slot];
      for (var a = 0; a < offsets.length; a++) {
        final from = base + offsets[a];
        final count = counts[a];
        if (from + count > view.length) return false;
        for (var c = 0; c < count; c++) {
          out[at++] = view[from + c];
        }
      }
    }
    return true;
  }
}
