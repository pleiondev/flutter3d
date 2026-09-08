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
  /// The module for [wgsl], or a throw naming [name] and quoting the compiler.
  ///
  /// **A throw is allowed and cannot be required, and the difference is a fact
  /// about this API.** `GPUDevice.createShaderModule` returns a module for text
  /// that does not compile: WGSL errors arrive out of band, through an error
  /// scope or `getCompilationInfo`, both of which are promises. So the device's
  /// implementation cannot know synchronously whether the text was good, and it
  /// does the next honest thing — it records the browser's verdict, with the
  /// stage's name and the line, where `WebGpuDevice.debugDrainErrors` will find
  /// it. Otherwise the complaint arrives at the first pipeline built from the
  /// module as "invalid due to a previous error", naming neither the stage nor
  /// the line, which is exactly the mystery the WebGL2 backend refuses to leave
  /// behind when a compile fails.
  ///
  /// A compiler that *can* decide — a test's, or an ahead-of-time one — throws
  /// [StateError], and the reload in `webgpu_loaded_shaders.dart` turns that
  /// into a refusal naming the bundle.
  Object compileModule(String name, String wgsl);
}

/// The entry point inside every module this backend compiles.
///
/// **One module per stage, one entry point in it, and it is always called
/// `main`** — because that is what glslang wrote from the engine's GLSL and
/// what naga kept. WGSL puts every stage of a translation unit in one module
/// and tells them apart with `@vertex` and `@fragment`, so a pipeline is built
/// from a module *and* a name; here the name is the same one every time, and
/// saying so once is better than carrying a string that is never anything else.
const String webgpuEntryPoint = 'main';

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

  /// The block called [name], or null where this stage declares none.
  ///
  /// A scan rather than a map because a stage declares a handful of blocks and
  /// the list arrives in the order the reflection stated. Building a map per
  /// stage would be a map per stage for a lookup that runs a few times a draw
  /// over three entries.
  ///
  /// Read through the [ShaderHandle] the caller already holds, which is what
  /// makes `PassEncoder.bindUniformBlock` answer to a name on an API that kept
  /// none: a `GPUShaderModule` cannot be interrogated for its bindings at all.
  WebGpuBlock? blockNamed(String name) {
    for (final block in stage.blocks) {
      if (block.name == name) return block;
    }
    return null;
  }

  /// The texture-and-sampler pair called [name], or null where this stage
  /// declares none. See [blockNamed] for why it is a scan.
  WebGpuSampler? samplerNamed(String name) {
    for (final sampler in stage.samplers) {
      if (sampler.name == name) return sampler;
    }
    return null;
  }
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

  /// Drops the handles this library has handed out.
  ///
  /// **Not a teardown, because there is nothing here to tear down** — a
  /// `GPUShaderModule` has no `destroy` in the API and dies with the device
  /// that compiled it. What this is for is the device's own resource count,
  /// which counts modules among the things a leak would show up in and has to
  /// be able to reach zero; and for the caller, who after `dispose` is holding
  /// stages of a device that is gone.
  void forget() => _handles.clear();

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
    required this.name,
    required this.vertexModule,
    required this.fragmentModule,
    required this.layout,
    required List<WebGpuVertexBuffer> buffers,
    required Map<String, WebGpuBlock> blocks,
    required Map<String, WebGpuSampler> samplers,
    required List<WebGpuGroupShape> groups,
  }) : buffers = List<WebGpuVertexBuffer>.unmodifiable(buffers),
       blocks = Map<String, WebGpuBlock>.unmodifiable(blocks),
       samplers = Map<String, WebGpuSampler>.unmodifiable(samplers),
       groups = List<WebGpuGroupShape>.unmodifiable(groups);

  /// The stage pair, spelled `vertex+fragment` the way the contract fixes it.
  final String name;

  /// Where the vertex inputs come from, as the caller stated it or as
  /// [_derivedLayout] worked it out.
  ///
  /// Kept beside [buffers] rather than thrown away once the locations are
  /// resolved, because it is what the pipeline cache's signature is rendered
  /// from: two layouts over one stage pair are two pipelines, and the
  /// fingerprint of a `VertexLayoutSpec` is the string that says so. See
  /// `webgpu_pipeline_cache.dart`.
  final VertexLayoutSpec layout;

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

  /// What each `@group` of this pipeline holds, group *n* at index *n*.
  ///
  /// The same bindings as [blocks] and [samplers], arranged the way the API
  /// wants them instead of the way a caller names them: a `GPUBindGroupLayout`
  /// is one group at a time, and the dynamic offsets a draw passes to
  /// `setBindGroup` go in the order that layout declared its dynamic entries.
  /// So the order here is binding order, and it is a property of the pipeline
  /// rather than a habit of whoever iterates it — an offset list out of order
  /// draws the last object's transform on this one and reports nothing.
  final List<WebGpuGroupShape> groups;
}

