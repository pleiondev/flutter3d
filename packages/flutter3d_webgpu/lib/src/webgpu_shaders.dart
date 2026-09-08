/// Shaders for the WebGPU backend: WGSL modules compiled on first use, and the
/// reflection they arrive beside.
///
/// **The names are the contract**, exactly as they are on the two backends
/// already shipped. `LightingModel.shaderName` and the renderer's `require`
/// calls name entry points — 'MeshVertex', 'Pbr', 'Composite' and the rest —
/// and every backend must answer to them.
///
/// ## What the WebGL2 file taught, and what of it survives here
///
/// `flutter3d_webgl`'s shader library keeps two caches: compiled stages by
/// name, and linked programs by the *pair* of stages. There is no link step in
/// WebGPU — a `GPUShaderModule` is one stage, and a render pipeline is built
/// from two of them at the draw — so the second cache has nothing to hold and
/// is gone. What it knew is not.
///
/// It knew that a compiled stage must be found by the **identity** of the
/// handle and never by the word the handle carries. Its program cache was once
/// keyed on `'$vertexName+$fragmentName'`, and that stopped being a key the day
/// a second library could answer the same name: a bundle loaded from bytes wins
/// `Pbr` over the engine's when it is layered first, and a cache keyed on the
/// word hands back whichever pair got there first — the engine's stage running
/// where the application's was asked for, with the lookup itself returning the
/// right handle and nothing in the picture to say so.
///
/// Here that lesson is spent rather than repeated: the compiled module is a
/// field of [WebGpuShader], which is the object a [ShaderHandle] carries, so
/// there is no map from a name to a module for two libraries to collide in. A
/// module is reached by dereferencing the handle the caller already holds, and
/// two libraries answering `Pbr` hold two different objects. The mistake is not
/// avoided by discipline; it has nowhere left to happen.
///
/// **The one place the word is still the key is downstream.**
/// `WebGpuPipelineKey.pipeline` is a `String`, taken from
/// `PipelineHandle.name`, which the contract spells `vertex+fragment`. Two
/// layered libraries produce the same string for two different stage pairs, and
/// the pipeline cache behind that key would hand back the wrong one. See the
/// note on [createWebGpuPipeline].
///
/// ## No `dart:js_interop` here
///
/// The same rule `webgpu_formats.dart` and `webgpu_bundle_section.dart` keep,
/// and for the same payoff: everything in this file runs on the Dart VM, so
/// name resolution, the vertex layout arithmetic and every refusal are asserted
/// in a second rather than only in a browser with a GPU. The single thing a
/// shader library needs a device for — turning WGSL text into a module — is
/// reached through [WgslModuleCompiler], an interface with one method, which
/// the device implements over `GPUDevice.createShaderModule`.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'webgpu_bundle_section.dart';

/// Turns WGSL text into whatever the backend's module object is.
///
/// **One method, because one method is the whole of what a shader library
/// cannot do without a device.** Everything else here — looking a name up,
/// merging two stages' reflection, turning a [VertexLayoutSpec] into buffers
/// and locations — is arithmetic over the sidecar and belongs on the VM.
/// Declaring the seam as an interface is what keeps it there, and it is what
/// lets a test compile a "module" that is a `String` and still exercise the
/// caching, the refusals and the reload.
///
/// Implemented by the device, which is the only holder of a `GPUDevice`.
abstract interface class WgslModuleCompiler {
  /// The module for [wgsl], or a throw naming [name] and quoting the browser.
  ///
  /// **Throwing is the contract, and it is not free on this API.**
  /// `GPUDevice.createShaderModule` returns a module for text that does not
  /// compile: WGSL errors arrive out of band, through an error scope or
  /// `getCompilationInfo`. An implementation that returned the module anyway
  /// would hand back a stage that fails at pipeline creation instead, in a
  /// message naming neither the stage nor the line — which is exactly the
  /// mystery the WebGL2 backend refuses to leave behind when a compile fails.
  /// So the device wraps the call in an error scope and throws.
  Object compileModule(String name, String wgsl);
}

/// The WGSL of one stage, the reflection that goes with it, and the module the
/// two produced.
///
/// **One value rather than three fields, so a reload cannot half-happen.** The
/// reflection travels with the code — a stage recompiled from a new bundle can
/// put its uniform block on a different binding — so a swap that replaced the
/// module and kept the old table would bind the right bytes to the wrong slot
/// and draw something plausible. Assigning a record replaces all of it at once.
typedef WebGpuCode = ({WebGpuStage stage, Object module});

