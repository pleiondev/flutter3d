/// What a draw looks a real pipeline up by, and the map it looks it up in.
///
/// **Pure Dart on purpose**, like `webgpu_formats.dart` beside it: nothing here
/// reaches for `dart:js_interop`, so the whole of the cache's behaviour — which
/// states are one pipeline and which are two — is asserted on the VM rather
/// than only in a browser with a GPU. The pipeline objects themselves are the
/// type parameter of [WebGpuPipelineCache], which is what lets a test hand it
/// strings and count what was built.
///
/// ## Why the signature is wider than the spike's key
///
/// `WebGpuPipelineKey` in `webgpu_formats.dart` came out of the spike that
/// proved this structure with one triangle. It carries ten fields, and three of
/// the things the spike never had are missing from it, each of which two
/// different draws can disagree about while every one of the ten matches:
///
///  1. **The vertex layout.** `GraphicsDevice.createPipeline` says it outright:
///     "A caller that caches pipelines must key on the layout as well as on the
///     pair. Two layouts over one stage pair are two different pipelines, and
///     handing back the first for the second is a draw that reads instance data
///     as vertices — which draws a picture rather than raising anything." An
///     instanced mesh and a plain one run the same stage pair with the same
///     cull mode into the same target; the layout is the only thing that
///     differs, and it is the whole difference.
///  2. **The stencil.** WebGPU puts the compare, the three operations and the
///     two masks in `GPUDepthStencilState`, so the x-ray stage's marking draw
///     and the silhouette draw after it are two pipelines. Only the reference
///     value is dynamic, which is why `setStencilReference` reaches the pass
///     and nothing else about the test does.
///  3. **A blend equation per attachment.** The spike keyed on one, because it
///     drew into one. WebGPU gives every colour target its own
///     `GPUColorTargetState`, which is the thing this backend can honour and
///     the other two cannot — see `PassEncoder.setBlend`, which calls the
///     attachment index a hint. Keyed as a list, so honouring the index is a
///     property of the cache rather than a promise the encoder makes and the
///     map quietly breaks.
///
/// The fourth is [stripIndexFormat], which is not a divergence so much as a
/// corner: a strip pipeline settles its restart value when it is built, so the
/// index width of a strip draw belongs here and the index width of a list draw
/// does not.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// [layout] as a string two layouts can be compared by.
///
/// **A string rather than structural equality on the layout objects**, because
/// `VertexLayoutSpec`, `BufferLayout` and `InputAttribute` are plain values
/// with no `==` — they were written to describe a pipeline once, not to be
/// hashed once a draw. Deriving equality by hand over three nested lists is the
/// sort of thing that is right until somebody adds a field to one of them; a
/// rendering of every field is wrong the moment a field is added *and says so*,
/// because a field left out of the rendering is a field left out of the text.
///
/// Rendered once per pipeline, at `createPipeline`, and never on the draw path.
String webgpuVertexLayoutFingerprint(VertexLayoutSpec layout) =>
    layout.buffers.map(_bufferFingerprint).join('|');

String _bufferFingerprint(BufferLayout buffer) {
  final attributes = buffer.attributes
      .map(
        (InputAttribute a) => '${a.name}@${a.offsetInBytes}.${a.format.name}',
      )
      .join(',');
  return '${buffer.strideInBytes}/${buffer.stepMode.name}:$attributes';
}

/// [front] and [back] as a string, or null where the test is off on both faces.
///
/// Null rather than the rendering of two disabled states, so that the ordinary
/// pass — which never mentions the stencil — makes one signature rather than
/// one that merely happens to match.
String? webgpuStencilFingerprint(StencilState? front, StencilState? back) {
  if (front == null && back == null) return null;
  if ((front ?? StencilState.disabled) == StencilState.disabled &&
      (back ?? StencilState.disabled) == StencilState.disabled) {
    return null;
  }
  String render(StencilState? state) =>
      (state ?? StencilState.disabled).toString();
  return '${render(front)}/${render(back)}';
}