/// Which stages one binding is visible to.
///
/// A block declared by both stages — `FrameInfo` is, in every lit shader — has
/// to say so: a bind group layout that named one stage would be refused by the
/// other's use of it. Two booleans rather than the API's flag word because
/// nothing in this file may import `dart:js_interop`, and turning a pair of
/// facts into `GPUShaderStage` bits is one line in `webgpu_types.dart`.
typedef WebGpuVisibility = ({bool vertex, bool fragment});

/// One uniform block of a group, and which stages see it.
final class WebGpuBoundBlock {
  const WebGpuBoundBlock({required this.block, required this.visibility});

  final WebGpuBlock block;
  final WebGpuVisibility visibility;
}

/// One texture-and-sampler pair of a group, and which stages see it.
final class WebGpuBoundSampler {
  const WebGpuBoundSampler({required this.sampler, required this.visibility});

  final WebGpuSampler sampler;
  final WebGpuVisibility visibility;
}

/// What one `@group` of a pipeline holds, each list in binding order.
final class WebGpuGroupShape {
  const WebGpuGroupShape({required this.blocks, required this.samplers});

  final List<WebGpuBoundBlock> blocks;
  final List<WebGpuBoundSampler> samplers;

  /// Whether this group has nothing in it, which a pipeline's lower group
  /// numbers legitimately do: a shader that declares `@group(1)` and no
  /// `@group(0)` still needs a placeholder in slot zero of its pipeline layout.
  bool get isEmpty => blocks.isEmpty && samplers.isEmpty;
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
/// string. Nothing about the pipeline is *found* by that string — the modules,
/// the buffers and the group shapes are all in the record — but
/// `WebGpuPipelineKey` keys a cache on it, so a backend that layered an
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
  // A caller that passed one gets that one; a caller that passed null — which
  // is every pipeline in this engine but the instanced ones — gets one derived
  // from the vertex stage's own attribute table, which is what
  // `GraphicsDevice.createPipeline` means by "the backend works it out from the
  // shader". Both then go through one resolution, so the derived path is a
  // layout like any other rather than a second way of packing a buffer.
  final spec = layout ?? _derivedLayout(vertexStage.stage);
  final name = '${vertex.name}+${fragment.name}';
  return PipelineHandle(
    backend: WebGpuPipeline(
      name: name,
      vertexModule: vertexStage.module,
      fragmentModule: fragmentStage.module,
      layout: spec,
      buffers: _resolvedBuffers(vertex.name, vertexStage.stage, spec),
      blocks: _mergedBlocks(vertexStage, fragmentStage),
      samplers: _mergedSamplers(vertexStage, fragmentStage),
      groups: _groupShapes(vertexStage, fragmentStage),
    ),
    name: name,
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

/// One buffer holding every attribute the stage declares, packed the way every
/// draw in this engine packed one before a layout could be asked for.
///
/// The attributes are laid end to end in location order and the stride is their
/// sum, which is the convention `VertexLayout` in the engine documents and the
/// convention `WebGlProgram.attributes` reconstructs from `getActiveAttrib`.
/// Sorted rather than taken as it comes: the sidecar writes its table in
/// location order already, and sorting is how that stays a fact about the bytes
/// rather than a habit of the generator.
///
/// A `VertexLayoutSpec` and not the resolved buffers, so that a derived layout
/// and a stated one are the same thing by the time anything reads them — and so
/// that the pipeline cache's signature can be rendered from a layout whether or
/// not the caller wrote it out.
VertexLayoutSpec _derivedLayout(WebGpuStage stage) {
  final ordered = <WebGpuAttribute>[...stage.attributes]
    ..sort(
      (WebGpuAttribute a, WebGpuAttribute b) =>
          a.location.compareTo(b.location),
    );
  // A running offset, which is what a packing loop's state is.
  var at = 0;
  final attributes = <InputAttribute>[];
  for (final attribute in ordered) {
    attributes.add(
      InputAttribute(
        name: attribute.name,
        format: attribute.format,
        offsetInBytes: at,
      ),
    );
    at += attribute.format.bytesPerElement;
  }
  return VertexLayoutSpec(<BufferLayout>[
    BufferLayout(strideInBytes: at, attributes: attributes),
  ]);
}

/// What each `@group` of the pair holds, and which stages see each binding.
///
/// Built from the two stages' reflection and from nothing else, because a
/// `GPUShaderModule` answers no question about its own bindings and a pipeline
/// layout has to state every one of them up front.
List<WebGpuGroupShape> _groupShapes(
  WebGpuShader vertex,
  WebGpuShader fragment,
) {
  bool declaresBlock(WebGpuShader shader, int group, int binding) => shader
      .stage
      .blocks
      .any((WebGpuBlock b) => b.group == group && b.binding == binding);
  bool declaresSampler(WebGpuShader shader, int group, int binding) =>
      shader.stage.samplers.any(
        (WebGpuSampler s) => s.group == group && s.textureBinding == binding,
      );

  final blocks = <int, Map<int, WebGpuBlock>>{};
  final samplers = <int, Map<int, WebGpuSampler>>{};
  // The highest group either stage mentions, which is how many slots the
  // pipeline layout needs — including the empty ones below it.
  var highest = -1;
  for (final shader in <WebGpuShader>[vertex, fragment]) {
    for (final block in shader.stage.blocks) {
      (blocks[block.group] ??= <int, WebGpuBlock>{})[block.binding] = block;
      if (block.group > highest) highest = block.group;
    }
    for (final sampler in shader.stage.samplers) {
      (samplers[sampler.group] ??=
              <int, WebGpuSampler>{})[sampler.textureBinding] =
          sampler;
      if (sampler.group > highest) highest = sampler.group;
    }
  }

  return <WebGpuGroupShape>[
    for (var group = 0; group <= highest; group++)
      WebGpuGroupShape(
        blocks: <WebGpuBoundBlock>[
          for (final block in _sorted<WebGpuBlock>(
            blocks[group],
            (WebGpuBlock a, WebGpuBlock b) => a.binding.compareTo(b.binding),
          ))
            WebGpuBoundBlock(
              block: block,
              visibility: (
                vertex: declaresBlock(vertex, group, block.binding),
                fragment: declaresBlock(fragment, group, block.binding),
              ),
            ),
        ],
        samplers: <WebGpuBoundSampler>[
          for (final sampler in _sorted<WebGpuSampler>(
            samplers[group],
            (WebGpuSampler a, WebGpuSampler b) =>
                a.textureBinding.compareTo(b.textureBinding),
          ))
            WebGpuBoundSampler(
              sampler: sampler,
              visibility: (
                vertex: declaresSampler(vertex, group, sampler.textureBinding),
                fragment: declaresSampler(
                  fragment,
                  group,
                  sampler.textureBinding,
                ),
              ),
            ),
        ],
      ),
  ];
}

List<T> _sorted<T>(Map<int, T>? byBinding, Comparator<T> order) =>
    byBinding == null
    ? const <Never>[]
    : (byBinding.values.toList()..sort(order));

/// The buffers [layout] names, with each attribute's location looked up in the
/// vertex stage's table.
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
List<WebGpuVertexBuffer> _resolvedBuffers(
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