/// What a [ShaderHandle] carries here: one compiled stage, and which kind.
final class WebGpuShader {
  WebGpuShader({
    required this.name,
    required this.isVertex,
    required this.code,
  });

  /// The entry point this stage was found under.
  ///
  /// Carried as well as on the handle because the refusals a reload raises name
  /// the stage, and they are raised from here where only this object is to
  /// hand.
  final String name;

  /// Whether this is a vertex stage; a fragment stage otherwise.
  ///
  /// Read by [createWebGpuPipeline], which will not take the two the wrong way
  /// round, and by a reload deciding which half of the new section to look the
  /// stage up in.
  final bool isVertex;

  /// The code and reflection this stage currently is.
  ///
  /// **Mutable, and that is the whole of how a reload works on this backend.**
  /// `LoadedShaderLibrary` promises that a handle already handed out keeps its
  /// identity and keeps working; flutter_gpu keeps it by mutating a stage in
  /// place, and there is nothing to mutate in a `GPUShaderModule` — it is
  /// compiled once from one text. So the handle stays and what sits behind it
  /// is replaced. `WebGpuLoadedShaderLibrary.refresh` is the one writer.
  WebGpuCode code;

  /// The WGSL and its reflection.
  WebGpuStage get stage => code.stage;

  /// The compiled module, as the device's own type.
  Object get module => code.module;
}

/// Compiles one stage into a handle, or throws naming it.
///
/// Shared by the engine's library and a loaded one, because a stage that failed
/// to compile and came back null would look exactly like a stage the sidecar
/// never had, and the two need different fixes.
ShaderHandle compileWebGpuStage(
  WgslModuleCompiler compiler,
  String name,
  WebGpuStage stage, {
  required bool isVertex,
}) => ShaderHandle(
  backend: WebGpuShader(
    name: name,
    isVertex: isVertex,
    code: (stage: stage, module: compiler.compileModule(name, stage.wgsl)),
  ),
  name: name,
);

/// A [ShaderLibrary] over a sidecar's stages, compiled on first use.
///
/// Compiled lazily and cached, because a scene uses a handful of the sidecar's
/// thirty-nine stages and compiling all of them at startup would cost a visible
/// pause for shaders the frame never binds.
///
/// **There is nothing to dispose.** A `WebGLShader` is a driver object nothing
/// collects, so `WebGlShaderLibrary` deletes every one it made; a
/// `GPUShaderModule` has no destructor in the API at all and is collected like
/// any other JavaScript object. So this library ends by being dropped, and
/// [debugTrackedModuleCount] is for a test to read rather than for a device to
/// drive to zero.
final class WebGpuShaderLibrary implements ShaderLibrary {
  WebGpuShaderLibrary(this._compiler, this._stages);

  final WgslModuleCompiler _compiler;
  final WebGpuSectionStages _stages;

  /// Answers already given, including the nulls.
  ///
  /// A null is an answer about a name this sidecar does not have, and caching
  /// it is what keeps a contributor that asks every frame for a stage nobody
  /// packed from searching two maps every frame.
  final Map<String, ShaderHandle?> _handles = <String, ShaderHandle?>{};

  @override
  ShaderHandle? operator [](String name) =>
      _handles.putIfAbsent(name, () => _compile(name));

  ShaderHandle? _compile(String name) {
    final isVertex = _stages.vertex.containsKey(name);
    final stage = isVertex ? _stages.vertex[name] : _stages.fragment[name];
    // Null rather than throwing: the contract says a missing name comes back
    // null and lets the caller decide, because the renderer refuses to start
    // while a contributor merely draws nothing.
    if (stage == null) return null;
    // A failed compile throws out of `putIfAbsent`, so it is never cached and
    // the next ask tries again.
    return compileWebGpuStage(_compiler, name, stage, isVertex: isVertex);
  }

  /// How many modules this library has compiled, for tests.
  ///
  /// Read by whoever wants to know that a second lookup of one name did not
  /// compile a second module. The nulls above are cached answers rather than
  /// modules and do not count.
  int get debugTrackedModuleCount => _handles.values.nonNulls.length;
}

