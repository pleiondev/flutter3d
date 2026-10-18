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
///
/// **1.0 added three more, for the same reason as the first three.** The
/// contract's `setDepthBias`, `setColorWriteMask` and `setDepthClamp` are
/// per-draw setters, and WebGPU bakes `depthBias`, a target's `writeMask` and
/// `unclippedDepth` into the pipeline. A shadow caster drawn with a bias and
/// the same mesh drawn without one are two pipelines; a key without the bias
/// hands the second the first and the acne comes back. Dual-source factors
/// and min/max operations need no field of their own: they are values of the
/// [BlendState]s already in [blends].
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

/// [layout] as a string two layouts can be compared by.
///
/// **A string rather than structural equality on the layout objects**, because
/// `VertexLayoutDescriptor`, `BufferLayout` and `InputAttribute` are plain values
/// with no `==` — they were written to describe a pipeline once, not to be
/// hashed once a draw. Deriving equality by hand over three nested lists is the
/// sort of thing that is right until somebody adds a field to one of them; a
/// rendering of every field is wrong the moment a field is added *and says so*,
/// because a field left out of the rendering is a field left out of the text.
///
/// Rendered once per pipeline, at `createPipeline`, and never on the draw path.
String webgpuVertexLayoutFingerprint(VertexLayoutDescriptor layout) =>
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
  /// A signature of every field. Optional ones default to the ordinary
  /// pass: no alpha to coverage, no modules, no depth bias, every channel
  /// written and depth clipped.
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
    this.alphaToCoverage = false,
    this.vertexModule,
    this.fragmentModule,
    this.depthBias = DepthBias.none,
    List<ColorWriteMask> writeMasks = const <ColorWriteMask>[],
    this.unclippedDepth = false,
  }) : blends = List<BlendState?>.unmodifiable(blends),
       colorFormats = List<String>.unmodifiable(colorFormats),
       writeMasks = List<ColorWriteMask>.unmodifiable(writeMasks);

  /// `depthBias`, `depthBiasSlopeScale` and `depthBiasClamp` —
  /// `PassEncoder.setDepthBias`.
  final DepthBias depthBias;

  /// One write mask per colour attachment — `PassEncoder.setColorWriteMask`.
  /// Shorter than [colorFormats] where nothing set the later ones, which
  /// reads as [ColorWriteMask.all].
  final List<ColorWriteMask> writeMasks;

  /// `unclippedDepth` — `PassEncoder.setDepthClamp`.
  final bool unclippedDepth;

  /// This signature with another stage pair and vertex layout in it, and
  /// every field of the draw's state as it was: the same state, asked of a
  /// different pipeline. What `createPipelineAsync` warms a new pair with.
  WebGpuPipelineSignature withStages({
    required String pipeline,
    required Object? vertexModule,
    required Object? fragmentModule,
    required String vertexLayout,
  }) => WebGpuPipelineSignature(
    pipeline: pipeline,
    vertexModule: vertexModule,
    fragmentModule: fragmentModule,
    vertexLayout: vertexLayout,
    topology: topology,
    stripIndexFormat: stripIndexFormat,
    cullMode: cullMode,
    frontFace: frontFace,
    depthCompare: depthCompare,
    depthWrite: depthWrite,
    stencil: stencil,
    blends: blends,
    colorFormats: colorFormats,
    depthFormat: depthFormat,
    sampleCount: sampleCount,
    alphaToCoverage: alphaToCoverage,
    depthBias: depthBias,
    writeMasks: writeMasks,
    unclippedDepth: unclippedDepth,
  );

  /// The write mask of attachment [index], all channels where none was set.
  ColorWriteMask writeMaskOf(int index) =>
      index < writeMasks.length ? writeMasks[index] : ColorWriteMask.all;

  /// The stage pair, by the name `PipelineHandle` carries.
  ///
  /// **Not unique on its own**, which is why [vertexModule] and
  /// [fragmentModule] sit beside it. Two layered libraries both answering
  /// `Pbr` make one string for two different stage pairs, and a reload swaps
  /// the code behind a name without changing the name — so a cache keyed on
  /// this alone hands back the pipeline built from whichever modules got there
  /// first, and a refreshed bundle draws its old code for ever.
  final String pipeline;

  /// The compiled modules the pipeline is built from, compared by identity.
  ///
  /// Null in a signature built without a device, which is what the VM tests
  /// do; the encoder always fills both.
  final Object? vertexModule;

  /// The fragment half of the pair, compared by identity as [vertexModule]
  /// is; null in a signature built without a device.
  final Object? fragmentModule;

  /// The vertex layout, as [webgpuVertexLayoutFingerprint] renders it. See the
  /// library comment for why leaving this out draws a picture instead of
  /// raising anything.
  final String vertexLayout;

  /// The `GPUPrimitiveTopology` string, such as `"triangle-list"`.
  final String topology;

  /// The index width a strip's restart value is read at, or null for a list
  /// topology — which is every draw in this engine so far.
  final String? stripIndexFormat;

  /// The `GPUCullMode` string: `"none"`, `"front"` or `"back"`.
  final String cullMode;

  /// The `GPUFrontFace` string, `"ccw"` or `"cw"`, measured in clip space.
  final String frontFace;

  /// The depth test's `GPUCompareFunction` string.
  final String depthCompare;

  /// Whether passing fragments write depth.
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

  /// The depth attachment's texture format string, or null where the pass
  /// has no depth attachment.
  final String? depthFormat;

  /// Samples per texel of every attachment: one, or four when multisampled.
  final int sampleCount;

  /// `alphaToCoverageEnabled` — `P7`. Part of a pipeline in WebGPU, so a
  /// masked material drawn with and without it is two.
  final bool alphaToCoverage;

  @override
  bool operator ==(Object other) =>
      other is WebGpuPipelineSignature &&
      other.pipeline == pipeline &&
      identical(other.vertexModule, vertexModule) &&
      identical(other.fragmentModule, fragmentModule) &&
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
      other.alphaToCoverage == alphaToCoverage &&
      other.depthBias == depthBias &&
      other.unclippedDepth == unclippedDepth &&
      _sameMasks(other) &&
      _same<BlendState?>(other.blends, blends) &&
      _same<String>(other.colorFormats, colorFormats);

  /// Compared as [writeMaskOf] reads them over the attachments, so a list
  /// that stops early and one that spells the trailing `all` out are one key.
  bool _sameMasks(WebGpuPipelineSignature other) => Iterable<int>.generate(
    colorFormats.length,
  ).every((int i) => other.writeMaskOf(i) == writeMaskOf(i));

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
    identityHashCode(vertexModule),
    identityHashCode(fragmentModule),
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
    alphaToCoverage,
    depthBias,
    unclippedDepth,
    // The masks as `writeMaskOf` reads them over the attachments, so the two
    // spellings `_sameMasks` calls one key hash alike.
    Object.hashAll(<int>[
      for (var i = 0; i < colorFormats.length; i++) writeMaskOf(i).bits,
    ]),
  );

  @override
  String toString() =>
      'WebGpuPipelineSignature($pipeline, $topology, '
      'layout: $vertexLayout, cull: $cullMode, front: $frontFace, '
      'depth: $depthCompare, write: $depthWrite, '
      'stencil: ${stencil ?? 'off'}, '
      'blend: ${blends.map((BlendState? b) => b == null ? 'off' : 'on').join('+')}, '
      'targets: ${colorFormats.join('+')}'
      '${depthFormat == null ? '' : '/$depthFormat'}, x$sampleCount'
      '${alphaToCoverage ? ', alpha to coverage' : ''}'
      '${depthBias == DepthBias.none ? '' : ', $depthBias'}'
      '${unclippedDepth ? ', unclipped depth' : ''}'
      '${writeMasks.every((ColorWriteMask m) => m == ColorWriteMask.all) ? '' : ', masks: ${writeMasks.join('+')}'})';
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

  /// The states sent to be built off the frame, by the frame that sent each.
  final Map<WebGpuPipelineSignature, int> _pending =
      <WebGpuPipelineSignature, int>{};

  /// How many distinct pipelines have been built. What `dispose` drops, and
  /// what a test asserts a cache hit by.
  int get length => _built.length;

  /// The pipeline for [signature], built by [build] the first time it is asked
  /// for.
  T get(WebGpuPipelineSignature signature, T Function() build) =>
      _built[signature] ??= build();

  /// The pipeline a draw in [frame] uses for [signature], or null when the
  /// draw is skipped while the pipeline is built off the frame.
  ///
  /// **The browser compiles a new state on its own threads, and the frame
  /// does not wait for it.** `createRenderPipeline` hands back an object at
  /// once and stalls the queue at the first draw with it until the driver
  /// has compiled it, which on a phone is tens of milliseconds a state; a
  /// level that brings in a new material paid it in the frame that drew the
  /// material first. So where [defer] is true, the first draw in a state
  /// calls [buildLater] (`createRenderPipelineAsync`, whose answer arrives
  /// through [offer] or [settle]) and is skipped, as is every draw in that
  /// state until the answer comes.
  ///
  /// **The fallback is one frame.** A draw in a later frame than the one
  /// that sent the build, which still finds no answer, builds in place with
  /// [build], and the late answer is then dropped by [offer]: a draw is
  /// missing from one frame at most, never from as many as a slow compiler
  /// takes. Where [defer] is false — a frame drawn once and read back, which
  /// is every golden — the draw builds in place, as [get] does.
  T? forDraw(
    WebGpuPipelineSignature signature, {
    required int frame,
    required bool defer,
    required T Function() build,
    required void Function() buildLater,
  }) {
    final built = _built[signature];
    if (built != null) return built;
    final sent = _pending[signature];
    if (!defer || (sent != null && sent < frame)) {
      _pending.remove(signature);
      return _built[signature] = build();
    }
    if (sent == null) {
      _pending[signature] = frame;
      buildLater();
    }
    return null;
  }

  /// Whether a build for [signature] was sent off the frame and has not
  /// answered.
  bool isPending(WebGpuPipelineSignature signature) =>
      _pending.containsKey(signature);

  /// Whether a pipeline for [signature] is built.
  bool contains(WebGpuPipelineSignature signature) =>
      _built.containsKey(signature);

  /// Keeps [pipeline] for [signature] unless one is already there — how a
  /// pipeline built asynchronously arrives, after a draw may have built the
  /// same one in the meantime, which then stands. Answers the one kept.
  T offer(WebGpuPipelineSignature signature, T pipeline) {
    _pending.remove(signature);
    return _built.putIfAbsent(signature, () => pipeline);
  }

  /// Stops waiting for a build of [signature] sent off the frame, which the
  /// browser refused: the next draw in that state asks again rather than
  /// taking the fallback and building what was just refused.
  void settle(WebGpuPipelineSignature signature) => _pending.remove(signature);

  /// Forgets the pipeline built for [signature], so the next draw that asks
  /// builds it again: what a pipeline the browser refused on its error scope
  /// leaves behind.
  void forget(WebGpuPipelineSignature signature) => _built.remove(signature);

  /// Forgets every pipeline built from [stages], in whatever draw state:
  /// what `releasePipeline` leaves once no handle over them is left. Answers
  /// how many went.
  ///
  /// A build of those stages still out off the frame stops being waited
  /// for, so what it brings back is dropped rather than cached for a
  /// pipeline nobody holds.
  int forgetStages(WebGpuStages stages) {
    bool built(WebGpuPipelineSignature signature) =>
        identical(signature.vertexModule, stages.vertexModule) &&
        identical(signature.fragmentModule, stages.fragmentModule) &&
        signature.vertexLayout == stages.vertexLayout;
    final before = _built.length;
    _built.removeWhere(
      (WebGpuPipelineSignature signature, T _) => built(signature),
    );
    _pending.removeWhere(
      (WebGpuPipelineSignature signature, int _) => built(signature),
    );
    return before - _built.length;
  }

  /// Forgets everything. Called from `dispose`, where the device that owns the
  /// pipelines is going: a `GPURenderPipeline` has no `destroy` of its own and
  /// dies with its device.
  void clear() {
    _built.clear();
    _pending.clear();
  }
}

