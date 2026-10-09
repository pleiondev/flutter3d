/// Records state and rasterises on `draw`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart';

import 'cpu_render_bundle.dart';
import 'cpu_resources.dart';
import 'cpu_shader.dart';
import 'cpu_shader_library.dart';
import 'cpu_vertex_fetch.dart';

/// Records state and rasterises on `draw`.
///
/// [features] is the device's answer, which every gated member asks before
/// doing anything; [support] answers per format, for storage bindings; and
/// [clock] is what the pass's timestamps are read from.
final class CpuEncoder extends PassEncoder with CommandEncoder {
  CpuEncoder(
    this._descriptor, {
    required DeviceFeatures features,
    required this._support,
    required this._clock,
  }) : _features = features,
       _independentBlend = features.has(DeviceFeature.independentBlend) {
    final occlusion = _descriptor.occlusionQuerySet;
    if (occlusion != null && occlusion.type != QueryType.occlusion) {
      throw ArgumentError.value(
        occlusion,
        'occlusionQuerySet',
        'is a ${occlusion.type.name} set',
      );
    }
    final timestamps = _descriptor.timestampWrites;
    writeTimestamp(timestamps, timestamps?.beginningOfPassIndex, _clock);
    for (final color in _descriptor.colors) {
      final texture = _attachment(color);
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
      // The level and the plane the attachment names. `layer` and `face`
      // count as a colour target's do, so on a cube or a cube array the
      // plane is the one a `TextureRegion.z` would name: `layer × 6 + face`.
      final shape = depth.texture.dimension;
      final texture = (depth.texture.backend as CpuTexture).plane(
        mipLevel: depth.mipLevel,
        z: shape == TextureDimension.cube || shape == TextureDimension.cubeArray
            ? depth.layer * 6 + depth.face
            : depth.layer,
      );
      // Kept as the last pass left it when the pass loads — `R8`'s
      // transparent passes test against the opaque pass's depth. Every
      // buffer here is stored, so the store action has nothing to decide.
      // A read-only depth is never cleared and never written: its load
      // action is ignored, as WebGPU says.
      if (depth.loadAction == LoadAction.clear && !depth.depthReadOnly) {
        texture.depthBuffer().fillRange(
          0,
          texture.width * texture.height,
          depth.clearValue,
        );
      }
      _depthTarget = texture;
      _depthReadOnly = depth.depthReadOnly;
      _depthFormat = depth.texture.format;
      // The stencil only where the format says there is one — the test
      // against an attachment without a stencil is specified to pass always,
      // and a null here is how the loops below get that for free.
      if (depth.texture.format.hasStencil) {
        final stencil = texture.stencilBuffer();
        if (depth.stencilLoadAction == LoadAction.clear &&
            !depth.stencilReadOnly) {
          stencil.fillRange(0, stencil.length, depth.stencilClearValue & 0xFF);
        }
        _stencilTarget = stencil;
        _stencilReadOnly = depth.stencilReadOnly;
      }
    }
  }

  final RenderPassDescriptor _descriptor;
  final DeviceFeatures _features;
  final TextureFormatSupport Function(TextureFormat) _support;
  final CpuClock _clock;

  /// What the device answered for `supportsIndependentBlend`. False only for
  /// a test drawing the fallback; then an index is ignored, as the contract
  /// says of a backend without it.
  final bool _independentBlend;
  CpuTexture? _depthTarget;
  Uint8List? _stencilTarget;
  TextureFormat _depthFormat = TextureFormat.unknown;

  /// `DepthTarget.depthReadOnly` and `stencilReadOnly`: tested against,
  /// never written, whatever a draw's write state says.
  bool _depthReadOnly = false;
  bool _stencilReadOnly = false;

  /// [DepthBias.none] until a pass sets one — `setDepthBias`.
  DepthBias _depthBias = DepthBias.none;

  /// Off until a pass says otherwise — `setDepthClamp`.
  bool _depthClamp = false;

  /// One mask per attachment the rasteriser writes: colour, the surface
  /// buffer and the albedo buffer — `setColorWriteMask`.
  final List<ColorWriteMask> _writeMasks = List<ColorWriteMask>.filled(
    3,
    ColorWriteMask.all,
  );

  /// Fragments that passed the depth and stencil tests and were not
  /// discarded, since the pass opened — what an occlusion query is the
  /// difference of.
  int _samplesPassed = 0;
  ({CpuQueryResults results, int index, int start})? _occlusion;

  final CpuStatistics _statistics = CpuStatistics();
  CpuOpenStatisticsQuery? _statisticsQuery;
  final Map<String, ByteData> _storage = <String, ByteData>{};
  final Map<String, CpuStorageTexture> _storageTextures =
      <String, CpuStorageTexture>{};

  // Off on both faces until a pass says otherwise, which is what a fresh
  // `flutter_gpu` pass and a fresh GL context both start with.
  StencilState _stencilFront = StencilState.disabled;
  StencilState _stencilBack = StencilState.disabled;
  int _stencilReference = 0;

  /// The buffer to test against, or null when nothing would change: no
  /// attachment carries one, or both faces are still switched off. Asked once
  /// per primitive so the thirty-odd scenes that never mention the stencil
  /// pay a null check per triangle and nothing per fragment.
  Uint8List? get _activeStencil =>
      _stencilFront == StencilState.disabled &&
          _stencilBack == StencilState.disabled
      ? null
      : _stencilTarget;

  /// The array [color] actually names: a face of a cube, a level of a chain,
  /// or the texture itself. Every write in this pass goes through it, so a
  /// probe's face and a post pass's full-size target are the same code.
  static CpuTexture _attachment(ColorTarget color) =>
      (color.texture.backend as CpuTexture).subresource(
        face: color.face,
        mipLevel: color.mipLevel,
        layer: color.layer,
      );

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

  /// Attachment one's blend — `R8`. Null, which here means the stage's value
  /// is written as it is, until a call names that attachment: that is what
  /// attachment one has always had, so no pass that never names it moves.
  BlendState? _surfaceBlend;