/// One vertex input, resolved: where its bytes are and which location wants
/// them.
///
/// [name] is carried through because it is the only thing an error message can
/// say, and because the two ways of building this list — from the sidecar's own
/// attribute table and from a [VertexLayoutSpec] — agree about nothing else.
final class WebGpuVertexAttribute {
  const WebGpuVertexAttribute({
    required this.name,
    required this.shaderLocation,
    required this.format,
    required this.offsetInBytes,
  });

  final String name;

  /// Spelled as `GPUVertexAttribute` spells it, because that is where the
  /// number is going.
  final int shaderLocation;

  final VertexFormat format;

  /// Where this attribute begins inside one element of its buffer.
  final int offsetInBytes;
}

/// One vertex buffer a pipeline reads, in the slot its position gives it.
final class WebGpuVertexBuffer {
  WebGpuVertexBuffer({
    required this.strideInBytes,
    required this.stepMode,
    required List<WebGpuVertexAttribute> attributes,
  }) : attributes = List<WebGpuVertexAttribute>.unmodifiable(attributes);

  final int strideInBytes;
  final VertexStepMode stepMode;
  final List<WebGpuVertexAttribute> attributes;
}

/// What a [PipelineHandle] carries here: two modules, the vertex layout they
/// will be built with, and the reflection a bind group needs.
///
/// **This is the record `WebGlProgram` is, with the three reflection procedures
/// replaced by a lookup.** WebGL asks the context — `getActiveAttrib`,
/// `getActiveUniformBlock`, `getActiveUniform` — after it has linked. A
/// `GPUShaderModule` answers none of those questions and cannot be made to, so
/// the answers arrive in the bundle beside the code, and building a pipeline
/// reads them out of `WebGpuStage` instead of out of a driver. The *shape* is
/// deliberately unchanged: attributes in location order, blocks by name,
/// samplers by name. The sidecar is the file version of exactly this record,
/// which is why the two look alike.
final class WebGpuPipeline {
  WebGpuPipeline({
    required this.vertexModule,
    required this.fragmentModule,
    required List<WebGpuVertexBuffer> buffers,
    required Map<String, WebGpuBlock> blocks,
    required Map<String, WebGpuSampler> samplers,
  }) : buffers = List<WebGpuVertexBuffer>.unmodifiable(buffers),
       blocks = Map<String, WebGpuBlock>.unmodifiable(blocks),
       samplers = Map<String, WebGpuSampler>.unmodifiable(samplers);

  /// The vertex stage's module, as the device's own type.
  ///
  /// Captured here rather than reached through the handle, and the difference
  /// is what the reload contract asks for: a pipeline already handed out goes
  /// on drawing the code it was built from until `Renderer.relinkShaders`
  /// replaces it, so a frame between a refresh and a relink is the old picture
  /// rather than a missing one. Nothing has to be retired to keep that promise
  /// here — the browser collects a module the moment the last pipeline holding
  /// it is dropped, where GL needed a program kept alive by hand.
  final Object vertexModule;

  /// The fragment stage's module, held for the reason above.
  final Object fragmentModule;

  /// Every buffer this pipeline reads vertices from, slot *n* at index *n*.
  final List<WebGpuVertexBuffer> buffers;

  /// Uniform blocks by the name `PassEncoder.bindUniformBlock` uses, over both
  /// stages.
  final Map<String, WebGpuBlock> blocks;

  /// Texture-and-sampler pairs by the name `PassEncoder.bindTexture` uses, over
  /// both stages.
  final Map<String, WebGpuSampler> samplers;
}

/// Pairs two stages into a pipeline, resolving the vertex layout against the
/// vertex stage's own attribute table.
///
/// A function rather than a method, because there is no per-pair state left to
/// hang it off: WebGL keeps a cache here because linking is expensive and
/// WebGPU has no link step. The device calls this from `createPipeline`
/// whichever library answered the names.
///
/// **The pipeline's name is `vertex+fragment`, which the contract fixes and
/// which is not unique.** Two layered libraries can each answer `Pbr`, and the
/// two pipelines built from them are then two different objects under one
/// string. Nothing here depends on the string — the modules are in the record —
/// but `WebGpuPipelineKey` keys a cache on it, so a backend that layered an
/// application's shaders over the engine's would want that key to carry the
/// handle rather than its word. The lesson is `webgl_shaders.dart`'s, learnt
/// there the expensive way.
///
/// Throws [StateError] when the two handles are not a vertex stage and a
/// fragment stage of this backend, when the two stages disagree about where a
/// name is bound, or when [layout] does not feed every input the vertex stage
/// declares.
PipelineHandle createWebGpuPipeline(
  ShaderHandle vertex,
  ShaderHandle fragment, {
  VertexLayoutSpec? layout,
}) {
  final vertexStage = _stageOf(vertex, wantVertex: true);
  final fragmentStage = _stageOf(fragment, wantVertex: false);
  return PipelineHandle(
    backend: WebGpuPipeline(
      vertexModule: vertexStage.module,
      fragmentModule: fragmentStage.module,
      buffers: layout == null
          ? _interleavedBuffers(vertexStage.stage)
          : _declaredBuffers(vertex.name, vertexStage.stage, layout),
      blocks: _mergedBlocks(vertexStage, fragmentStage),
      samplers: _mergedSamplers(vertexStage, fragmentStage),
    ),
    name: '${vertex.name}+${fragment.name}',
  );
}

