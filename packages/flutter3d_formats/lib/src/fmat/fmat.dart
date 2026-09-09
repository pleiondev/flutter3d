import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../lighting_model.dart';
import '../material_document.dart';
import '../surface_material.dart';

/// The version this reader writes and the only one it accepts.
///
/// **Additions do not bump it, and `hints` is the case that proves why.** The
/// gate below refuses a whole file whose number is larger than this one, so
/// raising it to two would make every `.fmat` written since — and every one an
/// artist has on disk — unreadable by the readers already shipped, in exchange
/// for a key those readers would have ignored anyway. A version is for a
/// difference that changes what the old reader would *draw*; a new key that an
/// old reader skips with a warning is not one.
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
/// Unknown top-level keys are recorded in [MaterialDocument.warnings] rather
/// than thrown on: a file written by a newer tool should still load, minus what
/// this version does not understand, and a hand-edited file with `roughnesss`
/// in it should say so rather than quietly take the default. That is not in
/// tension with the version gate below, which refuses a whole newer `fmat`
/// number outright: a bumped version is the writer declaring that the
/// difference matters, and an extra key in a file that still calls itself
/// version 1 is the writer saying it does not.
///
/// Two namespaces are deliberately open and so are never warned about. A
/// texture slot the [SurfaceMaterial] does not name becomes an entry in
/// [MaterialDocument.extraTextures], and a key under `parameters` becomes a
/// uniform: both exist so a custom shader can ask for something this engine
/// has never heard of.
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

  // Exactly the keys `writeFmat` emits, so the two halves of the format
  // cannot drift: a key added to the writer and not to this set warns on the
  // writer's own output, which `fmat_test.dart`'s round trip catches.
  const knownKeys = <String>{
    'fmat',
    'name',
    'lighting',
    'baseColor',
    'metallic',
    'roughness',
    'normalScale',
    'occlusionStrength',
    'emissive',
    'emissiveStrength',
    'alphaMode',
    'alphaCutoff',
    'doubleSided',
    'unlit',
    'textures',
    'parameterBlock',
    'parameters',
    'hints',
  };
  final warnings = <String>[
    for (final key in parsed.keys)
      if (!knownKeys.contains(key))
        '"$key" is not a key this reader knows; ignored',
  ];
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
  // The slots [SurfaceMaterial] has a field for; everything else under
  // `textures` is an extra, on purpose, and so is never a warning.
  const knownSlots = <String>{
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
    hints: _readHints(parsed['hints'], warnings),
    extraTextures: <String, TextureBinding>{
      for (final entry in textures.entries)
        if (!knownSlots.contains(entry.key))
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
    if (document.hints.isNotEmpty) 'hints': _writeHints(document.hints),
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

/// Reads the `hints` block, which describes the entries in `parameters`.
///
/// **Only the parameters, and only in the file.** The fields every material has
/// are hinted by [builtInMaterialHints]: their ends and their lists are the same
/// in every material ever written, and repeating them here would put a hundred
/// lines of identical text in front of the six an artist edits. What a file
/// alone can say is what a studio's own `windStrength` means, which is exactly
/// what this block is for.
Map<String, MaterialHint> _readHints(Object? value, List<String> warnings) {
  if (value == null) return const <String, MaterialHint>{};
  if (value is! Map<String, Object?>) {
    warnings.add('"hints" is not an object; ignored');
    return const <String, MaterialHint>{};
  }
  final hints = <String, MaterialHint>{};
  for (final entry in value.entries) {
    final body = entry.value;
    if (body is! Map<String, Object?>) {
      warnings.add('the hint for "${entry.key}" is not an object; ignored');
      continue;
    }
    if (_hintKind(entry.key, body, warnings) case final MaterialHintKind kind) {
      hints[entry.key] = MaterialHint(
        kind,
        label: body['label'] as String?,
        help: body['help'] as String?,
      );
    }
  }
  return hints;
}

/// The control a hint asks for, or null and a word when it asks for one this
/// engine has never heard of.
///
/// **A warning rather than a refusal**, the same answer `alphaMode` gives a word
/// it does not know — and for a stronger reason here: a hint that will not parse
/// costs a slider in an editor, and a whole material that will not load costs
/// the level. A tool three versions ahead may write a curve or a gradient, and
/// the file's colours are still good.
MaterialHintKind? _hintKind(
  String name,
  Map<String, Object?> body,
  List<String> warnings,
) => switch (body['kind']) {
  'range' => RangeHint(
    _number(body['min'], 0.0),
    _number(body['max'], 1.0),
    step: body['step'] is num ? _number(body['step'], 0.0) : null,
  ),
  'color' => ColorHint(channels: (body['channels'] as num?)?.toInt() ?? 4),
  'texture' => TextureHint(
    extensions: switch (body['extensions']) {
      final List<Object?> listed => <String>[
        for (final suffix in listed)
          if (suffix is String) suffix,
      ],
      _ => TextureHint.imageSuffixes,
    },
  ),
  'enum' => EnumHint(<EnumHintValue>[
    for (final choice in body['values'] as List<Object?>? ?? const <Object?>[])
      // A choice that is already a word is written as that word, so a list of
      // six of them is six short lines rather than six objects.
      ...switch (choice) {
        final String plain => <EnumHintValue>[EnumHintValue(plain)],
        {'value': final String value, 'label': final String label} =>
          <EnumHintValue>[EnumHintValue(value, label)],
        {'value': final String value} => <EnumHintValue>[EnumHintValue(value)],
        _ => const <EnumHintValue>[],
      },
  ]),
  final Object? kind => () {
    warnings.add(
      '"$kind" is not a hint kind this reader knows, so "$name" is shown '
      'without one; its value is unaffected',
    );
    return null;
  }(),
};

/// Symmetric with [_readHints]: what this writes, that reads back equal.
Object _writeHints(Map<String, MaterialHint> hints) => <String, Object?>{
  for (final entry in hints.entries)
    entry.key: <String, Object?>{
      ..._writeHintKind(entry.value.kind),
      if (entry.value.label case final String label) 'label': label,
      if (entry.value.help case final String help) 'help': help,
    },
};

Map<String, Object?> _writeHintKind(MaterialHintKind kind) => switch (kind) {
  RangeHint(:final min, :final max, :final step) => <String, Object?>{
    'kind': 'range',
    'min': min,
    'max': max,
    'step': ?step,
  },
  ColorHint(:final channels) => <String, Object?>{
    'kind': 'color',
    'channels': channels,
  },
  TextureHint(:final extensions) => <String, Object?>{
    'kind': 'texture',
    'extensions': extensions,
  },
  EnumHint(:final values) => <String, Object?>{
    'kind': 'enum',
    'values': <Object?>[
      for (final choice in values)
        if (choice.label == choice.value)
          choice.value
        else
          <String, Object?>{'value': choice.value, 'label': choice.label},
    ],
  },
};

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