  /// The constant the four constant-reading factors multiply by.
  ///
  /// Transparent black until a pass sets it, which the HAL states and which
  /// costs nothing to keep here: the field is the pass's, so a pass that never
  /// mentions the constant cannot inherit the previous one's.
  final Vector4 _blendColor = Vector4.zero();
  CpuPipeline? _pipeline;

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
      _features.require(
        DeviceFeature.wireframe,
        backend: cpuBackendName,
        reason: wireframeRefusal,
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
  void setDepthWrite({required bool enabled}) => _depthWrite = enabled;

  /// Nothing — `P7`: one sample a pixel has no coverage to spread; `supportsAlphaToCoverage` is false.
  @override
  void setAlphaToCoverage({required bool enabled}) {}

  @override
  void setDepthCompare(CompareFunction compare) => _depthCompare = compare;

  @override
  void setStencil(StencilState front, {StencilState? back}) {
    _stencilFront = front;
    _stencilBack = back ?? front;
  }

  @override
  void setStencilReference(int value) =>
      _stencilReference = StencilState.narrowReference(value);

  /// Attachments zero and one each keep their own state; a higher index is
  /// ignored, since the albedo buffer is never blended — `R8`.
  ///
  /// Until weighted blended transparency asked, this pass kept one state and
  /// ignored the index. Attachment one was never blended even so: the
  /// surface buffer took the stage's value as it came, and still does until
  /// something names it. A device built without independent blending goes
  /// back to one state, whatever the index, which is the contract's word for
  /// a backend that has none.
  ///
  /// The 1.0 factors and operations are honoured — min and max ignore both
  /// factors, the four `source1…` factors read `FragmentContext.source1` —
  /// and refused through their features on a device built without them.
  /// Dual-source blending reads attachment zero's second output, so a state
  /// naming one of those factors for any other attachment is an
  /// [ArgumentError], as WebGPU makes it.
  @override
  void setBlend(BlendState? state, {int attachment = 0}) {
    if (state != null) checkBlend(state, attachment, _features);
    if (attachment == 0 || !_independentBlend) {
      _blend = state;
    } else if (attachment == 1) {
      _surfaceBlend = state;
    }
  }

  @override
  void setBlendColor(Vector4 color) {
    _features.require(DeviceFeature.blendConstant, backend: cpuBackendName);
    _blendColor.setFrom(color);
  }

  /// Forgets every binding, as the contract says every backend does.
  ///
  /// It used to replace the pipeline and keep the rest, so a draw that forgot
  /// a block read the previous draw's here and drew a plausible picture, while
  /// Impeller, which clears on this call, failed. The software set is the
  /// cross-backend reference; it cannot be the backend that hides a missing
  /// bind.
  @override
  void bindPipeline(PipelineHandle pipeline) {
    _pipeline = pipeline.backend as CpuPipeline;
    clearBindings();
  }

  @override
  void bindVertexBuffer(
    GeometryBuffer buffer,
    int vertexCount, {
    int slot = 0,
  }) {
    final backend = buffer.backend as ({ByteData bytes, GeometryUsage usage});
    _bindSlot(slot, _range(backend.bytes, buffer), vertexCount);
  }

  /// The bytes [buffer] names within [bytes]: its offset and length, which
  /// `GeometryBuffer.slice` sets and this used to ignore, reading from byte
  /// zero with a stride worked out from the whole buffer.
  static ByteData _range(ByteData bytes, GeometryBuffer buffer) =>
      buffer.offsetInBytes == 0 && buffer.lengthInBytes == bytes.lengthInBytes
      ? bytes
      : ByteData.sublistView(
          bytes,
          buffer.offsetInBytes,
          buffer.offsetInBytes + buffer.lengthInBytes,
        );

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
    _indices = _range(backend.bytes, buffer);
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
    // `gfx-92n`: a block the compiled stage dropped is refused here, before
    // anything reaches the driver — binding one is a native crash on Metal.
    if (!shader.mayBindBlock(blockName)) return false;
    // `H1`: where the stage's layout is known, a member it does not have, or
    // more floats than the member holds, is refused by name — the same
    // refusal Impeller, WebGL and WebGPU make from their own reflection. A
    // Dart stage reads members by name, so without this a misspelt member
    // read as zero here and threw on every other backend.
    final layout = shader.layouts?[blockName];
    if (layout != null) {
      members.forEach((name, values) {
        final member = layout[name];
        if (member == null) {
          throw StateError(
            'uniform block "$blockName" has no member "$name" in stage '
            '"${shader.name}". The engine and the shader disagree about this '
            'block.',
          );
        }
        if (values.length * 4 > member.byteLength) {
          throw StateError(
            'uniform block "$blockName" member "$name" wants ${values.length} '
            'floats and has room for ${member.byteLength ~/ 4}.',
          );
        }
      });
    }
    _blocks[blockName] = members;
    return true;
  }

  /// True always: a Dart stage declares no samplers, so "this stage has no
  /// such slot" is not a state this backend has. See
  /// `CommandEncoder.bindUniformBlock` for why that is the honest answer.
  @override
  bool bindTexture(
    ShaderHandle shader,
    String slot,
    TextureHandle texture, {
    SamplerDescriptor? sampler,
  }) {
    // The sampler's features first, before the slot: a refusal is about the
    // device, whichever slot it was asked of.
    checkSampler(sampler, _features);
    if (!shader.mayBindSampler(slot)) return false;
    // linearRepeat for a null sampler, which is now written down in
    // `CommandEncoder.bindTexture` — it was not, and this backend picked the
    // constructor's own defaults instead, nearest and clamped. Both hardware
    // backends had independently chosen linearRepeat, so the two agreed and
    // the rule stayed unstated until a third implementation read the
    // interface and answered differently. It cost two percent of every
    // textured golden and looked like a rendering bug.
    _textures[slot] = BoundTexture(
      texture.backend as CpuTexture,
      sampler ?? SamplerDescriptor.linearRepeat,
    );
    return true;
  }

  /// Every binding, geometry included, as the contract says. It used to keep
  /// the vertex slots and the index buffer, so a draw after this re-drew the
  /// previous mesh here and an instanced slot the next layout declares and
  /// did not bind passed with the previous batch's instances in it.
  @override
  void clearBindings() {
    _blocks.clear();
    _textures.clear();
    _storage.clear();
    _storageTextures.clear();
    _vertices = null;
    _vertexCount = 0;
    _slots = null;
    _indices = null;
    _indexCount = 0;
  }

  @override
  void submit() {
    // Nothing deferred, so nothing to flush. Draws happened as they arrived,
    // which is a different execution model from a command buffer and one the
    // contract allows: it promises passes execute in submission order, not
    // that anything is buffered. The end timestamp is all there is to write.
    if (_occlusion != null || _statisticsQuery != null) {
      throw StateError('a pass submitted with a query still open');
    }
    final timestamps = _descriptor.timestampWrites;
    writeTimestamp(timestamps, timestamps?.endOfPassIndex, _clock);
  }

  // ------------------------------------------------------------------ 1.0

  @override
  void setDepthBias(DepthBias bias) {
    _features.require(DeviceFeature.depthBias, backend: cpuBackendName);
    _depthBias = bias;
  }

  /// Masks attachments zero, one and two — the colour, the surface buffer
  /// and the albedo buffer, every attachment this rasteriser writes. A
  /// device built without independent blending masks attachment zero
  /// whatever the index, as `setBlend` does.
  @override
  void setColorWriteMask(ColorWriteMask mask, {int attachment = 0}) {
    _features.require(DeviceFeature.colorWriteMask, backend: cpuBackendName);
    final index = _independentBlend ? attachment : 0;
    if (index < 0 || index >= _writeMasks.length) {
      throw RangeError.range(attachment, 0, _writeMasks.length - 1);
    }
    _writeMasks[index] = mask;
  }

  @override
  void setDepthClamp({required bool enabled}) {
    _features.require(DeviceFeature.depthClamp, backend: cpuBackendName);
    _depthClamp = enabled;
  }

  /// False unless the stage declares [name] — see [CpuStorageReader]; the
  /// stage reads the bytes as `ShaderBindings.storage[name]`, the buffer's
  /// own memory.
  @override
  bool bindStorageBuffer(
    ShaderHandle shader,
    String name,
    StorageBuffer buffer, {
    int offsetInBytes = 0,
    int? sizeInBytes,
  }) {
    _features.require(
      DeviceFeature.renderStageStorage,
      backend: cpuBackendName,
    );
    final range = storageRangeOf(
      buffer,
      offsetInBytes: offsetInBytes,
      sizeInBytes: sizeInBytes,
    );
    if (!declaresStorage(shader, name, undeclared: false)) return false;
    _storage[name] = range;
    return true;
  }