/// What a pipeline handle stands for in the cache: its two modules, compared
/// by identity, and its vertex layout's fingerprint. Every signature built
/// for the handle carries these three, whatever the draw state.
final class WebGpuStages {
  /// The stages of a handle: its two modules and its layout fingerprint.
  const WebGpuStages({
    required this.vertexModule,
    required this.fragmentModule,
    required this.vertexLayout,
  });

  /// The compiled vertex module, compared by identity; null without a
  /// device.
  final Object? vertexModule;

  /// The compiled fragment module, compared by identity; null without a
  /// device.
  final Object? fragmentModule;

  /// The vertex layout, as `webgpuVertexLayoutFingerprint` renders it.
  final String vertexLayout;

  /// Whether [other] has the same two modules, whatever its layout: the
  /// stage pair the bind group layouts are made for.
  bool samePair(WebGpuStages other) =>
      identical(other.vertexModule, vertexModule) &&
      identical(other.fragmentModule, fragmentModule);

  @override
  bool operator ==(Object other) =>
      other is WebGpuStages &&
      samePair(other) &&
      other.vertexLayout == vertexLayout;

  @override
  int get hashCode => Object.hash(
    identityHashCode(vertexModule),
    identityHashCode(fragmentModule),
    vertexLayout,
  );
}

