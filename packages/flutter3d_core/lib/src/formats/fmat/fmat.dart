import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show FormatSpec;
import 'package:vector_math/vector_math.dart';

import '../format_exceptions.dart';
import '../lighting_model.dart';
import '../material_document.dart';
import '../surface_material.dart';
import 'lighting_json.dart';

/// The version this reader writes, and the newest it reads.
///
/// Every version up to it is read: a later one that changes what a key means
/// lifts the older file in `readFmat` before anything is decoded, and mints a
/// fixture under `test/fixtures/v<N>/` (decision 8 of
/// `tasks/1.0-stability.md`). Only a file from the future is refused.
///
/// **Additions do not bump it, and `hints` is the case that proves why.** The
/// gate below refuses a whole file whose number is larger than this one, so
/// raising it to two would make every `.fmat` written since — and every one an
/// artist has on disk — unreadable by the readers already shipped, in exchange
/// for a key those readers would have ignored anyway. A version is for a
/// difference that changes what the old reader would *draw*; a new key that an
/// old reader skips with a warning is not one.
const int fmatVersion = 1;

/// `.fmat` in the format registry.
///
/// **The envelope is additive at version 1.** [writeFmat] puts the shared
/// envelope first and keeps the format's own key, `fmat`, after it, because
/// a `.fmat` travels inside a `.f3d` bundle that a 0.8 reader still opens, and
/// that reader refuses a material without `fmat`. A file from before the
/// envelope, with `fmat` alone, is the same version 1.
const FormatSpec fmatFormat = FormatSpec(
  id: 'f3d.fmat',
  version: fmatVersion,
  suffixes: <String>['.fmat'],
  fixture: 'test/fixtures/v<N>/brass.fmat',
  legacyVersionKey: 'fmat',
);