  @override
  bool bindStorageTexture(
    ShaderHandle shader,
    String name,
    TextureHandle texture, {
    int mipLevel = 0,
    StorageTextureAccess access = StorageTextureAccess.writeOnly,
  }) {
    _features.require(
      DeviceFeature.renderStageStorage,
      backend: cpuBackendName,
    );
    final bound = CpuStorageTexture.bind(
      texture,
      mipLevel: mipLevel,
      access: access,
      features: _features,
      support: _support(texture.format),
      backend: cpuBackendName,
    );
    if (!declaresStorage(shader, name, undeclared: false)) return false;
    _storageTextures[name] = bound;
    return true;
  }

  /// Refused — see `uniformBytesRefusal` for what would unblock it.
  @override
  bool bindUniformBytes(
    ShaderHandle shader,
    String blockName,
    ByteData bytes,
  ) => throw uniformBytesRefusal();

  @override
  void drawIndexed(IndexedDraw draw) {
    checkIndexedDraw(draw, _features);
    _drawIndexed(draw);
  }

  /// Every [IndexedDraw] in turn, which is what a native multi-draw is too.
  /// Each is checked before any is drawn, so a refused entry draws nothing.
  @override
  void multiDraw(List<IndexedDraw> draws) {
    _features.require(DeviceFeature.multiDraw, backend: cpuBackendName);
    for (final draw in draws) {
      checkIndexedDraw(draw, _features);
    }
    for (final draw in draws) {
      _drawIndexed(draw);
    }
  }

  /// Reads the twenty bytes and draws them: the pass that wrote them ran to
  /// its end before this one opened, so there is nothing to wait for.
  @override
  void drawIndirect(StorageBuffer arguments, {int offsetInBytes = 0}) {
    _features.require(DeviceFeature.indirectDraw, backend: cpuBackendName);
    _drawIndirect(arguments, offsetInBytes);
  }

  @override
  void multiDrawIndirect(
    StorageBuffer arguments,
    int drawCount, {
    int offsetInBytes = 0,
    StorageBuffer? countBuffer,
    int countOffsetInBytes = 0,
  }) {
    _features.require(DeviceFeature.multiDrawIndirect, backend: cpuBackendName);
    final int count;
    if (countBuffer == null) {
      count = drawCount;
    } else {
      requireBufferUsage(countBuffer, BufferUsage.indirect, 'a draw count');
      checkUnmapped(countBuffer);
      final written = rangeOf(
        countBuffer,
        offsetInBytes: countOffsetInBytes,
        sizeInBytes: 4,
      ).getUint32(0, Endian.little);
      count = written < drawCount ? written : drawCount;
    }
    for (var i = 0; i < count; i++) {
      _drawIndirect(arguments, offsetInBytes + i * 20);
    }
  }

  @override
  void drawNonIndexed({
    required int vertexCount,
    int firstVertex = 0,
    int instanceCount = 1,
    int firstInstance = 0,
  }) {
    _features.require(DeviceFeature.nonIndexedDraw, backend: cpuBackendName);
    for (var i = 0; i < instanceCount; i++) {
      _drawOnce(firstInstance + i, firstVertex, vertexCount, indexed: false);
    }
  }

  /// Replays each bundle's calls into this pass, each starting from a pass's
  /// own defaults — no pipeline, no bindings, the state a pass opens with —
  /// and puts back afterwards the state this pass had, with its bindings
  /// forgotten, as WebGPU specifies. Nothing leaks in either direction.
  @override
  void executeBundles(List<RenderBundle> bundles) {
    _features.require(DeviceFeature.renderBundles, backend: cpuBackendName);
    for (final bundle in bundles) {
      _checkBundle(bundle);
    }
    final saved = _drawState();
    for (final bundle in bundles) {
      _restoreDrawState(_openingState);
      _pipeline = null;
      clearBindings();
      for (final call in (bundle.backend as CpuRenderBundle).calls) {
        call(this);
      }
    }
    _restoreDrawState(saved);
    clearBindings();
  }

  void _checkBundle(RenderBundle bundle) {
    final wanted = bundle.descriptor;
    final colors = <TextureFormat>[
      for (final c in _descriptor.colors) c.texture.format,
    ];
    final depth = _descriptor.depth?.texture.format;
    final samples = _descriptor.colors.isEmpty
        ? 1
        : _descriptor.colors.first.texture.sampleCount;
    final matches =
        wanted.colorFormats.length == colors.length &&
        <bool>[
          for (var i = 0; i < colors.length; i++)
            wanted.colorFormats[i] == colors[i],
        ].every((bool same) => same) &&
        wanted.depthStencilFormat == depth &&
        wanted.sampleCount == samples;
    if (!matches) {
      throw ArgumentError.value(
        bundle,
        'bundles',
        'was recorded for ${wanted.colorFormats.map((f) => f.name)} / '
            '${wanted.depthStencilFormat?.name} x${wanted.sampleCount}, and '
            'this pass is ${colors.map((f) => f.name)} / ${depth?.name} '
            'x$samples',
      );
    }
  }

  @override
  void beginOcclusionQuery(int queryIndex) {
    _features.require(DeviceFeature.occlusionQuery, backend: cpuBackendName);
    final set = _descriptor.occlusionQuerySet;
    if (set == null) {
      throw StateError(
        'beginOcclusionQuery in a pass opened with no occlusionQuerySet',
      );
    }
    if (_occlusion != null) {
      throw StateError('an occlusion query is already open in this pass');
    }
    _occlusion = (
      results: queryResultsOf(set, QueryType.occlusion, queryIndex),
      index: queryIndex,
      start: _samplesPassed,
    );
  }

  @override
  void endOcclusionQuery() {
    final open = _occlusion;
    if (open == null) throw StateError('no occlusion query is open');
    open.results.values[open.index] = _samplesPassed - open.start;
    _occlusion = null;
  }

  @override
  void beginPipelineStatisticsQuery(QuerySet querySet, int queryIndex) {
    _features.require(
      DeviceFeature.pipelineStatisticsQuery,
      backend: cpuBackendName,
    );
    if (_statisticsQuery != null) {
      throw StateError('a pipeline-statistics query is already open');
    }
    _statisticsQuery = CpuOpenStatisticsQuery(
      queryResultsOf(querySet, QueryType.pipelineStatistics, queryIndex),
      queryIndex,
      _statistics,
    );
  }

  @override
  void endPipelineStatisticsQuery() {
    final query = _statisticsQuery;
    if (query == null) {
      throw StateError('no pipeline-statistics query is open');
    }
    query.end(_statistics);
    _statisticsQuery = null;
  }

  /// [draw] with its base vertex and instance range, after the gate.
  void _drawIndexed(IndexedDraw draw) {
    if (!draw.usesBaseVertexOrInstance) {
      this.draw(
        instanceCount: draw.instanceCount,
        firstIndex: draw.firstIndex,
        indexCount: draw.indexCount,
      );
      return;
    }
    if (_indices == null) {
      throw StateError('an indexed draw with no index buffer bound');
    }
    final window = indexWindow(
      _indexCount,
      firstIndex: draw.firstIndex,
      indexCount: draw.indexCount,
    );
    for (var i = 0; i < draw.instanceCount; i++) {
      _drawOnce(
        draw.firstInstance + i,
        window.first,
        window.count,
        indexed: true,
        baseVertex: draw.baseVertex,
      );
    }
  }