/// How many live pipeline handles stand for each [WebGpuStages], so the
/// pipelines built for them go with the last handle and not the first.
///
/// **Why a count.** `createPipeline` is nearly free here and a renderer may
/// ask for one pair twice, or for one pair under two names; every such
/// handle draws from the same cached `GPURenderPipeline`s. Giving one back
/// must leave the others drawing.
final class WebGpuPipelineHolders {
  final Map<WebGpuStages, int> _counts = <WebGpuStages, int>{};

  /// One more handle stands for [stages].
  void hold(WebGpuStages stages) =>
      _counts[stages] = (_counts[stages] ?? 0) + 1;

  /// One handle for [stages] is given back. True when it was the last, and
  /// what was built for [stages] may go.
  bool release(WebGpuStages stages) {
    final left = (_counts[stages] ?? 0) - 1;
    if (left > 0) {
      _counts[stages] = left;
      return false;
    }
    _counts.remove(stages);
    return true;
  }

  /// Whether any handle still stands for [stages]' pair, under any layout.
  bool holdsPair(WebGpuStages stages) =>
      _counts.keys.any((WebGpuStages held) => held.samePair(stages));

  /// How many distinct [WebGpuStages] are held, for a test.
  int get length => _counts.length;

  /// Forgets every count: the device is going.
  void clear() => _counts.clear();
}
