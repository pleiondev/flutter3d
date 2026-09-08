/// What WebGPU calls the things `flutter3d_hardware` names, and the places the
/// two do not agree.
///
/// **Pure Dart on purpose.** Nothing here imports `dart:js_interop`, so the
/// whole translation runs and is asserted on the VM — which is the half of this
/// package that can be checked without a browser and a GPU. The interop half is
/// `webgpu_interop.dart`, which imports `dart:js_interop` and so can only be
/// checked in Chrome.
///
/// Every function here returns one of WebGPU's own enumeration strings, spelled
/// as the specification spells it. A string rather than a constant because that
/// is what the API takes: `GPUCullMode` is `"none" | "front" | "back"` and there
/// is nothing else to map onto. `webgpu_formats_test.dart` holds every
/// answer against the specification's own value sets, so a typo is a failed test
/// rather than a pipeline the browser refuses at run time with a message about a
/// dictionary member.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// The texture format WebGPU calls [format], or null where it has none.
///
/// Null is an answer rather than a failure: it is one of the two things
/// `GraphicsDevice.supportsTextureFormat` reports false for — the other being a
/// compression family the device was not granted, which is
/// [gpuTextureFormatFeature] — and the contract already asks a caller to ask.
///
/// **Three of the engine's formats have no WebGPU spelling at all, and no
/// amount of work on this backend will give them one.** They are
/// [TextureFormat.a8UNormInt], which WebGPU dropped in favour of `r8unorm` plus
/// a swizzle in the shader, and [TextureFormat.astc4x4HDR] and
/// [TextureFormat.astc8x8HDR], whose profile no WebGPU feature exposes:
/// `texture-compression-astc` unlocks the LDR block formats and there is no
/// second feature behind it. So those three stay a refusal after the compressed
/// families are asked for and granted, and the refusal is a property of the API
/// rather than a piece of this package nobody has written yet. Nothing in this
/// repository allocates any of the three, which is why they cost a null here and
/// not an argument.
String? gpuTextureFormat(TextureFormat format) => switch (format) {
  TextureFormat.unknown => null,
  TextureFormat.a8UNormInt => null,
  TextureFormat.r8UNormInt => 'r8unorm',
  TextureFormat.r8g8UNormInt => 'rg8unorm',
  TextureFormat.r8g8b8a8UNormInt => 'rgba8unorm',
  TextureFormat.r8g8b8a8UNormIntSRGB => 'rgba8unorm-srgb',
  TextureFormat.b8g8r8a8UNormInt => 'bgra8unorm',
  TextureFormat.b8g8r8a8UNormIntSRGB => 'bgra8unorm-srgb',
  TextureFormat.r32g32b32a32Float => 'rgba32float',
  TextureFormat.r16g16b16a16Float => 'rgba16float',
  TextureFormat.r32Float => 'r32float',
  TextureFormat.s8UInt => 'stencil8',
  TextureFormat.d24UnormS8Uint => 'depth24plus-stencil8',
  TextureFormat.d32FloatS8UInt => 'depth32float-stencil8',
  TextureFormat.bc1RGBAUNormInt => 'bc1-rgba-unorm',
  TextureFormat.bc1RGBAUNormIntSRGB => 'bc1-rgba-unorm-srgb',
  TextureFormat.bc3RGBAUNormInt => 'bc3-rgba-unorm',
  TextureFormat.bc3RGBAUNormIntSRGB => 'bc3-rgba-unorm-srgb',
  TextureFormat.bc5RGUNormInt => 'bc5-rg-unorm',
  TextureFormat.bc7RGBAUNormInt => 'bc7-rgba-unorm',
  TextureFormat.bc7RGBAUNormIntSRGB => 'bc7-rgba-unorm-srgb',
  TextureFormat.etc2RGB8UNormInt => 'etc2-rgb8unorm',
  TextureFormat.etc2RGB8UNormIntSRGB => 'etc2-rgb8unorm-srgb',
  TextureFormat.etc2RGBA8UNormInt => 'etc2-rgba8unorm',
  TextureFormat.etc2RGBA8UNormIntSRGB => 'etc2-rgba8unorm-srgb',
  TextureFormat.astc4x4LDR => 'astc-4x4-unorm',
  TextureFormat.astc4x4LDRSRGB => 'astc-4x4-unorm-srgb',
  TextureFormat.astc8x8LDR => 'astc-8x8-unorm',
  TextureFormat.astc8x8LDRSRGB => 'astc-8x8-unorm-srgb',
  TextureFormat.astc4x4HDR => null,
  TextureFormat.astc8x8HDR => null,
};

