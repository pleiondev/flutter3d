/// A material's lighting model as JSON: how `.fmat` names one, and how
/// `.f3d`'s `materialLighting` section stores one.
///
/// **Shared, not exported.** Both formats must read each other's words the
/// same way, so the reading and the writing live once, here; neither is part
/// of the public API.
library;

import '../lighting_model.dart';

/// Reads the shader this material asks for.
///
/// A string names one the engine ships; an object describes one it does not, and
/// must then declare what the compiled shader binds. The flags default to the
/// same values [LightingModel] does, so a custom lit shader is three keys.
LightingModel? readLightingJson(
  Object? value,
  List<String> warnings, {
  String key = 'lighting',
}) {
  if (value == null) return null;
  if (value is String) {
    // The engine's models and every one a plugin registered: a file naming
    // an addon's model reads as it while the addon is installed.
    final named = LightingModels.named(value);
    if (named != null) return named;
    warnings.add(
      '"$value" is not a shader this engine ships or a plugin registered. '
      'Name it as an object with '
      'a "shader" key to use one from your own bundle; the scene\'s model is '
      'used instead.',
    );
    return null;
  }
  if (value is! Map<String, Object?>) {
    warnings.add('"$key" is neither a name nor an object; ignored');
    return null;
  }
  final shader = value['shader'];
  if (shader is! String) {
    warnings.add('"$key" has no "shader" name; ignored');
    return null;
  }
  return LightingModel(
    value['label'] as String? ?? shader,
    shader,
    vertexShaderName: value['vertexShader'] as String?,
    usesFragInfo: value['fragInfo'] as bool? ?? true,
    usesAlbedoTexture: value['albedoTexture'] as bool? ?? true,
    usesMaterialMaps: value['materialMaps'] as bool? ?? true,
    usesMetallicRoughnessMap:
        value['metallicRoughnessMap'] as bool? ??
        (value['materialMaps'] as bool? ?? true),
    usesMaterialParameters: value['materialParameters'] as bool? ?? true,
    usesMetallic: value['metallic'] as bool? ?? false,
    usesEnvironment: value['environment'] as bool? ?? false,
    usesLightList: value['lightList'] as bool?,
    usesFogInfo: value['fogInfo'] as bool?,
    // Absent in every file written before 0.7.3, a saved polyline among them,
    // and `PolylineVertex` declares no morphs: reading it as true brought back
    // the "Failed to bind texture" 0.7.2 fixed. Any other stage is written
    // from `MeshVertex` and does.
    vertexStageMorphs:
        value['vertexMorphs'] as bool? ??
        (LightingModel.polyline.vertexShaderName != value['vertexShader']),
  );
}

Object writeLightingJson(LightingModel model) {
  // By name when the name reads back as this very model — built in or
  // registered — and as a description otherwise.
  if (identical(LightingModels.named(model.shaderName), model)) {
    return model.shaderName;
  }
  const plain = LightingModel('', '');
  return <String, Object?>{
    'shader': model.shaderName,
    if (model.label != model.shaderName) 'label': model.label,
    // The vertex stage a material brings (`gfx-75n`). Left out, a material
    // saved and read back drew with the engine's own vertex stage — an ocean
    // gone flat, with nothing in the file to say why.
    if (model.vertexShaderName case final String vertex) 'vertexShader': vertex,
    if (model.usesFragInfo != plain.usesFragInfo)
      'fragInfo': model.usesFragInfo,
    if (model.usesAlbedoTexture != plain.usesAlbedoTexture)
      'albedoTexture': model.usesAlbedoTexture,
    if (model.usesMaterialMaps != plain.usesMaterialMaps)
      'materialMaps': model.usesMaterialMaps,
    if (model.usesMetallicRoughnessMap != model.usesMaterialMaps)
      'metallicRoughnessMap': model.usesMetallicRoughnessMap,
    if (model.usesLightList != model.usesMaterialMaps)
      'lightList': model.usesLightList,
    if (model.usesFogInfo != model.usesFragInfo) 'fogInfo': model.usesFogInfo,
    if (model.vertexStageMorphs != plain.vertexStageMorphs)
      'vertexMorphs': model.vertexStageMorphs,
    if (model.usesMaterialParameters != plain.usesMaterialParameters)
      'materialParameters': model.usesMaterialParameters,
    if (model.usesMetallic != plain.usesMetallic)
      'metallic': model.usesMetallic,
    if (model.usesEnvironment != plain.usesEnvironment)
      'environment': model.usesEnvironment,
  };
}
