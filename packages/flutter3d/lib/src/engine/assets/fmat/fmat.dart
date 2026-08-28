import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../../render/lighting_model.dart';
import '../material_document.dart';
import '../surface_material.dart';

/// The version this reader writes and the only one it accepts.
const int kFmatVersion = 1;

/// Whether [bytes] look like a `.fmat`.
///
/// Sniffed rather than trusted to the suffix, because `MaterialDecoder.handles`
/// is handed files whose names may be empty — and because a JSON file that does
/// not declare itself is somebody else's JSON.
bool isFmat(Uint8List bytes) {
  // Cheap enough to be worth doing before parsing, and the parse is what would
  // otherwise throw on a PNG.
  final head = bytes.length < 64 ? bytes : bytes.sublist(0, 64);
  return utf8.decode(head, allowMalformed: true).contains('"fmat"');
}

/// Reads a `.fmat` material.
///
/// **JSON, and text on purpose.** A material is a few hundred bytes that an
/// artist edits between two runs of the game and that shows up in a diff when
/// the look of something changes; a binary container would buy nothing here and
/// cost both. Models are the other case and have their own container.
///
/// Unknown keys are recorded in [MaterialDocument.warnings] rather than thrown
/// on: a file written by a newer tool should still load, minus what this version
/// does not understand.
MaterialDocument readFmat(Uint8List bytes, {String name = ''}) {
  final Object? parsed = json.decode(utf8.decode(bytes));
  if (parsed is! Map<String, Object?>) {
    throw FormatException('$name is not a JSON object');
  }
  final version = (parsed['fmat'] as num?)?.toInt();
  if (version == null) {
    throw FormatException('$name has no "fmat" version key');
  }
  if (version > kFmatVersion) {
    throw FormatException(
      '$name is version $version and this engine reads $kFmatVersion. Newer '
      'material files are not read as older ones, because the difference '
      'between the two versions is precisely what would be silently dropped.',
    );
  }

  final warnings = <String>[];
  final images = <String>[];
  final texturePaths = <String, int>{};

  /// Interns [path] and returns the index [TextureBinding] addresses it by.
  int imageIndex(String path) =>
      texturePaths[path] ??= (images..add(path)).length - 1;

  TextureBinding? binding(Object? value) {
    if (value == null) return null;
    if (value is String) return TextureBinding(imageIndex: imageIndex(value));
    if (value is! Map<String, Object?>) {
      warnings.add('a texture slot is neither a path nor an object; ignored');
      return null;
    }
    final path = value['path'];
    if (path is! String) {
      warnings.add('a texture slot has no "path"; ignored');
      return null;
    }
    return TextureBinding(
      imageIndex: imageIndex(path),
      sampling: _readSampling(value),
    );
  }

  final textures =
      parsed['textures'] as Map<String, Object?>? ?? const <String, Object?>{};
  const known = <String>{
    'albedo',
    'normal',
    'metallicRoughness',
    'occlusion',
    'emissive',
  };

  final surface = SurfaceMaterial(
    name: parsed['name'] as String? ?? (name.isEmpty ? null : name),
    baseColor: _vec4(parsed['baseColor']) ?? Vector4(1.0, 1.0, 1.0, 1.0),
    metallic: _number(parsed['metallic'], 0.0),
    roughness: _number(parsed['roughness'], 0.5),
    baseColorTexture: binding(textures['albedo']),
    metallicRoughnessTexture: binding(textures['metallicRoughness']),
    normalTexture: binding(textures['normal']),
    normalScale: _number(parsed['normalScale'], 1.0),
    occlusionTexture: binding(textures['occlusion']),
    occlusionStrength: _number(parsed['occlusionStrength'], 1.0),
    emissiveTexture: binding(textures['emissive']),
    emissive: _vec3(parsed['emissive']) ?? Vector3.zero(),
    emissiveStrength: _number(parsed['emissiveStrength'], 1.0),
    alphaMode: _alphaMode(parsed['alphaMode'], warnings),
    alphaCutoff: _number(parsed['alphaCutoff'], 0.5),
    doubleSided: parsed['doubleSided'] as bool? ?? false,
    unlit: parsed['unlit'] as bool? ?? false,
  );

  return MaterialDocument(
    surface: surface,
    images: images,
    lighting: _readLighting(parsed['lighting'], warnings),
    parameterBlock: parsed['parameterBlock'] as String? ?? 'MaterialParams',
    parameters: <String, Float32List>{
      for (final entry
          in (parsed['parameters'] as Map<String, Object?>? ??
                  const <String, Object?>{})
              .entries)
        entry.key: _floats(entry.value),
    },
    extraTextures: <String, TextureBinding>{
      for (final entry in textures.entries)
        if (!known.contains(entry.key))
          if (binding(entry.value) case final TextureBinding slot)
            entry.key: slot,
    },
    warnings: warnings,
  );
}