WebGpuShader _stageOf(ShaderHandle handle, {required bool wantVertex}) {
  final backend = handle.backend;
  if (backend is! WebGpuShader) {
    throw StateError(
      'the stage "${handle.name}" was not compiled by this backend, so there '
      'is no WGSL module behind it. A pipeline can only pair stages from a '
      'library this device built.',
    );
  }
  if (backend.isVertex != wantVertex) {
    // Cheap to make and expensive to find: a pipeline built from two fragment
    // stages fails inside the browser with a message about an entry point,
    // which names neither shader.
    throw StateError(
      'the ${wantVertex ? 'vertex' : 'fragment'} stage of a pipeline must be '
      'a ${wantVertex ? 'vertex' : 'fragment'} shader, and "${handle.name}" '
      'is a ${backend.isVertex ? 'vertex' : 'fragment'} one',
    );
  }
  return backend;
}

/// One buffer, packed the way every draw in this engine packed one before a
/// layout could be asked for.
///
/// The attributes are laid end to end in location order and the stride is their
/// sum, which is the convention `VertexLayout` in the engine documents and the
/// convention `WebGlProgram.attributes` reconstructs from `getActiveAttrib`.
/// Sorted rather than taken as it comes: the sidecar writes its table in
/// location order already, and sorting is how that stays a fact about the bytes
/// rather than a habit of the generator.
List<WebGpuVertexBuffer> _interleavedBuffers(WebGpuStage stage) {
  final ordered = <WebGpuAttribute>[...stage.attributes]
    ..sort(
      (WebGpuAttribute a, WebGpuAttribute b) =>
          a.location.compareTo(b.location),
    );
  // A running offset, which is what a packing loop's state is.
  var at = 0;
  final attributes = <WebGpuVertexAttribute>[];
  for (final attribute in ordered) {
    attributes.add(
      WebGpuVertexAttribute(
        name: attribute.name,
        shaderLocation: attribute.location,
        format: attribute.format,
        offsetInBytes: at,
      ),
    );
    at += attribute.format.bytesPerElement;
  }
  return <WebGpuVertexBuffer>[
    WebGpuVertexBuffer(
      strideInBytes: at,
      stepMode: VertexStepMode.vertex,
      attributes: attributes,
    ),
  ];
}

