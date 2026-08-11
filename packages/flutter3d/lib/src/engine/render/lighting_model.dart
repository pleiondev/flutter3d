/// A lighting model, which on flutter_gpu means one pre-built fragment shader.
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
enum LightingModel {
  unlit('Unlit', 'Unlit', usesMaterialMaps: false, usesMetallicRoughnessMap: false),
  lambert('Lambert', 'Lambert', usesMetallicRoughnessMap: false),
  blinnPhong('Blinn-Phong', 'BlinnPhong'),
  pbr('PBR (GGX)', 'Pbr'),
  toon('Toon', 'Toon'),
  normals(
    'Normals',
    'Normals',
    usesFragInfo: false,
    usesAlbedoTexture: false,
    usesMaterialMaps: false,
    usesMetallicRoughnessMap: false,
  );

  const LightingModel(
    this.label,
    this.shaderName, {
    this.usesFragInfo = true,
    this.usesAlbedoTexture = true,
    this.usesMaterialMaps = true,
    this.usesMetallicRoughnessMap = true,
  }) : assert(
          !usesMetallicRoughnessMap || usesMaterialMaps,
          'the metallic-roughness map is one of the material maps, so a model '
          'that samples no maps cannot sample it either. Getting this pair '
          'wrong is not a warning at run time: the renderer binds a texture '
          'the compiled shader has no slot for, and the bind fails. Unlit sat '
          'in exactly that state until a golden caught it.',
        );

  /// Shown in the UI.
  final String label;

  /// Entry name inside whichever bundle the backend supplied.
  ///
  /// This is the contract the engine cannot abstract away: it names shaders,
  /// and every backend must ship a bundle containing them under these names.
  /// For `flutter3d_gpu` they are listed in that package's
  /// `shaders/flutter3d.shaderbundle.json`; a second backend needs its own set
  /// answering to the same names.
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

  /// Models that ignore the material sliders, so the UI can disable them.
  bool get usesMaterialParameters =>
      this != LightingModel.unlit && this != LightingModel.normals;

  /// Only the physical model interprets metallic.
  bool get usesMetallic => this == LightingModel.pbr;
}