  void _drawIndirect(StorageBuffer arguments, int offsetInBytes) {
    final words = readIndirectDraw(arguments, offsetInBytes);
    if (words.firstInstance != 0) {
      _features.require(
        DeviceFeature.indirectFirstInstance,
        backend: cpuBackendName,
        reason: 'the indirect arguments name a first instance',
      );
    }
    if (_indices == null) {
      throw StateError('an indirect draw with no index buffer bound');
    }
    final window = indexWindow(
      _indexCount,
      firstIndex: words.firstIndex,
      indexCount: words.indexCount,
    );
    for (var i = 0; i < words.instanceCount; i++) {
      _drawOnce(
        words.firstInstance + i,
        window.first,
        window.count,
        indexed: true,
        baseVertex: words.baseVertex,
      );
    }
  }

  /// The state a draw inherits from the calls before it, as one value — what
  /// [executeBundles] saves, resets and puts back.
  ({
    CpuPipeline? pipeline,
    PrimitiveType primitive,
    CullMode cull,
    WindingOrder winding,
    bool depthWrite,
    CompareFunction depthCompare,
    BlendState? blend,
    BlendState? surfaceBlend,
    StencilState stencilFront,
    StencilState stencilBack,
    DepthBias depthBias,
    bool depthClamp,
    List<ColorWriteMask> writeMasks,
  })
  _drawState() => (
    pipeline: _pipeline,
    primitive: _primitive,
    cull: _cull,
    winding: _winding,
    depthWrite: _depthWrite,
    depthCompare: _depthCompare,
    blend: _blend,
    surfaceBlend: _surfaceBlend,
    stencilFront: _stencilFront,
    stencilBack: _stencilBack,
    depthBias: _depthBias,
    depthClamp: _depthClamp,
    writeMasks: List<ColorWriteMask>.of(_writeMasks),
  );

  /// What every pass opens with — the defaults the fields below start at.
  static const _openingState = (
    pipeline: null,
    primitive: PrimitiveType.triangle,
    cull: CullMode.none,
    winding: WindingOrder.counterClockwise,
    depthWrite: false,
    depthCompare: CompareFunction.less,
    blend: null,
    surfaceBlend: null,
    stencilFront: StencilState.disabled,
    stencilBack: StencilState.disabled,
    depthBias: DepthBias.none,
    depthClamp: false,
    writeMasks: <ColorWriteMask>[
      ColorWriteMask.all,
      ColorWriteMask.all,
      ColorWriteMask.all,
    ],
  );

  void _restoreDrawState(
    ({
      CpuPipeline? pipeline,
      PrimitiveType primitive,
      CullMode cull,
      WindingOrder winding,
      bool depthWrite,
      CompareFunction depthCompare,
      BlendState? blend,
      BlendState? surfaceBlend,
      StencilState stencilFront,
      StencilState stencilBack,
      DepthBias depthBias,
      bool depthClamp,
      List<ColorWriteMask> writeMasks,
    })
    state,
  ) {
    _pipeline = state.pipeline;
    _primitive = state.primitive;
    _cull = state.cull;
    _winding = state.winding;
    _depthWrite = state.depthWrite;
    _depthCompare = state.depthCompare;
    _blend = state.blend;
    _surfaceBlend = state.surfaceBlend;
    _stencilFront = state.stencilFront;
    _stencilBack = state.stencilBack;
    _depthBias = state.depthBias;
    _depthClamp = state.depthClamp;
    _writeMasks.setAll(0, state.writeMasks);
  }

