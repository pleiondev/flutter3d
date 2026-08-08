/// A lighting model, which on flutter_gpu means one pre-built fragment shader.
///
/// Shaders are compiled ahead of time into the bundle, so a material graph
/// cannot be assembled at runtime. Switching models therefore means switching
/// shader — and switching shader means a different `RenderPipeline`, which is
/// why the renderer caches pipelines by [shaderName].
///
/// [usesFragInfo] and [usesAlbedoTexture] are declared rather than detected.
/// Shader reflection cannot answer the question: it reports a uniform block as
/// present because the GLSL *declared* it, even when the compiled shader binds
/// no buffer for it, and binding that phantom block segfaults inside Metal with
/// no Dart stack trace. Explicit metadata is how a real engine keys its
/// permutations anyway.
enum LightingModel {
  unlit('Unlit', 'Unlit'),
  lambert('Lambert', 'Lambert'),
  blinnPhong('Blinn-Phong', 'BlinnPhong'),
  pbr('PBR (GGX)', 'Pbr'),
  toon('Toon', 'Toon'),
  normals(
    'Normals',
    'Normals',
    usesFragInfo: false,
    usesAlbedoTexture: false,
  );

  const LightingModel(
    this.label,
    this.shaderName, {
    this.usesFragInfo = true,
    this.usesAlbedoTexture = true,
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

  /// Models that ignore the material sliders, so the UI can disable them.
  bool get usesMaterialParameters =>
      this != LightingModel.unlit && this != LightingModel.normals;

  /// Only the physical model interprets metallic.
  bool get usesMetallic => this == LightingModel.pbr;
}