/// Everything WebGPU bakes into a `GPURenderPipeline` that this contract sets
/// somewhere else.
///
/// A value type with `==` because the map behind it is consulted once per draw.
/// Every field is one the engine genuinely changes inside a single pass: the
/// mesh loop sets winding and cull per node and blend per material, so a scene
/// with opaque and transparent materials and one mirrored prop is four
/// signatures before anything else moves.
final class WebGpuPipelineSignature {
  WebGpuPipelineSignature({
    required this.pipeline,
    required this.vertexLayout,
    required this.topology,
    required this.stripIndexFormat,
    required this.cullMode,
    required this.frontFace,
    required this.depthCompare,
    required this.depthWrite,
    required this.stencil,
    required List<BlendState?> blends,
    required List<String> colorFormats,
    required this.depthFormat,
    required this.sampleCount,
  }) : blends = List<BlendState?>.unmodifiable(blends),
       colorFormats = List<String>.unmodifiable(colorFormats);

  /// The stage pair, by the name `PipelineHandle` carries.
  final String pipeline;

  /// The vertex layout, as [webgpuVertexLayoutFingerprint] renders it. See the
  /// library comment for why leaving this out draws a picture instead of
  /// raising anything.
  final String vertexLayout;

  final String topology;

  /// The index width a strip's restart value is read at, or null for a list
  /// topology — which is every draw in this engine so far.
  final String? stripIndexFormat;

  final String cullMode;
  final String frontFace;
  final String depthCompare;
  final bool depthWrite;

  /// The stencil test, as [webgpuStencilFingerprint] renders it, or null where
  /// it is off.
  final String? stencil;

  /// One blend equation per colour attachment, null where blending is off.
  /// Shorter than [colorFormats] when nothing has set a state for the later
  /// attachments, which reads as "off" — the same thing a null entry means.
  final List<BlendState?> blends;

  /// The colour attachments' formats, in shader output order. Part of a
  /// pipeline in WebGPU: the same stage pair drawn into the HDR target and into
  /// the eight-bit one is two pipelines.
  final List<String> colorFormats;

  final String? depthFormat;
  final int sampleCount;

  @override
  bool operator ==(Object other) =>
      other is WebGpuPipelineSignature &&
      other.pipeline == pipeline &&
      other.vertexLayout == vertexLayout &&
      other.topology == topology &&
      other.stripIndexFormat == stripIndexFormat &&
      other.cullMode == cullMode &&
      other.frontFace == frontFace &&
      other.depthCompare == depthCompare &&
      other.depthWrite == depthWrite &&
      other.stencil == stencil &&
      other.depthFormat == depthFormat &&
      other.sampleCount == sampleCount &&
      _same<BlendState?>(other.blends, blends) &&
      _same<String>(other.colorFormats, colorFormats);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    pipeline,
    vertexLayout,
    topology,
    stripIndexFormat,
    cullMode,
    frontFace,
    depthCompare,
    depthWrite,
    stencil,
    Object.hashAll(blends),
    Object.hashAll(colorFormats),
    depthFormat,
    sampleCount,
  );

  @override
  String toString() =>
      'WebGpuPipelineSignature($pipeline, $topology, '
      'layout: $vertexLayout, cull: $cullMode, front: $frontFace, '
      'depth: $depthCompare, write: $depthWrite, '
      'stencil: ${stencil ?? 'off'}, '
      'blend: ${blends.map((BlendState? b) => b == null ? 'off' : 'on').join('+')}, '
      'targets: ${colorFormats.join('+')}'
      '${depthFormat == null ? '' : '/$depthFormat'}, x$sampleCount)';
}

/// The pipelines this device has built, by the signature that produced each.
///
/// Generic over the pipeline object so that this file, and the tests that hold
/// it, need no browser. The device instantiates it over `GPURenderPipeline`;
/// `webgpu_pipeline_cache_test.dart` instantiates it over `String` and counts
/// how often the builder ran, which is the only way to ask "did the cache tell
/// these two draws apart" without a GPU in the room.
///
/// **Shared across passes on purpose.** The signature already carries the
/// attachment formats and the sample count, so a pipeline built for one pass is
/// valid in the next pass that matches — which for a frame drawing the same
/// meshes into the same targets is every pass after the first.
final class WebGpuPipelineCache<T extends Object> {
  final Map<WebGpuPipelineSignature, T> _built = <WebGpuPipelineSignature, T>{};

  /// How many distinct pipelines have been built. What `dispose` drops, and
  /// what a test asserts a cache hit by.
  int get length => _built.length;

  /// The pipeline for [signature], built by [build] the first time it is asked
  /// for.
  T get(WebGpuPipelineSignature signature, T Function() build) =>
      _built[signature] ??= build();

  /// Forgets everything. Called from `dispose`, where the device that owns the
  /// pipelines is going: a `GPURenderPipeline` has no `destroy` of its own and
  /// dies with its device.
  void clear() => _built.clear();
}