/// The adapter feature [format] rides on, or null for one every WebGPU device
/// has.
///
/// **A spelling is not permission.** `rgba8unorm` works on every device;
/// `bc7-rgba-unorm` is a name the specification defines and a device that did
/// not request `texture-compression-bc` refuses outright, allocation and sample
/// alike. So `GraphicsDevice.supportsTextureFormat` is two questions and this is
/// the second: whether the family's feature was granted. `WebGpuDevice.create`
/// asks the adapter which of the three it has and requests exactly those,
/// because requesting one the adapter lacks does not answer with a lesser
/// device — it rejects the promise, and a game that will not start is a worse
/// answer than a texture left out.
///
/// The three names are written here rather than taken from `GpuFeature`, which
/// carries the same three: that class lives in `webgpu_interop.dart`, which
/// imports `dart:js_interop` and cannot be reached from a library that runs on
/// the VM. `webgpu_interop_test.dart` — which runs in a browser and can import
/// both — holds the two statements against each other, so the duplication is
/// checked rather than trusted.
///
/// Null for [TextureFormat.astc4x4HDR] and [TextureFormat.astc8x8HDR], which is
/// not a claim that they need nothing: [gpuTextureFormat] has already answered
/// null for both, because no WebGPU feature exposes the HDR profile of ASTC at
/// all. A format with no spelling never reaches this question.
String? gpuTextureFormatFeature(TextureFormat format) => switch (format) {
  TextureFormat.bc1RGBAUNormInt ||
  TextureFormat.bc1RGBAUNormIntSRGB ||
  TextureFormat.bc3RGBAUNormInt ||
  TextureFormat.bc3RGBAUNormIntSRGB ||
  TextureFormat.bc5RGUNormInt ||
  TextureFormat.bc7RGBAUNormInt ||
  TextureFormat.bc7RGBAUNormIntSRGB => 'texture-compression-bc',
  TextureFormat.etc2RGB8UNormInt ||
  TextureFormat.etc2RGB8UNormIntSRGB ||
  TextureFormat.etc2RGBA8UNormInt ||
  TextureFormat.etc2RGBA8UNormIntSRGB => 'texture-compression-etc2',
  TextureFormat.astc4x4LDR ||
  TextureFormat.astc4x4LDRSRGB ||
  TextureFormat.astc8x8LDR ||
  TextureFormat.astc8x8LDRSRGB => 'texture-compression-astc',
  _ => null,
};

/// The row stride and the number of rows `writeTexture` wants for a
/// [width] by [height] level of a block-compressed [format].
///
/// **Both numbers are counted in blocks, and that is the whole trap.** For
/// `rgba8unorm` the stride is a row of texels and `rowsPerImage` is a row count;
/// for `bc7-rgba-unorm` the stride is a row of *blocks* — sixteen bytes each
/// covering four texels across — and `rowsPerImage` counts block rows, so a
/// 64x64 BC7 level is sixteen rows of 256 bytes rather than sixty-four rows of
/// anything. Handed the texel arithmetic instead, the browser reads four times
/// the bytes that exist and refuses the write.
///
/// The rounding is up, which is what makes a chain work: level three of a 32x32
/// ASTC 8x8 texture is 4x4 texels and still one whole block, and a level smaller
/// than a block is stored as one block whatever it covers.
({int bytesPerRow, int rowsPerImage, int byteLength}) gpuBlockLayoutOf(
  TextureFormat format,
  int width,
  int height,
) {
  final block = format.blockLayout;
  final wide = (width + block.blockWidth - 1) ~/ block.blockWidth;
  final high = (height + block.blockHeight - 1) ~/ block.blockHeight;
  final stride = wide * block.bytesPerBlock;
  return (bytesPerRow: stride, rowsPerImage: high, byteLength: stride * high);
}