/// Whether [bytes] look like a `.fmat`.
///
/// Sniffed rather than trusted to the suffix, because `MaterialDecoder.handles`
/// is handed files whose names may be empty — and because a JSON file that does
/// not declare itself is somebody else's JSON.
bool isFmat(Uint8List bytes) {
  // Cheap enough to be worth doing before parsing, and the parse is what would
  // otherwise throw on a PNG.
  // The envelope comes first in what this build writes, so the format's id
  // is what the head holds; a file from before the envelope starts with the
  // `fmat` key.
  final head = utf8.decode(
    bytes.length < 64 ? bytes : bytes.sublist(0, 64),
    allowMalformed: true,
  );
  return head.contains('"${fmatFormat.id}"') || head.contains('"fmat"');
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
  final Object? parsed;
  try {
    parsed = json.decode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw FmatFormatException('$name is not JSON: ${error.message}');
  }
  if (parsed is! Map<String, Object?>) {
    throw FmatFormatException('$name is not a JSON object');
  }
  // A JSON object that names neither this format nor carries its own key is
  // somebody else's JSON, not a version 1 material with every default.
  if (!fmatFormat.claims(parsed)) {
    throw FmatFormatException(
      '$name has no "fmat" version key and no "format": "${fmatFormat.id}"',
    );
  }
  // A newer version, another format's document or a `requires` this build
  // does not know is refused here, naming both versions. Newer material files
  // are not read as older ones, because the difference between the two
  // versions is precisely what would be silently dropped. Version 1 is the
  // only one, so there is nothing to lift yet.
  fmatFormat.open(
    parsed,
    refuse: (String message) => FmatFormatException('$name: $message'),
  );

  // Exactly the keys `writeFmat` emits, so the two halves of the format
  // cannot drift: a key added to the writer and not to this set warns on the
  // writer's own output, which `fmat_test.dart`'s round trip catches.
  const knownKeys = _writtenKeys;
  final warnings = <String>[
    for (final key in parsed.keys)
      if (!knownKeys.contains(key))
        '"$key" is not a key this reader knows; kept as it is',
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
      transform: _readTransform(value['transform'], warnings),
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

  final surface = surfaceMaterialFromJson(
    parsed,
    name: name.isEmpty ? null : name,
    warnings: warnings,
    baseColorTexture: binding(textures['albedo']),
    metallicRoughnessTexture: binding(textures['metallicRoughness']),
    normalTexture: binding(textures['normal']),
    occlusionTexture: binding(textures['occlusion']),
    emissiveTexture: binding(textures['emissive']),
    // glTF's own shape, with a `.fmat` slot — a path or an object — wherever
    // glTF puts a texture info, so an extension reads the same here as in the
    // file it was imported from.
    extensions: switch (parsed['extensions']) {
      final Map<String, Object?> layers => materialExtensionsFromJson(
        layers,
        texture: binding,
        warnings: warnings,
        where: name.isEmpty ? 'this material' : name,
      ),
      _ => null,
    },
  );

  return MaterialDocument(
    surface: surface,
    images: images,
    lighting: readLightingJson(parsed['lighting'], warnings),
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
    unknown: <String, Object?>{
      for (final MapEntry(:key, :value) in parsed.entries)
        if (!knownKeys.contains(key)) key: value,
    },
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
    final transform = switch (binding.transform) {
      final TextureTransform moved when !moved.isIdentity => moved,
      _ => null,
    };
    const plain = TextureSampling();
    if (transform == null &&
        sampling.magLinear == plain.magLinear &&
        sampling.minLinear == plain.minLinear &&
        sampling.useMipmaps == plain.useMipmaps &&
        sampling.mipLinear == plain.mipLinear &&
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
      if (!sampling.mipLinear) 'mipLinear': false,
      if (sampling.wrapS != TextureWrap.repeat)
        'wrapS': _wrapWord(sampling.wrapS),
      if (sampling.wrapT != TextureWrap.repeat)
        'wrapT': _wrapWord(sampling.wrapT),
      if (transform != null) 'transform': _writeTransform(transform),
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
  final json = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    ...fmatFormat.envelope(),
    // Beside the envelope for a 0.8 reader, which refuses a material without
    // it (see [fmatFormat]).
    'fmat': fmatVersion,
    if (lighting != null) 'lighting': writeLightingJson(lighting),
    ...surfaceMaterialToJson(surface),
    if (textures.isNotEmpty) 'textures': textures,
    if (surface.extensions case final layers?)
      if (materialExtensionsToJson(layers, texture: slot) case final written
          when written.isNotEmpty)
        'extensions': written,
    if (document.parameterBlock != 'MaterialParams')
      'parameterBlock': document.parameterBlock,
    if (document.parameters.isNotEmpty)
      'parameters': <String, Object?>{
        for (final entry in document.parameters.entries)
          entry.key: <double>[for (final v in entry.value) _cleanFloat32(v)],
      },
    if (document.hints.isNotEmpty) 'hints': _writeHints(document.hints),
    // What a later build wrote and this one does not read, last and as it
    // came, so opening and saving a material does not lose it.
    for (final MapEntry(:key, :value) in document.unknown.entries)
      if (!_writtenKeys.contains(key)) key: value,
  });
  return '${_ensureFloatLiterals(json)}\n';
}

/// Every number [writeFmat] writes past `fmat` itself is conceptually a
/// double — the format declares no schema distinguishing `1` from `1.0` —
/// and a double that happens to hold a whole number writes as a bare
/// integer regardless of why: on the Dart VM because `JsonEncoder` checks
/// `is int` and a whole-number double is not one, and on the web because it
/// is — `1.0 is int` is `true` there, the one thing JavaScript's single
/// number type cannot keep apart from Dart's two. A colour with every
/// channel at full strength would then write three channels with a decimal
/// point and the fourth without, on the web only, for a reader who would
/// never see the difference on desktop.
///
/// Every field this format reads back already goes through `num.toDouble()`
/// or `.toInt()` rather than trusting which shape the literal came in as
/// (`readFmat`'s own `_number` and the version check both do), so appending
/// `.0` costs nothing to read — including to the handful of fields, like a
/// colour hint's channel count, that happen to be genuine integers. `fmat`
/// and the envelope's `version` are the exceptions worth keeping bare: a
/// version number that looks like one.
final RegExp _bareIntegerLine = RegExp(
  r'^(\s*(?:"[^"]+"\s*:\s*)?)(-?\d+)(,?)\s*$',
);

String _ensureFloatLiterals(String json) => json
    .split('\n')
    .map((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('"fmat"') || trimmed.startsWith('"version"')) {
        return line;
      }
      final match = _bareIntegerLine.firstMatch(line);
      return match == null ? line : '${match[1]}${match[2]}.0${match[3]}';
    })
    .join('\n');