/// Writes [document] back out, so a tool that edits a material can save it.
///
/// Round-trips: what this writes, [readFmat] reads back to an equal document.
/// That is the property a material editor stands on, and it is measured rather
/// than asserted — see `fmat_test.dart`.
String writeFmat(MaterialDocument document) {
  final surface = document.surface;

  String? pathOf(TextureBinding? slot) =>
      slot == null ||
          slot.imageIndex < 0 ||
          slot.imageIndex >= document.images.length
      ? null
      : document.images[slot.imageIndex];

  Object? slot(TextureBinding? binding) {
    final path = pathOf(binding);
    if (path == null) return null;
    final sampling = binding!.sampling;
    const plain = TextureSampling();
    if (sampling.magLinear == plain.magLinear &&
        sampling.minLinear == plain.minLinear &&
        sampling.useMipmaps == plain.useMipmaps &&
        sampling.wrapS == plain.wrapS &&
        sampling.wrapT == plain.wrapT) {
      // A slot that asks for nothing unusual is written as the path alone,
      // because that is what an artist writes by hand and what a diff should
      // show when only the path changed.
      return path;
    }
    return <String, Object?>{
      'path': path,
      if (!sampling.magLinear) 'magLinear': false,
      if (!sampling.minLinear) 'minLinear': false,
      if (!sampling.useMipmaps) 'mipmaps': false,
      if (sampling.wrapS != TextureWrap.repeat) 'wrapS': sampling.wrapS.name,
      if (sampling.wrapT != TextureWrap.repeat) 'wrapT': sampling.wrapT.name,
    };
  }

  final textures = <String, Object?>{
    if (slot(surface.baseColorTexture) case final Object value) 'albedo': value,
    if (slot(surface.normalTexture) case final Object value) 'normal': value,
    if (slot(surface.metallicRoughnessTexture) case final Object value)
      'metallicRoughness': value,
    if (slot(surface.occlusionTexture) case final Object value)
      'occlusion': value,
    if (slot(surface.emissiveTexture) case final Object value)
      'emissive': value,
    for (final entry in document.extraTextures.entries)
      if (slot(entry.value) case final Object value) entry.key: value,
  };

  final lighting = document.lighting;
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'fmat': kFmatVersion,
    if (surface.name != null) 'name': surface.name,
    if (lighting != null) 'lighting': _writeLighting(lighting),
    'baseColor': <double>[surface.baseColor.r, surface.baseColor.g, surface.baseColor.b, surface.baseColor.a],
    if (surface.metallic != 0.0) 'metallic': surface.metallic,
    if (surface.roughness != 0.5) 'roughness': surface.roughness,
    if (surface.normalScale != 1.0) 'normalScale': surface.normalScale,
    if (surface.occlusionStrength != 1.0) 'occlusionStrength': surface.occlusionStrength,
    if (surface.emissive.length2 != 0.0) 'emissive': <double>[surface.emissive.r, surface.emissive.g, surface.emissive.b],
    if (surface.emissiveStrength != 1.0) 'emissiveStrength': surface.emissiveStrength,
    if (surface.alphaMode != SurfaceAlphaMode.opaque) 'alphaMode': surface.alphaMode.name,
    if (surface.alphaCutoff != 0.5) 'alphaCutoff': surface.alphaCutoff,
    if (surface.doubleSided) 'doubleSided': true,
    if (surface.unlit) 'unlit': true,
    if (textures.isNotEmpty) 'textures': textures,
    if (document.parameterBlock != 'MaterialParams') 'parameterBlock': document.parameterBlock,
    if (document.parameters.isNotEmpty) 'parameters': <String, Object?>{for (final entry in document.parameters.entries) entry.key: entry.value.toList()},
  })}\n';
}

TextureSampling _readSampling(Map<String, Object?> json) => TextureSampling(
  magLinear: json['magLinear'] as bool? ?? true,
  minLinear: json['minLinear'] as bool? ?? true,
  useMipmaps: json['mipmaps'] as bool? ?? true,
  wrapS: _wrap(json['wrapS']),
  wrapT: _wrap(json['wrapT']),
);