/// The buffers a [VertexLayoutSpec] names, with each attribute's location
/// looked up in the vertex stage's table.
///
/// **The layout names attributes and WebGPU wants locations, which is the whole
/// reason both paths go through the same table.** `InputAttribute.name` says
/// outright that a name is what the hardware backends agree about: Impeller
/// resolves it through the compiled shader's reflection and WebGL through
/// `getAttribLocation`. There is no third mechanism here — the sidecar is the
/// reflection — so the five call sites in the engine that hand a layout in get
/// their locations from the same place the reflection path gets its order.
///
/// The layout's own [VertexFormat] wins over the sidecar's, because the layout
/// describes the bytes in the buffer and the sidecar describes what the shader
/// declared; WebGPU is happy for the first to have fewer components than the
/// second and fills the rest with zeros and a one.
List<WebGpuVertexBuffer> _declaredBuffers(
  String stageName,
  WebGpuStage stage,
  VertexLayoutSpec layout,
) {
  final byName = <String, WebGpuAttribute>{
    for (final attribute in stage.attributes) attribute.name: attribute,
  };
  final fed = <String>{
    for (final buffer in layout.buffers)
      for (final attribute in buffer.attributes) attribute.name,
  };
  final buffers = <WebGpuVertexBuffer>[
    for (final buffer in layout.buffers)
      WebGpuVertexBuffer(
        strideInBytes: buffer.strideInBytes,
        stepMode: buffer.stepMode,
        attributes: <WebGpuVertexAttribute>[
          for (final attribute in buffer.attributes)
            // A name the stage does not declare is skipped rather than
            // refused, for the reason WebGL skips a negative location: an `in`
            // the compiler dropped because nothing read it is not an error, and
            // the same layout is handed to shaders that differ in which of them
            // use every attribute. A layout naming one too many is merely more
            // complete than it needs to be.
            if (byName[attribute.name] case final WebGpuAttribute found)
              WebGpuVertexAttribute(
                name: attribute.name,
                shaderLocation: found.location,
                format: attribute.format,
                offsetInBytes: attribute.offsetInBytes,
              ),
        ],
      ),
  ];

  // The other direction, which WebGL never had to check and WebGPU will not
  // forgive. GL leaves an attribute nobody pointed at reading zeros; WebGPU
  // refuses to create a pipeline whose vertex stage declares an input no buffer
  // supplies, in a message about a shader location. Naming the attribute — and
  // the stage, and how many buffers were offered — is the difference between a
  // one-line fix and an afternoon.
  final missing = <String>[
    for (final attribute in stage.attributes)
      if (!fed.contains(attribute.name)) attribute.name,
  ];
  if (missing.isNotEmpty) {
    throw StateError(
      'the vertex stage "$stageName" reads ${missing.join(', ')}, and the '
      'layout offered ${layout.buffers.length} buffer(s) naming none of '
      'them. Every input a stage declares has to come from some slot.',
    );
  }
  return buffers;
}

/// The uniform blocks of both stages, by name.
///
/// A merge and not a concatenation, because `bindUniformBlock` takes a name and
/// one name has to mean one binding. The engine's own GLSL puts a vertex
/// stage's blocks in group 0 and a fragment stage's in group 1, so a name in
/// both is either the same block twice — which merges to itself — or two
/// different blocks the encoder could not tell apart.
///
/// **The disagreement is not hypothetical.** `VertexTextureProbeVertex` binds
/// `ProbeInfo` at group 0 and `ProbePrefilter` binds a block of that name at
/// group 1. The engine never pairs those two stages, so nothing draws wrong
/// today; a backend that took the first of the two and said nothing would draw
/// wrong the day something did.
Map<String, WebGpuBlock> _mergedBlocks(
  WebGpuShader vertex,
  WebGpuShader fragment,
) {
  final merged = <String, WebGpuBlock>{
    for (final block in vertex.stage.blocks) block.name: block,
  };
  for (final block in fragment.stage.blocks) {
    final seen = merged[block.name];
    if (seen != null &&
        (seen.group != block.group ||
            seen.binding != block.binding ||
            seen.sizeInBytes != block.sizeInBytes)) {
      throw StateError(
        'the stages "${vertex.name}" and "${fragment.name}" both declare the '
        'uniform block "${block.name}" and put it in different places: '
        'group ${seen.group} binding ${seen.binding} against group '
        '${block.group} binding ${block.binding}. A block is bound by name, '
        'so the two would have to be one.',
      );
    }
    merged[block.name] = block;
  }
  return merged;
}

/// The texture-and-sampler pairs of both stages, by name, refusing a
/// disagreement for the reason [_mergedBlocks] gives.
Map<String, WebGpuSampler> _mergedSamplers(
  WebGpuShader vertex,
  WebGpuShader fragment,
) {
  final merged = <String, WebGpuSampler>{
    for (final sampler in vertex.stage.samplers) sampler.name: sampler,
  };
  for (final sampler in fragment.stage.samplers) {
    final seen = merged[sampler.name];
    if (seen != null &&
        (seen.group != sampler.group ||
            seen.textureBinding != sampler.textureBinding ||
            seen.samplerBinding != sampler.samplerBinding ||
            seen.dimension != sampler.dimension)) {
      throw StateError(
        'the stages "${vertex.name}" and "${fragment.name}" both declare the '
        'sampler "${sampler.name}" and put it in different places: group '
        '${seen.group} bindings ${seen.textureBinding}/'
        '${seen.samplerBinding} against group ${sampler.group} bindings '
        '${sampler.textureBinding}/${sampler.samplerBinding}. A texture is '
        'bound by name, so the two would have to be one.',
      );
    }
    merged[sampler.name] = sampler;
  }
  return merged;
}