/// [surface]'s own scalar and colour fields, keyed the way [writeFmat] nests
/// them into a `.fmat` — everything but its texture slots, which
/// [surfaceMaterialFromJson] takes as separate, already-resolved arguments
/// rather than reading here.
///
/// **`doc-25`'s own remaining half, once `mat-01` absorbed the rest**: the
/// one place these eleven field names and shapes are spelled out, so a
/// material editor's own `SetMaterialField` and this format's own writer
/// cannot drift the way two hand-written lists of the same fields always
/// eventually do.
///
/// **Texture slots stay out on purpose.** [SurfaceMaterial] holds a
/// [TextureBinding] for each, but a binding's own `imageIndex` only means
/// anything against the [MaterialDocument] it came from — resolving a path
/// to one, or interning a new one, is a whole document's business, not one
/// material's, which is why [readFmat] still does that part itself before
/// handing the result to [surfaceMaterialFromJson].
Map<String, Object?> surfaceMaterialToJson(SurfaceMaterial surface) =>
    <String, Object?>{
      if (surface.name != null) 'name': surface.name,
      // sRGB-encoded in the file, as it always was.
      'baseColor': <double>[
        _cleanFloat32(surface.baseColor.toSrgb().r),
        _cleanFloat32(surface.baseColor.toSrgb().g),
        _cleanFloat32(surface.baseColor.toSrgb().b),
        _cleanFloat32(surface.baseColor.a),
      ],
      if (surface.metallic != 0.0) 'metallic': surface.metallic,
      if (surface.roughness != 0.5) 'roughness': surface.roughness,
      if (surface.normalScale != 1.0) 'normalScale': surface.normalScale,
      if (surface.occlusionStrength != 1.0)
        'occlusionStrength': surface.occlusionStrength,
      if (surface.emissive.r != 0.0 ||
          surface.emissive.g != 0.0 ||
          surface.emissive.b != 0.0)
        'emissive': <double>[
          _cleanFloat32(surface.emissive.r),
          _cleanFloat32(surface.emissive.g),
          _cleanFloat32(surface.emissive.b),
        ],
      if (surface.emissiveStrength != 1.0)
        'emissiveStrength': surface.emissiveStrength,
      if (surface.alphaMode != SurfaceAlphaMode.opaque)
        'alphaMode': switch (surface.alphaMode) {
          SurfaceAlphaMode.opaque => 'opaque',
          SurfaceAlphaMode.mask => 'mask',
          SurfaceAlphaMode.blend => 'blend',
        },
      if (surface.alphaCutoff != 0.5) 'alphaCutoff': surface.alphaCutoff,
      if (surface.doubleSided) 'doubleSided': true,
      if (surface.unlit) 'unlit': true,
      if (surface.lightingModel case final LightingModel model)
        'lightingModel': writeLightingJson(model),
    };

/// The inverse of [surfaceMaterialToJson]: a [SurfaceMaterial] built from
/// [json]'s own scalar and colour fields, with [name] as the fallback for a
/// document that names itself no other way and the five texture bindings
/// supplied by the caller — already resolved against whatever document
/// [json] came from, the same division [surfaceMaterialToJson] draws.
///
/// A field [json] does not carry reads as the same default
/// [SurfaceMaterial]'s own constructor gives it; an `alphaMode` this build
/// has never heard of is reported through [warnings] and read as `opaque`,
/// the identical fallback [readFmat] has always given one.
SurfaceMaterial surfaceMaterialFromJson(
  Map<String, Object?> json, {
  String? name,
  List<String>? warnings,
  TextureBinding? baseColorTexture,
  TextureBinding? normalTexture,
  TextureBinding? metallicRoughnessTexture,
  TextureBinding? occlusionTexture,
  TextureBinding? emissiveTexture,
  MaterialExtensions? extensions,
}) => SurfaceMaterial(
  name: json['name'] as String? ?? name,
  baseColor: switch (_vec4(json['baseColor'])) {
    final Vector4 srgb => LinearColor.fromSrgb(srgb.x, srgb.y, srgb.z, srgb.w),
    null => LinearColor.white,
  },
  metallic: _number(json['metallic'], 0.0),
  roughness: _number(json['roughness'], 0.5),
  baseColorTexture: baseColorTexture,
  metallicRoughnessTexture: metallicRoughnessTexture,
  normalTexture: normalTexture,
  normalScale: _number(json['normalScale'], 1.0),
  occlusionTexture: occlusionTexture,
  occlusionStrength: _number(json['occlusionStrength'], 1.0),
  emissiveTexture: emissiveTexture,
  emissive: switch (_vec3(json['emissive'])) {
    final Vector3 linear => LinearColor(linear.x, linear.y, linear.z),
    null => LinearColor.black,
  },
  emissiveStrength: _number(json['emissiveStrength'], 1.0),
  alphaMode: _alphaMode(json['alphaMode'], warnings ?? <String>[]),
  alphaCutoff: _number(json['alphaCutoff'], 0.5),
  doubleSided: json['doubleSided'] as bool? ?? false,
  unlit: json['unlit'] as bool? ?? false,
  lightingModel: readLightingJson(
    json['lightingModel'],
    warnings ?? <String>[],
    key: 'lightingModel',
  ),
  extensions: extensions,
);