TextureWrap _wrap(Object? value) => switch (value) {
  'clampToEdge' => TextureWrap.clampToEdge,
  'mirroredRepeat' => TextureWrap.mirroredRepeat,
  _ => TextureWrap.repeat,
};

/// Reads the shader this material asks for.
///
/// A string names one the engine ships; an object describes one it does not, and
/// must then declare what the compiled shader binds. The flags default to the
/// same values [LightingModel] does, so a custom lit shader is three keys.
LightingModel? _readLighting(Object? value, List<String> warnings) {
  if (value == null) return null;
  if (value is String) {
    for (final model in LightingModel.builtIn) {
      if (model.shaderName.toLowerCase() == value.toLowerCase()) return model;
    }
    warnings.add(
      '"$value" is not a shader this engine ships. Name it as an object with '
      'a "shader" key to use one from your own bundle; the scene\'s model is '
      'used instead.',
    );
    return null;
  }
  if (value is! Map<String, Object?>) {
    warnings.add('"lighting" is neither a name nor an object; ignored');
    return null;
  }
  final shader = value['shader'];
  if (shader is! String) {
    warnings.add('"lighting" has no "shader" name; ignored');
    return null;
  }
  return LightingModel(
    value['label'] as String? ?? shader,
    shader,
    usesFragInfo: value['fragInfo'] as bool? ?? true,
    usesAlbedoTexture: value['albedoTexture'] as bool? ?? true,
    usesMaterialMaps: value['materialMaps'] as bool? ?? true,
    usesMetallicRoughnessMap:
        value['metallicRoughnessMap'] as bool? ??
        (value['materialMaps'] as bool? ?? true),
    usesMaterialParameters: value['materialParameters'] as bool? ?? true,
    usesMetallic: value['metallic'] as bool? ?? false,
    usesEnvironment: value['environment'] as bool? ?? false,
  );
}

Object _writeLighting(LightingModel model) {
  for (final built in LightingModel.builtIn) {
    if (identical(built, model)) return model.shaderName;
  }
  const plain = LightingModel('', '');
  return <String, Object?>{
    'shader': model.shaderName,
    if (model.label != model.shaderName) 'label': model.label,
    if (model.usesFragInfo != plain.usesFragInfo)
      'fragInfo': model.usesFragInfo,
    if (model.usesAlbedoTexture != plain.usesAlbedoTexture)
      'albedoTexture': model.usesAlbedoTexture,
    if (model.usesMaterialMaps != plain.usesMaterialMaps)
      'materialMaps': model.usesMaterialMaps,
    if (model.usesMetallicRoughnessMap != model.usesMaterialMaps)
      'metallicRoughnessMap': model.usesMetallicRoughnessMap,
    if (model.usesMaterialParameters != plain.usesMaterialParameters)
      'materialParameters': model.usesMaterialParameters,
    if (model.usesMetallic != plain.usesMetallic)
      'metallic': model.usesMetallic,
    if (model.usesEnvironment != plain.usesEnvironment)
      'environment': model.usesEnvironment,
  };
}

SurfaceAlphaMode _alphaMode(Object? value, List<String> warnings) =>
    switch (value) {
      null || 'opaque' => SurfaceAlphaMode.opaque,
      'mask' => SurfaceAlphaMode.mask,
      'blend' => SurfaceAlphaMode.blend,
      _ => () {
        warnings.add('"$value" is not an alpha mode; treated as opaque');
        return SurfaceAlphaMode.opaque;
      }(),
    };

double _number(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

Float32List _floats(Object? value) {
  if (value is num) return Float32List.fromList(<double>[value.toDouble()]);
  if (value is! List<Object?>) return Float32List(0);
  return Float32List.fromList(<double>[
    for (final item in value) item is num ? item.toDouble() : 0.0,
  ]);
}

Vector3? _vec3(Object? value) => value is List<Object?> && value.length >= 3
    ? Vector3(
        _number(value[0], 0.0),
        _number(value[1], 0.0),
        _number(value[2], 0.0),
      )
    : null;

Vector4? _vec4(Object? value) => value is List<Object?> && value.length >= 3
    ? Vector4(
        _number(value[0], 0.0),
        _number(value[1], 0.0),
        _number(value[2], 0.0),
        value.length > 3 ? _number(value[3], 1.0) : 1.0,
      )
    : null;