/// The blend factor WebGPU calls [factor], or null where it has none.
///
/// **Two of the fifteen come back null, and they are the reason this function
/// answers with null at all.** OpenGL splits the blend constant into
/// `CONSTANT_COLOR` and `CONSTANT_ALPHA`: the first multiplies each channel by
/// the matching channel of the constant, the second multiplies every channel by
/// the constant's alpha. Metal spells the same split, Vulkan spells it, and
/// `BlendFactor` mirrors it — [BlendFactor.blendColor] against
/// [BlendFactor.blendAlpha].
///
/// WebGPU has `"constant"` and `"one-minus-constant"` and nothing else. In the
/// alpha equation `"constant"` already means the constant's alpha, so
/// [BlendFactor.blendAlpha] is expressible *there*; in the colour equation there
/// is no way to say "the constant's alpha in every channel" at all. So the
/// factor is not a translation that lands on the wrong value — it is a term the
/// hardware interface can ask for and this API cannot form.
///
/// See `webgpuContractGaps`, where this is the one entry that cannot be answered
/// from the backend alone.
String? gpuBlendFactor(BlendFactor factor) => switch (factor) {
  BlendFactor.zero => 'zero',
  BlendFactor.one => 'one',
  BlendFactor.sourceColor => 'src',
  BlendFactor.oneMinusSourceColor => 'one-minus-src',
  BlendFactor.sourceAlpha => 'src-alpha',
  BlendFactor.oneMinusSourceAlpha => 'one-minus-src-alpha',
  BlendFactor.destinationColor => 'dst',
  BlendFactor.oneMinusDestinationColor => 'one-minus-dst',
  BlendFactor.destinationAlpha => 'dst-alpha',
  BlendFactor.oneMinusDestinationAlpha => 'one-minus-dst-alpha',
  BlendFactor.sourceAlphaSaturated => 'src-alpha-saturated',
  BlendFactor.blendColor => 'constant',
  BlendFactor.oneMinusBlendColor => 'one-minus-constant',
  BlendFactor.blendAlpha => null,
  BlendFactor.oneMinusBlendAlpha => null,
};

String gpuBlendOperation(BlendOperation operation) => switch (operation) {
  BlendOperation.add => 'add',
  BlendOperation.subtract => 'subtract',
  BlendOperation.reverseSubtract => 'reverse-subtract',
};

String gpuCompareFunction(CompareFunction compare) => switch (compare) {
  CompareFunction.never => 'never',
  CompareFunction.always => 'always',
  CompareFunction.less => 'less',
  CompareFunction.equal => 'equal',
  CompareFunction.lessEqual => 'less-equal',
  CompareFunction.greater => 'greater',
  CompareFunction.notEqual => 'not-equal',
  CompareFunction.greaterEqual => 'greater-equal',
};

/// [StencilOperation.setToReferenceValue] is WebGPU's `"replace"`, which is the
/// one name in this table that is not the engine's word for the same thing.
String gpuStencilOperation(StencilOperation operation) => switch (operation) {
  StencilOperation.keep => 'keep',
  StencilOperation.zero => 'zero',
  StencilOperation.setToReferenceValue => 'replace',
  StencilOperation.incrementClamp => 'increment-clamp',
  StencilOperation.decrementClamp => 'decrement-clamp',
  StencilOperation.invert => 'invert',
  StencilOperation.incrementWrap => 'increment-wrap',
  StencilOperation.decrementWrap => 'decrement-wrap',
};

String gpuPrimitiveTopology(PrimitiveType type) => switch (type) {
  PrimitiveType.triangle => 'triangle-list',
  PrimitiveType.triangleStrip => 'triangle-strip',
  PrimitiveType.line => 'line-list',
  PrimitiveType.lineStrip => 'line-strip',
  PrimitiveType.point => 'point-list',
};

String gpuCullMode(CullMode mode) => switch (mode) {
  CullMode.none => 'none',
  CullMode.frontFace => 'front',
  CullMode.backFace => 'back',
};

/// **Straight through — and it was written crossed first, on an argument that
/// turned out to be wrong.**
///
/// The contract does not say which space a winding is measured in, and it has
/// not needed to: the three implementations agree by accident of their APIs.
/// OpenGL takes the signed area in window coordinates, whose y runs *up*, so
/// `glFrontFace(CCW)` is counter-clockwise as the clip-space triangle was wound.
/// The software rasteriser measures in its own window space, whose y runs down,
/// and says so where it tests the sign — same answer, opposite arithmetic.
/// Impeller's is Metal's and lands in the same place. So
/// [WindingOrder.counterClockwise] means counter-clockwise **in clip space**,
/// with y up, and that is what every mesh in the engine is wound as.
///
/// WebGPU's framebuffer coordinates run y down, the same choice Vulkan made —
/// and a Vulkan port genuinely does have to cross the winding over or flip the
/// viewport. Reasoning from that, this function returned `"cw"` for
/// [WindingOrder.counterClockwise], and it looked like the careful answer.
///
/// **The measurement says otherwise, and the measurement is what is here.** A
/// triangle wound counter-clockwise in clip space, drawn through the spike this
/// table came from, in
/// Chrome, survives `CullMode.backFace` under `"ccw"` and is discarded under
/// `"cw"` — the whole two-by-two of winding against cull mode, which is
/// `webgpu_triangle_test.dart`. So WebGPU agrees with the other three about what
/// counter-clockwise means, and the fourth backend needs no correction here at
/// all.
///
/// The function survives its own non-finding because the argument for the
/// inversion is a good one and somebody will make it again. What settles it is a
/// draw, and there is one.
String gpuFrontFace(WindingOrder order) => switch (order) {
  WindingOrder.counterClockwise => 'ccw',
  WindingOrder.clockwise => 'cw',
};