/// A slot's `transform`, `KHR_texture_transform`'s three fields under its
/// own names (`offset` for its `offset`, `scale`, `rotation` in radians),
/// each optional — an additive key, read by nothing older, so no version.
/// Null when the slot has none or moves nothing.
TextureTransform? _readTransform(Object? json, List<String> warnings) {
  if (json == null) return null;
  if (json is! Map<String, Object?>) {
    warnings.add('a texture slot\'s "transform" is not an object; ignored');
    return null;
  }
  Vector2? pair(String key) => switch (json[key]) {
    [final num u, final num v] => Vector2(u.toDouble(), v.toDouble()),
    null => null,
    _ => () {
      warnings.add('a texture transform\'s "$key" is not two numbers; ignored');
      return null;
    }(),
  };
  final rotation = switch (json['rotation']) {
    final num turn => turn.toDouble(),
    _ => 0.0,
  };
  final transform = TextureTransform(
    offset: pair('offset'),
    scale: pair('scale'),
    rotation: rotation,
  );
  return transform.isIdentity ? null : transform;
}

/// [transform] as [_readTransform] reads it, with only the fields that move.
Map<String, Object?> _writeTransform(TextureTransform transform) =>
    <String, Object?>{
      if (transform.offset.x != 0.0 || transform.offset.y != 0.0)
        'offset': <double>[transform.offset.x, transform.offset.y],
      if (transform.scale.x != 1.0 || transform.scale.y != 1.0)
        'scale': <double>[transform.scale.x, transform.scale.y],
      if (transform.rotation != 0.0) 'rotation': transform.rotation,
    };

TextureSampling _readSampling(Map<String, Object?> json) => TextureSampling(
  magLinear: json['magLinear'] as bool? ?? true,
  minLinear: json['minLinear'] as bool? ?? true,
  useMipmaps: json['mipmaps'] as bool? ?? true,
  mipLinear: json['mipLinear'] as bool? ?? true,
  wrapS: _wrap(json['wrapS']),
  wrapT: _wrap(json['wrapT']),
);

/// The word a `.fmat` file says for [wrap] — the inverse of [_wrap], spelled
/// out so a rename of a value does not change what the file says.
String _wrapWord(TextureWrap wrap) => switch (wrap) {
  TextureWrap.repeat => 'repeat',
  TextureWrap.clampToEdge => 'clampToEdge',
  TextureWrap.mirroredRepeat => 'mirroredRepeat',
};

TextureWrap _wrap(Object? value) => switch (value) {
  'clampToEdge' => TextureWrap.clampToEdge,
  'mirroredRepeat' => TextureWrap.mirroredRepeat,
  _ => TextureWrap.repeat,
};

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

/// [v] came out of a [Vector4]/[Vector3] component or a parameter's own
/// [Float32List], so it is already a float32 value widened to a double —
/// `0.55` written in comes back as `0.550000011920929`, float32's honest
/// opinion of it. Writing that verbatim
/// would defeat the doc comment above [writeFmat]: a `.fmat` an artist edits
/// and diffs should show the number they typed, not the bits it landed on.
///
/// Picks the shortest decimal of up to nine significant digits whose own
/// float32 rounding lands on the same bits as [v], so the file keeps
/// exactly the precision the format already only carries.
double _cleanFloat32(double v) {
  if (!v.isFinite) return v;
  final Float32List probe = Float32List(1);
  probe[0] = v;
  final target = probe[0];
  for (var digits = 1; digits <= 9; digits++) {
    final double candidate = double.parse(v.toStringAsPrecision(digits));
    probe[0] = candidate;
    if (probe[0] == target) return candidate;
  }
  return v;
}

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

/// Exactly the keys [writeFmat] emits; [readFmat] keeps every other one in
/// [MaterialDocument.unknown].
const Set<String> _writtenKeys = <String>{
  ...FormatSpec.envelopeKeys,
  'fmat',
  'name',
  'lighting',
  'lightingModel',
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
  'extensions',
};