  @override
  void draw({int instanceCount = 1, int firstIndex = 0, int? indexCount}) {
    // Refused before the first instance rather than inside the loop, so a
    // window past the binding draws nothing at all, as on the other three.
    final window = _indices == null
        ? null
        : indexWindow(
            _indexCount,
            firstIndex: firstIndex,
            indexCount: indexCount,
          );
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
      _drawOnce(
        instance,
        window?.first ?? 0,
        window?.count ?? _vertexCount,
        indexed: window != null,
      );
    }
  }

  /// One instance: [count] indices from [first] (each plus [baseVertex]) when
  /// [indexed], or [count] vertices in order from [first] when not.
  void _drawOnce(
    int instance,
    int first,
    int count, {
    required bool indexed,
    int baseVertex = 0,
  }) {
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

    final target = _attachment(_descriptor.colors.first);
    final view =
        _viewport ??
        ScreenRect(x: 0, y: 0, width: target.width, height: target.height);

    final layout = pipeline.layout;
    final fetch = layout == null
        ? PackedFetch(vertices, _floatsPerVertex(vertices, _vertexCount))
        : LayoutFetch.build(layout, vertices, _slots, instance);
    final stride = fetch.floatsPerVertex;
    final bindings = ShaderBindings.forDraw(
      _blocks,
      _textures,
      storage: _storage,
      storageTextures: _storageTextures,
    );
    final varyingCount = pipeline.vertex.varyingCount;

    final clip = <Vector4>[Vector4.zero(), Vector4.zero(), Vector4.zero()];
    final varyings = <Float32List>[
      Float32List(varyingCount),
      Float32List(varyingCount),
      Float32List(varyingCount),
    ];
    final attributes = Float32List(stride);

    final perPrimitive = _primitive == PrimitiveType.line ? 2 : 3;
    final primitives = count ~/ perPrimitive;

    for (var t = 0; t < primitives; t++) {
      for (var corner = 0; corner < perPrimitive; corner++) {
        final at = first + t * perPrimitive + corner;
        final vertex = indexed ? _indexAt(at) + baseVertex : at;
        if (!fetch.into(attributes, vertex)) return;
        _statistics.add(PipelineStatistic.vertexShaderInvocations, 1);
        // A stage that wants its own index gets it — see
        // [CpuVertexShaderByIndex], which exists because morph targets read a
        // delta per vertex and this backend had no way to say which vertex.
        // Asked once per corner rather than hoisted: `is` on a const stage is
        // a class check the compiler folds, and hoisting it would mean a
        // second field on the pipeline that could disagree with the stage.
        final stage = pipeline.vertex;
        clip[corner] = stage is CpuVertexShaderByIndex
            ? stage.runAt(
                vertex,
                instance,
                attributes,
                bindings,
                varyings[corner],
              )
            : stage.run(attributes, bindings, varyings[corner]);
      }
      _statistics.add(PipelineStatistic.clipperInvocations, 1);
      if (perPrimitive == 2) {
        _rasteriseLine(
          pipeline,
          target,
          view,
          clip,
          varyings,
          varyingCount,
          bindings,
        );
      } else {
        _rasterise(
          pipeline,
          target,
          view,
          clip,
          varyings,
          varyingCount,
          bindings,
        );
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
    CpuPipeline pipeline,
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
    _statistics.add(PipelineStatistic.clipperPrimitivesOut, 1);

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
    // A line has no facing, so it takes the front state — which is what GL
    // does with a primitive it cannot classify.
    final stencil = _activeStencil;
    final stencilState = _stencilFront;
    final interpolated = Float32List(varyingCount);
    final context = FragmentContext();

    // **No screen-space gradients here, and that is the answer rather than an
    // omission.** The triangle path solves them from three window positions;
    // this one has two, and the solve was copied down here whole — it read
    // `sx[2]` and `sy[2]` out of two-element lists, so any line drawn while a
    // bound texture happened to carry a chain came back as a `RangeError` out
    // of the rasteriser rather than as a frame. Debug geometry samples nothing,
    // which is why it never fired.
    //
    // A line has no area and therefore no second direction to differentiate
    // along: there is no derivative to have, only a derivative along the run,
    // which says nothing about how fast a coordinate moves across the pixel.
    // Left unset, `BoundTexture.sample` takes the base level — the sharpest
    // one, and the only defensible choice for a primitive one pixel wide.
    // The viewport and the scissor both — see `_clipRect`.
    final clipRect = _clipRect(view, target);

    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final x = (sx[0] + dx * t).floor();
      final y = (sy[0] + dy * t).floor();
      if (x < clipRect.x ||
          y < clipRect.y ||
          x >= clipRect.x + clipRect.width ||
          y >= clipRect.y + clipRect.height) {
        continue;
      }

      final z = _asStored(sz[0] + (sz[1] - sz[0]) * t);
      final index = y * target.width + x;
      final fate = _fateOf(stencil, stencilState, index, z, depth);
      final op = _operationFor(fate, stencilState);
      if (fate != _fatePass && op == StencilOperation.keep) continue;

      final iw = invW[0] + (invW[1] - invW[0]) * t;
      for (var v = 0; v < varyingCount; v++) {
        interpolated[v] =
            (varyings[0][v] * invW[0] * (1 - t) +
                varyings[1][v] * invW[1] * t) /
            iw;
      }

      context.coord.setValues(x + 0.5, y + 0.5, z, iw);
      context.surface = null;
      // Cleared with it, and for the same reason the coordinate is rebuilt: one
      // context serves every fragment, so a debug picture left over from the
      // last one would be shown for this one.
      context.debugSurface = null;
      context.fragDepth = null;
      context.source1 = null;
      _statistics.add(PipelineStatistic.fragmentShaderInvocations, 1);
      final color = pipeline.fragment.run(interpolated, bindings, context);
      if (color == null) continue;
      if (stencil != null) _stencilWrite(stencil, index, stencilState, op);
      if (fate != _fatePass) continue;
      _samplesPassed++;

      final at = index * 4;
      final mask = _writeMasks[0];
      if (mask != ColorWriteMask.all) _keep(target.pixels, at);
      target.pixels[at] = color.x;
      target.pixels[at + 1] = color.y;
      target.pixels[at + 2] = color.z;
      target.pixels[at + 3] = color.w;
      if (mask != ColorWriteMask.all) _restore(target.pixels, at, mask);
      if (depth != null && _depthWrite && !_depthReadOnly) {
        depth[index] = context.fragDepth ?? z;
      }
    }
  }

  /// The four channels at [at] before a masked write, for [_restore].
  final Float32List _kept = Float32List(4);

  void _keep(Float32List pixels, int at) {
    for (var c = 0; c < 4; c++) {
      _kept[c] = pixels[at + c];
    }
  }

  /// Puts back the channels [mask] says the write may not change —
  /// `setColorWriteMask`. Written as keep-write-restore so that the blend,
  /// which writes all four, needs no masked twin.
  void _restore(Float32List pixels, int at, ColorWriteMask mask) {
    if (!mask.writesRed) pixels[at] = _kept[0];
    if (!mask.writesGreen) pixels[at + 1] = _kept[1];
    if (!mask.writesBlue) pixels[at + 2] = _kept[2];
    if (!mask.writesAlpha) pixels[at + 3] = _kept[3];
  }

  /// One float, for rounding a depth to what the buffer can hold.
  final Float32List _storedDepth = Float32List(1);

  /// [z] as the depth buffer would store it.
  ///
  /// **Compared at the buffer's precision, not the arithmetic's.** The buffer
  /// is a `Float32List` and the interpolation is in doubles, so a surface
  /// drawn twice — which is what the x-ray stage does — used to compare a
  /// double against its own rounded copy: `lessEqual` failed against the
  /// pixel the same triangle had just written, by one part in ten million,
  /// and `greater` passed, so a cube in plain view was painted as its own
  /// silhouette. Hardware has one precision on both sides of the test; this
  /// gives the rasteriser the same, and a coincident surface now ties the way
  /// it ties on a GPU rather than winning or losing by rounding.
  double _asStored(double z) {
    _storedDepth[0] = z;
    return _storedDepth[0];
  }

  /// A fragment the stencil test rejected.
  static const int _fateStencilFail = 0;

  /// A fragment the stencil test passed and the depth test rejected.
  static const int _fateDepthFail = 1;

  /// A fragment both tests passed: shaded, and written if it is not discarded.
  static const int _fatePass = 2;

  /// Which of the three outcomes a fragment at [index] and depth [z] meets.
  ///
  /// The stencil test first and the depth test second, which is the order
  /// the specification runs them in and the order that decides which of a
  /// state's three operations applies. Without a stencil there is only the
  /// depth test, and the answer is the one this rasteriser always gave.
  int _fateOf(
    Uint8List? stencil,
    StencilState state,
    int index,
    double z,
    Float32List? depth,
  ) {
    if (stencil != null && !_stencilPasses(state, stencil[index])) {
      return _fateStencilFail;
    }
    if (depth != null && !_depthPasses(z, depth[index])) {
      return _fateDepthFail;
    }
    return _fatePass;
  }

  static StencilOperation _operationFor(int fate, StencilState state) =>
      switch (fate) {
        _fateStencilFail => state.failOp,
        _fateDepthFail => state.depthFailOp,
        _ => state.passOp,
      };

  /// The reference against the stored value, both through the read mask, with
  /// the reference as the "new" side of the comparison — `less` passes when
  /// the reference is below what is stored, as [CompareFunction] says.
  bool _stencilPasses(StencilState state, int stored) {
    final reference = _stencilReference & state.readMask;
    final current = stored & state.readMask;
    return switch (state.compare) {
      CompareFunction.never => false,
      CompareFunction.always => true,
      CompareFunction.less => reference < current,
      CompareFunction.lessEqual => reference <= current,
      CompareFunction.greater => reference > current,
      CompareFunction.greaterEqual => reference >= current,
      CompareFunction.equal => reference == current,
      CompareFunction.notEqual => reference != current,
    };
  }

  /// Applies [op] to the byte at [index], through the write mask.
  ///
  /// **After the fragment stage, not before it**, in both rasterisers. A
  /// discarded fragment updates neither depth nor stencil on any of the three
  /// backends — that is what makes `discard` useless for a marking draw and
  /// [BlendState.keepDestination] necessary — so the operation a fragment
  /// earned by failing a test is still only applied once the stage has said
  /// the fragment exists. The cost is a shader run for a failing fragment
  /// whose operation is not `keep`; a failing fragment whose operation *is*
  /// `keep` is skipped before shading, exactly as it always was.
  void _stencilWrite(
    Uint8List stencil,
    int index,
    StencilState state,
    StencilOperation op,
  ) {
    if (op == StencilOperation.keep || _stencilReadOnly) return;
    final stored = stencil[index];
    final value = switch (op) {
      StencilOperation.keep => stored,
      StencilOperation.zero => 0,
      StencilOperation.setToReferenceValue => _stencilReference,
      StencilOperation.incrementClamp => math.min(stored + 1, 0xFF),
      StencilOperation.decrementClamp => math.max(stored - 1, 0),
      StencilOperation.invert => ~stored,
      StencilOperation.incrementWrap => stored + 1,
      StencilOperation.decrementWrap => stored - 1,
    };
    stencil[index] =
        (stored & ~state.writeMask) | (value & state.writeMask & 0xFF);
  }

  /// How many floats one vertex is, from the buffer and the count.
  int _floatsPerVertex(ByteData vertices, int count) =>
      count == 0 ? 0 : (vertices.lengthInBytes ~/ 4) ~/ count;

  int _indexAt(int i) => _indexType == IndexType.int16
      ? _indices!.getUint16(i * 2, Endian.little)
      : _indices!.getUint32(i * 4, Endian.little);

  /// How a target keeps what is written to it — `H4`.
  static _Storage _storageOf(TextureFormat format) => switch (format) {
    TextureFormat.r8g8b8a8UNormInt ||
    TextureFormat.b8g8r8a8UNormInt ||
    TextureFormat.r8UNormInt ||
    TextureFormat.r8g8UNormInt ||
    TextureFormat.a8UNormInt => _Storage.unorm8,
    TextureFormat.r8g8b8a8UNormIntSRGB ||
    TextureFormat.b8g8r8a8UNormIntSRGB => _Storage.unorm8Srgb,
    _ => _Storage.float,
  };

  /// What an eight-bit target would have kept of [v]: clamped to the unit
  /// interval and, on a linear target, rounded to the nearest of its 256
  /// steps — `H4`. What blending reads as its destination.
  ///
  /// **A GPU stores what it writes; this keeps every float.** Pixels are
  /// floats here whatever the format, so a reverse subtraction left a negative
  /// value in an eight-bit target — which reads back as black and looks the
  /// same — and the next additive draw added to the negative number where the
  /// GPU had stored nought. The fuzzer's programs blend over one another in a
  /// way the engine's passes never do and found it against WebGPU. The float
  /// stays in the target, because `readHdrPixels` exists to show it; what
  /// the pipeline reads back through the blend is what the hardware would
  /// have kept. An sRGB target is clamped only: its steps are in the encoded
  /// space, and the value here is linear.
  static double _settled(double v, _Storage storage) {
    if (storage == _Storage.float) return v;
    final clamped = v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
    return storage == _Storage.unorm8
        ? (clamped * 255.0).round() / 255.0
        : clamped;
  }

  /// Where a primitive may write: the viewport, the scissor and the target,
  /// intersected. Empty (zero width or height) where they do not meet.
  ScreenRect _clipRect(ScreenRect view, CpuTexture target) {
    final scissor = _scissor;
    var x0 = view.x < 0 ? 0 : view.x;
    var y0 = view.y < 0 ? 0 : view.y;
    var x1 = view.x + view.width;
    var y1 = view.y + view.height;
    if (scissor != null) {
      if (scissor.x > x0) x0 = scissor.x;
      if (scissor.y > y0) y0 = scissor.y;
      if (scissor.x + scissor.width < x1) x1 = scissor.x + scissor.width;
      if (scissor.y + scissor.height < y1) y1 = scissor.y + scissor.height;
    }
    if (x1 > target.width) x1 = target.width;
    if (y1 > target.height) y1 = target.height;
    return ScreenRect(
      x: x0,
      y: y0,
      width: x1 > x0 ? x1 - x0 : 0,
      height: y1 > y0 ? y1 - y0 : 0,
    );
  }

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
    CpuPipeline pipeline,
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
      _statistics.add(PipelineStatistic.clipperPrimitivesOut, 1);
      _rasteriseTriangle(
        pipeline,
        target,
        view,
        clip,
        varyings,
        varyingCount,
        bindings,
      );
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
    _statistics.add(PipelineStatistic.clipperPrimitivesOut, poly.length - 2);

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
    CpuPipeline pipeline,
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

    var area =
        (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0]);
    if (area == 0.0) return;

    // Winding is measured in window space, where y runs down, so a
    // counter-clockwise triangle has negative area here.
    final frontFacing = _winding == WindingOrder.counterClockwise
        ? area < 0
        : area > 0;
    if (_cull == CullMode.backFace && !frontFacing) return;
    if (_cull == CullMode.frontFace && frontFacing) return;

    // Wound so the interior is where every edge function is positive, which
    // the fill rule below depends on. Done after culling, which is what needs
    // the original winding.
    if (area < 0) {
      final t = sx[1];
      sx[1] = sx[2];
      sx[2] = t;
      final ty = sy[1];
      sy[1] = sy[2];
      sy[2] = ty;
      final tz = sz[1];
      sz[1] = sz[2];
      sz[2] = tz;
      final tw = invW[1];
      invW[1] = invW[2];
      invW[2] = tw;
      final tv = varyings[1];
      varyings[1] = varyings[2];
      varyings[2] = tv;
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

    // **The viewport and the scissor both, not one or the other — `H4`.** A
    // GPU clips a triangle to the clip volume, which in window space is the
    // viewport's rectangle, and then the scissor takes what it takes. This
    // used the scissor where there was one and the viewport only where there
    // was not, so a triangle reaching past ±1 drew outside a viewport that had
    // a scissor beside it — up to the edge of the target. Nothing the engine
    // draws had shown it, because its passes set the two to the same
    // rectangle; the fuzzer's programs do not, and found it on its first run
    // against WebGPU.
    // The corners as locals from here on: the lists above hold boxed
    // doubles, and the loop below reads them for every pixel of the box.
    final sx0 = sx[0];
    final sx1 = sx[1];
    final sx2 = sx[2];
    final sy0 = sy[0];
    final sy1 = sy[1];
    final sy2 = sy[2];
    final sz0 = sz[0];
    final sz1 = sz[1];
    final sz2 = sz[2];
    final invW0 = invW[0];
    final invW1 = invW[1];
    final invW2 = invW[2];
    final varyings0 = varyings[0];
    final varyings1 = varyings[1];
    final varyings2 = varyings[2];
    // The edge functions' constant factors, which are the same subtraction
    // whether it is done here or at every pixel.
    final edge0x = sx1 - sx0;
    final edge0y = sy1 - sy0;
    final edge1x = sx2 - sx1;
    final edge1y = sy2 - sy1;
    final edge2x = sx0 - sx2;
    final edge2y = sy0 - sy2;

    final clipRect = _clipRect(view, target);
    var minX = sx.reduce((a, b) => a < b ? a : b).floor();
    var maxX = sx.reduce((a, b) => a > b ? a : b).ceil();
    var minY = sy.reduce((a, b) => a < b ? a : b).floor();
    var maxY = sy.reduce((a, b) => a > b ? a : b).ceil();
    if (minX < clipRect.x) minX = clipRect.x;
    if (minY < clipRect.y) minY = clipRect.y;
    if (maxX > clipRect.x + clipRect.width - 1) {
      maxX = clipRect.x + clipRect.width - 1;
    }
    if (maxY > clipRect.y + clipRect.height - 1) {
      maxY = clipRect.y + clipRect.height - 1;
    }

    final depth = _depthTarget?.depthBuffer();
    // Per face, decided before the winding swap above changed what "front"
    // means for the edge functions: the state a triangle is tested against is
    // the one for the side the camera sees.
    final stencil = _activeStencil;
    final stencilState = frontFacing ? _stencilFront : _stencilBack;
    final interpolated = Float32List(varyingCount);
    final context = FragmentContext()..frontFacing = frontFacing;
    final storage = _storageOf(target.format);

    // **Screen-space gradients, which the triangle path did not have and the
    // line path did.** `CpuTexture.sample` picks the base level when it is
    // given no derivatives, so every textured triangle this backend has ever
    // drawn read the top of the mip chain however small the surface was on
    // screen. The chain was built, uploaded and unit-tested — `mip_sampling_test`
    // exercises `sample` directly with derivatives it supplies itself — and
    // nothing ever handed a triangle's to it.
    //
    // What that looks like is not a missing feature. It is a 2048-square normal
    // map read at full resolution across a few hundred pixels: detail sharper
    // and darker than the hardware backends draw, and aliasing that crawls when
    // the camera moves. It made `normal-mapping` the widest disagreement this
    // backend had with Impeller, at 1.4%, where every other lit scene sat near
    // a fifth of a percent.
    //
    // Solved from the three window positions and the three varying values, the
    // same two-by-two system the line path uses, and after the winding swap
    // above so the vertices match the varyings.
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

    // The surface buffer, when the pass declared one. Only the second is
    // handled: the engine opens no pass with a third, and inventing a general
    // multi-target path for a call site that does not exist would be inventing
    // the semantics too.
    final extra = _descriptor.colors.length > 1
        ? _attachment(_descriptor.colors[1])
        : null;
    // And the albedo buffer, attachment two, when the pass opened one — `L5`.
    final albedoTarget = _descriptor.colors.length > 2
        ? _attachment(_descriptor.colors[2])
        : null;
    final surfaceBlend = _surfaceBlend;
    final extraStorage = extra == null ? null : _storageOf(extra.format);
    final colourMask = _writeMasks[0];
    final surfaceMask = _writeMasks[1];
    final albedoMask = _writeMasks[2];
    final bias = depth == null ? 0.0 : _biasOf(sx, sy, sz, area);
    final depthClamp = _depthClamp;

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final w0 = edge0x * (py - sy0) - edge0y * (px - sx0);
        final w1 = edge1x * (py - sy1) - edge1y * (px - sx1);
        final w2 = edge2x * (py - sy2) - edge2y * (px - sx2);
        if (w0 < 0 || (w0 == 0 && !fill0)) continue;
        if (w1 < 0 || (w1 == 0 && !fill1)) continue;
        if (w2 < 0 || (w2 == 0 && !fill2)) continue;

        // Barycentric, named for the corner each weight belongs to rather than
        // for the edge it came from — the two are rotated by one, which is a
        // classic way to get a picture that is almost right.
        final b0 = w1 / area;
        final b1 = w2 / area;
        final b2 = w0 / area;

        final interpolatedZ = _asStored(sz0 * b0 + sz1 * b1 + sz2 * b2);
        // The depth clip every GPU does and the clipper above does not: a
        // fragment outside `[0, 1]` is in front of the near plane or past
        // the far one. Window depth is linear across the screen, so dropping
        // the fragment is the same cut as clipping the triangle. It mattered
        // once a near plane stopped being parallel to the screen — `P4`'s
        // mirrored camera stands its near plane on the mirror.
        //
        // `setDepthClamp(true)` keeps the fragment and clamps its depth
        // instead — what a caster behind a light's near plane wants. The
        // clip at `w` above still stands: that one is about dividing by
        // nought, and no API's depth clamp lifts it.
        if (!depthClamp && (interpolatedZ < 0.0 || interpolatedZ > 1.0)) {
          continue;
        }
        // The bias after the clip, as every API orders them, and the result
        // held to the depth range.
        final z = bias == 0.0 && !depthClamp
            ? interpolatedZ
            : _asStored((interpolatedZ + bias).clamp(0.0, 1.0));
        final index = y * target.width + x;
        final fate = _fateOf(stencil, stencilState, index, z, depth);
        final op = _operationFor(fate, stencilState);
        // Rejected with nothing to record: gone before the stage runs, which
        // is the early-z every scene without a stencil has always had.
        if (fate != _fatePass && op == StencilOperation.keep) continue;

        // Perspective-correct: interpolate over 1/w and divide back.
        final iw = invW0 * b0 + invW1 * b1 + invW2 * b2;
        for (var v = 0; v < varyingCount; v++) {
          interpolated[v] =
              (varyings0[v] * invW0 * b0 +
                  varyings1[v] * invW1 * b1 +
                  varyings2[v] * invW2 * b2) /
              iw;
        }

        // gl_FragCoord: pixel centre, window depth, and 1/w. Rebuilt rather
        // than reused between fragments, because a stage that kept a reference
        // to it would see the next fragment's values.
        context.coord.setValues(px, py, z, iw);
        context.surface = null;
        context.albedo = null;
        context.debugSurface = null;
        context.fragDepth = null;
        context.source1 = null;
        _statistics.add(PipelineStatistic.fragmentShaderInvocations, 1);
        final color = pipeline.fragment.run(interpolated, bindings, context);
        if (color == null) continue;
        if (stencil != null) _stencilWrite(stencil, index, stencilState, op);
        if (fate != _fatePass) continue;
        _samplesPassed++;

        // Attachment one, when the stage wrote it and the pass has one. Both
        // conditions matter: the lit models always write it and the shadow
        // passes never do, and a pass may have a single attachment either way.
        final surface = context.surface;
        if (surface != null && extra != null) {
          final e = index * 4;
          if (surfaceMask != ColorWriteMask.all) _keep(extra.pixels, e);
          if (surfaceBlend == null) {
            extra.pixels[e] = surface.x;
            extra.pixels[e + 1] = surface.y;
            extra.pixels[e + 2] = surface.z;
            extra.pixels[e + 3] = surface.w;
          } else {
            _blendInto(
              surfaceBlend,
              _blendColor,
              extra.pixels,
              e,
              surface,
              extraStorage!,
            );
          }
          if (surfaceMask != ColorWriteMask.all) {
            _restore(extra.pixels, e, surfaceMask);
          }
        }
        // Attachment two with it: whatever writes the surface writes its
        // colour, black when it named none, as `WriteSurfaceGeometry` does.
        if (surface != null && albedoTarget != null) {
          final e = index * 4;
          final albedo = context.albedo;
          if (albedoMask != ColorWriteMask.all) _keep(albedoTarget.pixels, e);
          albedoTarget.pixels[e] = albedo?.x ?? 0.0;
          albedoTarget.pixels[e + 1] = albedo?.y ?? 0.0;
          albedoTarget.pixels[e + 2] = albedo?.z ?? 0.0;
          albedoTarget.pixels[e + 3] = 1.0;
          if (albedoMask != ColorWriteMask.all) {
            _restore(albedoTarget.pixels, e, albedoMask);
          }
        }

        final at = index * 4;
        final blend = _blend;
        if (colourMask != ColorWriteMask.all) _keep(target.pixels, at);
        if (blend == null) {
          target.pixels[at] = color.x;
          target.pixels[at + 1] = color.y;
          target.pixels[at + 2] = color.z;
          target.pixels[at + 3] = color.w;
        } else {
          _blendInto(
            blend,
            _blendColor,
            target.pixels,
            at,
            color,
            storage,
            context.source1,
          );
        }
        if (colourMask != ColorWriteMask.all) {
          _restore(target.pixels, at, colourMask);
        }

        if (depth != null && _depthWrite && !_depthReadOnly) {
          depth[index] = context.fragDepth ?? z;
        }
      }
    }
  }

  /// The blend equation, factor by factor.
  ///
  /// This used to recognise exactly two states — source-over and additive —
  /// by testing two of their factors, on the argument that a general equation
  /// nothing asked for was a guess about a call site. The third state asked:
  /// [BlendState.keepDestination] is zero and one, which the two tests read
  /// as "one and one" and drew the marking pass's colour straight over the
  /// picture it was meant to leave alone. Every factor is a line here now: the
  /// last four to arrive read [constant], which threw for as long as
  /// `PassEncoder` had no way to set one.
  static void _blendInto(
    BlendState blend,
    Vector4 constant,
    Float32List pixels,
    int at,
    Vector4 source,
    _Storage storage, [
    Vector4? source1,
  ]) {
    final sa = source.w;
    final da = _settled(pixels[at + 3], storage);
    final ba = constant.w;
    final s1a = source1?.w ?? 0.0;
    for (var channel = 0; channel < 3; channel++) {
      final s = source[channel];
      final d = _settled(pixels[at + channel], storage);
      final bc = constant[channel];
      final s1 = source1?[channel] ?? 0.0;
      pixels[at + channel] = _combine(
        blend.colorOperation,
        s *
            _factor(
              blend.sourceColorFactor,
              s,
              sa,
              d,
              da,
              bc,
              ba,
              alpha: false,
              s1: s1,
              s1a: s1a,
            ),
        d *
            _factor(
              blend.destinationColorFactor,
              s,
              sa,
              d,
              da,
              bc,
              ba,
              alpha: false,
              s1: s1,
              s1a: s1a,
            ),
        s,
        d,
      );
    }
    // The alpha channel with every argument read off the alphas, [constant]'s
    // included: GL's `CONSTANT_COLOR` for the alpha channel *is* the constant's
    // alpha, which is why `bc` and `ba` are the same value here and different
    // above.
    pixels[at + 3] = _combine(
      blend.alphaOperation,
      sa *
          _factor(
            blend.sourceAlphaFactor,
            sa,
            sa,
            da,
            da,
            ba,
            ba,
            alpha: true,
            s1: s1a,
            s1a: s1a,
          ),
      da *
          _factor(
            blend.destinationAlphaFactor,
            sa,
            sa,
            da,
            da,
            ba,
            ba,
            alpha: true,
            s1: s1a,
            s1a: s1a,
          ),
      sa,
      da,
    );
  }

  /// [s] and [d] are the two terms with their factors applied; [rawS] and
  /// [rawD] without — which min and max read, since every API defines those
  /// two to ignore the factors.
  static double _combine(
    BlendOperation op,
    double s,
    double d,
    double rawS,
    double rawD,
  ) => switch (op) {
    BlendOperation.add => s + d,
    BlendOperation.subtract => s - d,
    BlendOperation.reverseSubtract => d - s,
    BlendOperation.min => math.min(rawS, rawD),
    BlendOperation.max => math.max(rawS, rawD),
  };

  /// One factor for one channel: [s] and [d] are that channel's source and
  /// destination, [sa] and [da] the two alphas, [bc] the blend constant's own
  /// value for this channel and [ba] its alpha. [alpha] says the channel is
  /// the alpha itself, where the specification pins the saturated factor at
  /// one. [s1] and [s1a] are the fragment's second output for this channel
  /// and its alpha — `FragmentContext.source1`, nought when unwritten.
  static double _factor(
    BlendFactor factor,
    double s,
    double sa,
    double d,
    double da,
    double bc,
    double ba, {
    required bool alpha,
    double s1 = 0.0,
    double s1a = 0.0,
  }) => switch (factor) {
    BlendFactor.zero => 0.0,
    BlendFactor.one => 1.0,
    BlendFactor.sourceColor => s,
    BlendFactor.oneMinusSourceColor => 1.0 - s,
    BlendFactor.sourceAlpha => sa,
    BlendFactor.oneMinusSourceAlpha => 1.0 - sa,
    BlendFactor.destinationColor => d,
    BlendFactor.oneMinusDestinationColor => 1.0 - d,
    BlendFactor.destinationAlpha => da,
    BlendFactor.oneMinusDestinationAlpha => 1.0 - da,
    BlendFactor.sourceAlphaSaturated => alpha ? 1.0 : math.min(sa, 1.0 - da),
    BlendFactor.blendColor => bc,
    BlendFactor.oneMinusBlendColor => 1.0 - bc,
    BlendFactor.blendAlpha => ba,
    BlendFactor.oneMinusBlendAlpha => 1.0 - ba,
    BlendFactor.source1Color => s1,
    BlendFactor.oneMinusSource1Color => 1.0 - s1,
    BlendFactor.source1Alpha => s1a,
    BlendFactor.oneMinusSource1Alpha => 1.0 - s1a,
  };

  /// The depth offset a triangle's fragments take — `setDepthBias`.
  ///
  /// `constant · r + slopeScale · maxSlope`, clamped by the bias's clamp
  /// when that is not nought. `maxSlope` is the larger of the triangle's
  /// window-space depth gradients, which this rasteriser has exactly, since
  /// window depth is a plane across the triangle. `r` is the smallest step
  /// the attachment's *format* resolves — `2⁻¹⁶` and `2⁻²⁴` for the unorm
  /// depths, and for a float depth `2^(e − 23)` with `e` the exponent of the
  /// triangle's largest depth — although the buffer here keeps a 32-bit
  /// float whatever the format: the constant moves a depth the distance it
  /// would move on the hardware the format describes.
  double _biasOf(
    List<double> sx,
    List<double> sy,
    List<double> sz,
    double area,
  ) {
    final bias = _depthBias;
    if (bias == DepthBias.none) return 0.0;
    final d1 = sz[1] - sz[0];
    final d2 = sz[2] - sz[0];
    final dzdx = (d1 * (sy[2] - sy[0]) - d2 * (sy[1] - sy[0])) / area;
    final dzdy = (d2 * (sx[1] - sx[0]) - d1 * (sx[2] - sx[0])) / area;
    final slope = math.max(dzdx.abs(), dzdy.abs());
    final r = switch (_depthFormat) {
      TextureFormat.d16UNormInt => 1.0 / 65536.0,
      TextureFormat.d24UnormS8Uint => 1.0 / 16777216.0,
      _ => _floatResolution(
        [sz[0].abs(), sz[1].abs(), sz[2].abs()].reduce(math.max),
      ),
    };
    final raw = bias.constant * r + bias.slopeScale * slope;
    if (bias.clamp > 0.0) return math.min(raw, bias.clamp);
    if (bias.clamp < 0.0) return math.max(raw, bias.clamp);
    return raw;
  }

  /// One step of a 32-bit float at the magnitude of [z]: `2^(e − 23)`.
  static double _floatResolution(double z) {
    if (z <= 0.0) return math.pow(2.0, -149).toDouble();
    final exponent = (math.log(z) / math.ln2).floor();
    return math.pow(2.0, exponent - 23).toDouble();
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

/// How a target keeps what is written to it.
enum _Storage { float, unorm8, unorm8Srgb }