/// [LoadAction.dontCare] becomes `"clear"`, which is a choice rather than a
/// translation: WebGPU has `"load"` and `"clear"` and no third option meaning
/// "the contents are undefined". Clearing is the one of the two that cannot
/// leak the previous frame into a target whose contents the caller said it did
/// not care about, and a caller that did not care cannot be harmed by it.
String gpuLoadOp(LoadAction action) => switch (action) {
  LoadAction.dontCare => 'clear',
  LoadAction.load => 'load',
  LoadAction.clear => 'clear',
};

/// The store operation, which in WebGPU says nothing about resolving: a resolve
/// is `resolveTarget` on the attachment, and the store op then says whether the
/// multisampled texture is kept as well.
///
/// So [StoreAction.multisampleResolve] is `"discard"` beside a resolve target
/// and [StoreAction.storeAndMultisampleResolve] is `"store"` beside the same
/// one — see [gpuResolves], which is the other half of the same answer.
String gpuStoreOp(StoreAction action) => switch (action) {
  StoreAction.dontCare => 'discard',
  StoreAction.store => 'store',
  StoreAction.multisampleResolve => 'discard',
  StoreAction.storeAndMultisampleResolve => 'store',
};

/// Whether [action] asks for a resolve, which WebGPU takes as an attachment
/// field rather than as part of the store operation.
bool gpuResolves(StoreAction action) =>
    action == StoreAction.multisampleResolve ||
    action == StoreAction.storeAndMultisampleResolve;

String gpuAddressMode(SamplerAddressMode mode) => switch (mode) {
  SamplerAddressMode.clampToEdge => 'clamp-to-edge',
  SamplerAddressMode.repeat => 'repeat',
  SamplerAddressMode.mirror => 'mirror-repeat',
};

String gpuFilterMode(MinMagFilter filter) => switch (filter) {
  MinMagFilter.nearest => 'nearest',
  MinMagFilter.linear => 'linear',
};

String gpuMipmapFilterMode(MipFilter filter) => switch (filter) {
  MipFilter.nearest => 'nearest',
  MipFilter.linear => 'linear',
};

String gpuIndexFormat(IndexType type) => switch (type) {
  IndexType.int16 => 'uint16',
  IndexType.int32 => 'uint32',
};

String gpuVertexFormat(VertexFormat format) => switch (format) {
  VertexFormat.float32 => 'float32',
  VertexFormat.float32x2 => 'float32x2',
  VertexFormat.float32x3 => 'float32x3',
  VertexFormat.float32x4 => 'float32x4',
  VertexFormat.uint32 => 'uint32',
  VertexFormat.uint32x2 => 'uint32x2',
  VertexFormat.uint32x3 => 'uint32x3',
  VertexFormat.uint32x4 => 'uint32x4',
  VertexFormat.sint32 => 'sint32',
  VertexFormat.sint32x2 => 'sint32x2',
  VertexFormat.sint32x3 => 'sint32x3',
  VertexFormat.sint32x4 => 'sint32x4',
};

String gpuVertexStepMode(VertexStepMode mode) => switch (mode) {
  VertexStepMode.vertex => 'vertex',
  VertexStepMode.instance => 'instance',
};

/// The row stride `copyTextureToBuffer` demands for a [width]-pixel region of
/// four-byte texels: a multiple of 256, whatever the region is.
///
/// **A backend detail that reaches the contract's promise and has to be undone
/// before it does.** `GraphicsDevice.readback` promises "the region's own width
/// times four per row"; WebGPU will not copy into a buffer whose rows are packed
/// tighter than 256 bytes. So the copy is made wide and the answer is repacked,
/// and the one-pixel readback the editor's pick uses — the cheapest region there
/// is — is the case where the padding is 252 bytes out of 256.
///
/// Here rather than inline because the arithmetic is the sort that is wrong by
/// one for exactly the widths nobody tries: a width of 64 is already aligned and
/// must not be rounded up to 512.
int paddedBytesPerRow(int width) {
  const alignment = 256;
  final packed = width * 4;
  final over = packed % alignment;
  return over == 0 ? packed : packed + (alignment - over);
}

