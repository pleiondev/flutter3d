/// A lighting model: one pre-built fragment shader and what the engine may
/// bind to it.
///
/// **A value class rather than an enum, so this list is not closed.** Shaders
/// are compiled ahead of time, so a material graph cannot be assembled at run
/// time — but an application that builds its own bundle can add an entry to it
/// and describe it here, and the renderer will cache a pipeline for it like any
/// other. What it cannot do is add a shader to a bundle it does not build; that
/// is the remaining limit, and it belongs to the bundle rather than to this
/// type.
///
/// Two properties used to be derived by comparing against particular constants,
/// which is the sort of thing that works exactly until somebody adds a seventh
/// model. They are declared now.
///
/// Shaders are compiled ahead of time into the bundle, so a material graph
/// cannot be assembled at runtime. Switching models therefore means switching
/// shader — and switching shader means a different `RenderPipeline`, which is
/// why the renderer caches pipelines by [shaderName].
///
/// The `uses…` flags are declared rather than detected. Shader reflection cannot
/// answer the question: it reports a uniform block as present because the GLSL
/// *declared* it, even when the compiled shader binds no buffer for it, and
/// binding that phantom block segfaults inside Metal with no Dart stack trace.
/// The same applies to samplers — the compiler drops one whose result never
/// reaches the output, which is why Lambert does not sample the metal-rough map
/// even though the header declares it.
///
/// The truth is printed by `tool/build_shaders.sh` after every build, as a table
/// of what each entry point actually kept. When this metadata and that table
/// disagree, the table is right.
final class LightingModel {
  const LightingModel(
    this.label,
    this.shaderName, {
    this.usesFragInfo = true,
    this.usesAlbedoTexture = true,
    this.usesMaterialMaps = true,
    this.usesMetallicRoughnessMap = true,
    this.usesMaterialParameters = true,
    this.usesMetallic = false,
    this.usesEnvironment = false,
  }) : assert(
         !usesMetallicRoughnessMap || usesMaterialMaps,
         'the metallic-roughness map is one of the material maps, so a model '
         'that samples no maps cannot sample it either. Getting this pair '
         'wrong is not a warning at run time: the renderer binds a texture '
         'the compiled shader has no slot for, and the bind fails. Unlit sat '
         'in exactly that state until a golden caught it.',
       );

  static const LightingModel unlit = LightingModel(
    'Unlit',
    'Unlit',
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );
  static const LightingModel lambert = LightingModel(
    'Lambert',
    'Lambert',
    usesMetallicRoughnessMap: false,
  );
  static const LightingModel blinnPhong = LightingModel(
    'Blinn-Phong',
    'BlinnPhong',
  );
  static const LightingModel pbr = LightingModel(
    'PBR (GGX)',
    'Pbr',
    usesMetallic: true,
    usesEnvironment: true,
  );
  static const LightingModel toon = LightingModel('Toon', 'Toon');
  static const LightingModel normals = LightingModel(
    'Normals',
    'Normals',
    usesFragInfo: false,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
    usesMaterialParameters: false,
  );

  /// The models this engine ships, in the order a picker should show them.
  ///
  /// `builtIn` and not `values`: there is no longer a complete list to have.
  /// The name says which question it answers — "what came with the engine" —
  /// rather than implying nothing else can exist.
  static const List<LightingModel> builtIn = <LightingModel>[
    unlit,
    lambert,
    blinnPhong,
    pbr,
    toon,
    normals,
  ];

  /// Shown in the UI.
  final String label;

  /// Entry name inside whichever bundle the backend supplied.
  ///
  /// This is the contract the engine cannot abstract away: it names shaders,
  /// and every backend must ship a bundle containing them under these names.
  /// Every backend package lists them in its own bundle manifest, and a
  /// backend that answers to a name the engine does not ask for is unused
  /// weight while one that misses a name the engine does ask for fails at
  /// `Renderer.create`, which names the missing entry.
  final String shaderName;

  /// Whether the shader reads the `FragInfo` uniform block.
  final bool usesFragInfo;

  /// Whether the shader samples `base_color_texture`.
  final bool usesAlbedoTexture;

  /// Whether the shader samples the normal, occlusion and emissive maps.
  ///
  /// The three travel together: every lit model applies all of them, and no
  /// unlit or debug model applies any.
  final bool usesMaterialMaps;

  /// Whether the shader samples `shadow_texture`.
  ///
  /// The same set as [usesMaterialMaps] today — every lit model shadows and no
  /// debug model does — but kept separate because the two answer different
  /// questions and will diverge the moment an unlit-but-shadowed model exists.
  bool get usesShadowMap => usesMaterialMaps;

  /// Whether the shader reads the `PointShadow` block and the two cube atlases.
  ///
  /// The same set again, and for the same reason kept its own name. It is a
  /// separate flag rather than a reuse because it was missing entirely: point
  /// shadows were added binding the block and both atlases to every model with
  /// a [usesFragInfo], which includes Unlit — and the compiled Unlit shader
  /// keeps none of the three, since it calls no lighting loop to reach them.
  /// The build script's table is what says so, and `lighting-unlit` is what
  /// noticed.
  bool get usesPointShadow => usesMaterialMaps;

  /// Whether the shader samples `metallic_roughness_texture`.
  ///
  /// Separate from [usesMaterialMaps] because Lambert is purely diffuse: it has
  /// no response to metallic or roughness, so the compiler drops the sampler
  /// and the engine must not try to bind it.
  final bool usesMetallicRoughnessMap;

  /// Whether the material's numeric parameters reach the shader, so a UI can
  /// disable the sliders that would do nothing.
  ///
  /// Declared rather than derived. It used to read `this != unlit && this !=
  /// normals`, which was true of the six models that existed and wrong for any
  /// seventh — a custom model would have been told its own parameters mattered
  /// because it was not one of two names.
  final bool usesMaterialParameters;

  /// A small stable number for grouping draws that share a pipeline.
  ///
  /// **Not `shaderName.hashCode`.** Dart does not promise a string's hash is
  /// the same from one run to the next, and the draw sort uses this — so the
  /// order two lighting models are drawn in would have varied between runs.
  /// Two goldens caught it at 25% and 0.6% of their pixels, which is what a
  /// nondeterministic sort looks like once anything blends.
  ///
  /// FNV-1a over the name, folded to six bits, because that is what the key has
  /// room for. A collision costs one extra pipeline switch and nothing else:
  /// grouping is an optimisation, and the key is allowed to be approximate
  /// about it in a way it is not allowed to be unstable about.
  int get pipelineGroup {
    var hash = 0x811c9dc5;
    for (var i = 0; i < shaderName.length; i++) {
      hash = ((hash ^ shaderName.codeUnitAt(i)) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x3F;
  }

  /// Whether the shader interprets metallic. Only a physical model does.
  ///
  /// Declared for the same reason: `this == pbr` answered a question about the
  /// shader by checking which constant it happened to be.
  final bool usesMetallic;

  /// Whether the shader declares the environment cube and samples it.
  ///
  /// Only the physical model does: image-based lighting is an answer to the
  /// rendering equation, and Lambert, Blinn-Phong and toon are not asking it.
  ///
  /// The renderer binds by this flag rather than by which constant a material
  /// holds, for the reason above it — and because binding a texture a compiled
  /// shader has no slot for is a native crash, not a no-op.
  final bool usesEnvironment;
}
