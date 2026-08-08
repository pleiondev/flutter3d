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
  unlit('Unlit', 'Unlit', usesMaterialMaps: false),
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
  });

  /// Shown in the UI.
  final String label;

  /// Entry name inside the shader bundle, matching
  /// shaders/flutter3d.shaderbundle.json.
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