/// [bytes] as `queue.writeBuffer` will take them: a length that is a multiple of
/// four, padded with zeros where it is not.
///
/// **The engine hands over lengths that are not.** `bindIndexData` with three
/// sixteen-bit indices — the full-screen triangle, and the smallest draw there
/// is — is six bytes, and `writeBuffer` refuses anything that is not a multiple
/// of four with an `OperationError` naming the number of bytes. So does a
/// vertex buffer of an odd number of half-floats, if one ever arrives.
///
/// The padding is invisible to the draw: the index count says how many to read
/// and the two zero bytes past the end are never reached. Rounding the *buffer*
/// up and writing the unpadded bytes into it is what fails, because the
/// constraint is on the write and not on the allocation — which is worth
/// stating, because the two look like the same fix.
Uint8List gpuWritableBytes(ByteData bytes) {
  final source = bytes.buffer.asUint8List(
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  if (bytes.lengthInBytes % 4 == 0) return source;
  return Uint8List((bytes.lengthInBytes + 3) & ~3)..setAll(0, source);
}

/// What WebGPU bakes into a render pipeline that `PassEncoder` sets per draw.
///
/// **The divergence `command_encoder.dart` names for Vulkan, arriving a second
/// time.** Cull mode, winding, depth compare, depth write, topology and the
/// blend equation are pass state on Impeller and methods on `PassEncoder`; in
/// WebGPU every one of them is a field of `GPURenderPipeline`, and so are the
/// attachment formats and the sample count, which the pass only learns when it
/// is opened. A backend therefore cannot build anything at
/// `GraphicsDevice.createPipeline` — it records the stage pair, accumulates the
/// setters, and looks a real pipeline up at the draw.
///
/// This is that lookup key as the spike wrote it, and **the backend does not
/// use it any more**: `WebGpuPipelineSignature` in `webgpu_pipeline_cache.dart`
/// is what a draw is actually keyed by, because three things WebGPU also bakes
/// into a pipeline are missing from the ten fields below — the vertex layout,
/// the stencil, and a blend equation per attachment rather than for attachment
/// zero. That file's header says what each of them costs when it is left out.
/// This one stays because it is exported from a published barrel and its tests
/// are what hold the ten spellings to the specification; it goes at the next
/// major.
///
/// A value type with `==` for the same reason `BlendState` is one: the map
/// behind it is consulted once per draw.
///
/// **Every field here is a field the engine actually changes inside one pass.**
/// The mesh loop sets winding and cull per node and blend per material, so a
/// scene with opaque and transparent materials and a mirrored prop is already
/// four keys before anything else moves.
final class WebGpuPipelineKey {
  const WebGpuPipelineKey({
    required this.pipeline,
    required this.topology,
    required this.cullMode,
    required this.frontFace,
    required this.depthCompare,
    required this.depthWrite,
    required this.blend,
    required this.colorFormats,
    required this.depthFormat,
    required this.sampleCount,
  });

  /// The stage pair, by the name `PipelineHandle` carries.
  final String pipeline;

  final String topology;
  final String cullMode;
  final String frontFace;
  final String depthCompare;
  final bool depthWrite;

  /// The blend equation of attachment zero, or null for blending off. One
  /// attachment because that is as far as the spike this key came from went; a
  /// backend keying on the whole list is what WebGPU is happy to honour and the
  /// two hardware
  /// backends are not — see `PassEncoder.setBlend`.
  final BlendState? blend;

  /// The colour attachments' formats, in shader output order. Part of the key
  /// because they are part of the pipeline in WebGPU: the same stage pair drawn
  /// into the HDR target and into the eight-bit one is two pipelines.
  final List<String> colorFormats;

  final String? depthFormat;
  final int sampleCount;

  @override
  bool operator ==(Object other) =>
      other is WebGpuPipelineKey &&
      other.pipeline == pipeline &&
      other.topology == topology &&
      other.cullMode == cullMode &&
      other.frontFace == frontFace &&
      other.depthCompare == depthCompare &&
      other.depthWrite == depthWrite &&
      other.blend == blend &&
      other.depthFormat == depthFormat &&
      other.sampleCount == sampleCount &&
      _sameFormats(other.colorFormats, colorFormats);

  static bool _sameFormats(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    pipeline,
    topology,
    cullMode,
    frontFace,
    depthCompare,
    depthWrite,
    blend,
    Object.hashAll(colorFormats),
    depthFormat,
    sampleCount,
  );

  @override
  String toString() =>
      'WebGpuPipelineKey($pipeline, $topology, cull: $cullMode, '
      'front: $frontFace, depth: $depthCompare, write: $depthWrite, '
      'blend: ${blend == null ? 'off' : 'on'}, '
      'targets: ${colorFormats.join('+')}'
      '${depthFormat == null ? '' : '/$depthFormat'}, x$sampleCount)';
}
