/// A Unity material (`.mat`) — the built-in Standard shader, URP's Lit and
/// HDRP's Lit — as the engine's metal-rough surface.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:vector_math/vector_math.dart';

import 'materials.dart';
import 'output.dart';
import 'report.dart';
import 'texture_files.dart';
import 'unity_yaml.dart';

/// The shaders a `.mat` names by GUID, and the pipeline each belongs to.
const Map<String, String> _shaderGuids = <String, String>{
  '933532a4fcc9baf4fa0491de14d08ed7': 'urp-lit',
  '8d2bb70cbf9db8d4da26e15b26e74248': 'urp-simple-lit',
  '650dd9526735d5b46b79224bc6e94025': 'urp-unlit',
  '6e4ae4064600d784cac1e41a9e6f2e59': 'hdrp-lit',
  'c4edd00ff2db5b24391a4fcb1762e459': 'hdrp-unlit',
};

/// The built-in Standard shaders, by file ID under the built-in GUID.
const Map<int, String> _builtInShaders = <int, String>{
  46: 'standard',
  45: 'standard-specular',
  10750: 'unlit-texture',
  10752: 'unlit-color',
};

/// Reads the `.mat` at [path].
MaterialSource? readUnityMaterial(
  String path,
  UnityAssetIndex index,
  ConvertReport report,
) {
  final Map<int, UnityObject> objects;
  try {
    objects = parseUnityYaml(File(path).readAsStringSync());
  } on Object catch (error) {
    report.drop('material $path', '$error');
    return null;
  }
  final material = objects.values
      .where((UnityObject o) => o.classId == UnityClass.material)
      .firstOrNull;
  if (material == null) {
    report.drop('material $path', 'the file holds no Material');
    return null;
  }
  final name = '${material['m_Name'] ?? stemOf(path)}';
  final id = safeFileName(name);
  final shader = unityRef(material['m_Shader']);
  final saved = material['m_SavedProperties'];
  final props = saved is Map ? saved : const <String, Object?>{};
  final textures = _namedList(props['m_TexEnvs']);
  final floats = _namedList(props['m_Floats']);
  final colors = _namedList(props['m_Colors']);
  final keywords = <String>{
    ...'${material['m_ShaderKeywords'] ?? ''}'.split(' '),
    if (material['m_ValidKeywords'] case final List<Object?> list)
      for (final k in list) '$k',
  };

  var pipeline =
      _shaderGuids[shader?.guid] ??
      (shader?.guid == '0000000000000000f000000000000000'
          ? _builtInShaders[shader?.fileId]
          : null);
  if (pipeline == null) {
    pipeline = textures.containsKey('_BaseColorMap')
        ? 'hdrp-lit'
        : (textures.containsKey('_BaseMap') ? 'urp-lit' : 'standard');
    report.warn(
      'material "$name": its shader (${index.path(shader?.guid) ?? shader?.guid ?? 'unknown'}) '
      'is not one this reads; its properties are read as $pipeline\'s',
    );
  }
  final hdrp = pipeline.startsWith('hdrp');
  final urp = pipeline.startsWith('urp');

  double number(String key, double fallback) => switch (floats[key]) {
    final num n => n.toDouble(),
    _ => fallback,
  };
  Vector4? color(String key) => switch (colors[key]) {
    final Map<Object?, Object?> c => Vector4(
      _num(c['r'], 1),
      _num(c['g'], 1),
      _num(c['b'], 1),
      _num(c['a'], 1),
    ),
    _ => null,
  };

  final images = <MaterialImage>[];
  int addImage(MaterialImage image) {
    final at = images.indexWhere((MaterialImage i) => i.name == image.name);
    if (at >= 0) return at;
    images.add(image);
    return images.length - 1;
  }

  ({MaterialImage image, TextureTransform? transform})? texture(String key) {
    final env = textures[key];
    if (env is! Map) return null;
    final ref = unityRef(env['m_Texture']);
    if (ref == null || ref.fileId == 0) return null;
    final asset = index.path(ref.guid);
    if (asset == null) {
      report.drop(
        'material "$name" $key',
        'its texture (guid ${ref.guid}) has no .meta in the project',
      );
      return null;
    }
    final image = loadTextureFile(asset, report);
    if (image == null) return null;
    final scale = env['m_Scale'];
    final offset = env['m_Offset'];
    final sx = scale is Map ? _num(scale['x'], 1) : 1.0;
    final sy = scale is Map ? _num(scale['y'], 1) : 1.0;
    final ox = offset is Map ? _num(offset['x'], 0) : 0.0;
    final oy = offset is Map ? _num(offset['y'], 0) : 0.0;
    final identity = sx == 1.0 && sy == 1.0 && ox == 0.0 && oy == 0.0;
    // Unity's v runs up the image and the engine's down: v' = v·s + o in
    // Unity's terms is v' = v·s + (1 − s − o) in the engine's.
    return (
      image: image,
      transform: identity
          ? null
          : TextureTransform(
              offset: Vector2(ox, 1.0 - sy - oy),
              scale: Vector2(sx, sy),
            ),
    );
  }

  TextureBinding? bind(
    ({MaterialImage image, TextureTransform? transform})? t,
  ) => t == null
      ? null
      : TextureBinding(imageIndex: addImage(t.image), transform: t.transform);

  final baseKey = hdrp ? '_BaseColorMap' : (urp ? '_BaseMap' : '_MainTex');
  final base = texture(baseKey);
  final baseColour =
      color(hdrp || urp ? '_BaseColor' : '_Color') ??
      Vector4(1.0, 1.0, 1.0, 1.0);

  if (pipeline.contains('unlit')) {
    report.map('material "$name" ($pipeline) -> unlit');
    return MaterialSource(
      id,
      SurfaceMaterial(
        name: id,
        baseColor: _fromSrgb(baseColour),
        baseColorTexture: bind(base),
        unlit: true,
      ),
      images: images,
    );
  }
  if (pipeline == 'standard-specular' ||
      (urp && number('_WorkflowMode', 1) == 0)) {
    report.warn(
      'material "$name" uses the specular workflow; it is read as a '
      'dielectric with its smoothness, and its specular colour is dropped',
    );
  }

  // Metal and smoothness: one image in Unity's layout (metal in red,
  // smoothness in alpha) — HDRP adds occlusion in green — repacked into
  // glTF's.
  final metalKey = hdrp ? '_MaskMap' : '_MetallicGlossMap';
  final metalMap = texture(metalKey);
  final occlusionMap = hdrp ? null : texture('_OcclusionMap');
  final smoothness = hdrp
      ? number('_Smoothness', 0.5)
      : (urp
            ? number('_Smoothness', 0.5)
            : (metalMap != null
                  ? number('_GlossMapScale', 1.0)
                  : number('_Glossiness', 0.5)));
  final metallic = number('_Metallic', 0.0);
  TextureBinding? metalRough;
  TextureBinding? occlusion;
  if (metalMap != null || occlusionMap != null) {
    final packed = repackMetalRough(
      name: '${id}_orm.png',
      metal: metalMap?.image,
      occlusion: hdrp ? metalMap?.image : occlusionMap?.image,
      // Unity's Standard occlusion map is read from green; HDRP's mask
      // keeps it in green too.
      occlusionChannel: 1,
      smoothnessScale: metalMap != null ? smoothness : 1.0,
    );
    if (packed == null) {
      report.drop(
        'material "$name" $metalKey',
        'the image could not be decoded',
      );
    } else {
      final at = addImage(packed);
      final transform = (metalMap ?? occlusionMap)!.transform;
      if (metalMap != null) {
        metalRough = TextureBinding(imageIndex: at, transform: transform);
      }
      if (hdrp ? metalMap != null : occlusionMap != null) {
        occlusion = TextureBinding(imageIndex: at, transform: transform);
      }
      report.map(
        'material "$name" $metalKey${occlusionMap != null ? ' and _OcclusionMap' : ''} '
        '-> ${packed.name}, repacked as occlusion/roughness/metal',
      );
    }
  }

  final normalMap = texture(hdrp ? '_NormalMap' : '_BumpMap');
  final normalScale = number(hdrp ? '_NormalScale' : '_BumpScale', 1.0);

  final emissionOn =
      hdrp ||
      keywords.contains('_EMISSION') ||
      number('_EmissionEnabled', 0) > 0;
  final emissionColour = emissionOn
      ? color(hdrp ? '_EmissiveColor' : '_EmissionColor')
      : null;
  final emissionMap = emissionOn
      ? texture(hdrp ? '_EmissiveColorMap' : '_EmissionMap')
      : null;
  final peak = emissionColour == null
      ? 0.0
      : <double>[
          emissionColour.x,
          emissionColour.y,
          emissionColour.z,
        ].reduce((a, b) => a > b ? a : b);

  final (alphaMode, cutoff) = _alpha(pipeline, number);
  final doubleSided = hdrp
      ? number('_DoubleSidedEnable', 0) > 0
      : (urp ? number('_Cull', 2) == 0 : false);

  final dropped = <String>[
    for (final key in textures.keys)
      if (_isSet(textures[key]) &&
          !<String>{
            baseKey,
            metalKey,
            '_OcclusionMap',
            hdrp ? '_NormalMap' : '_BumpMap',
            hdrp ? '_EmissiveColorMap' : '_EmissionMap',
          }.contains(key))
        key,
  ];
  for (final key in dropped) {
    report.drop(
      'material "$name" $key',
      'the engine\'s surface has no slot for it (detail, parallax and '
          'coat maps are not converted)',
    );
  }

  report.map('material "$name" ($pipeline) -> metal-rough');
  return MaterialSource(
    id,
    SurfaceMaterial(
      name: id,
      baseColor: _fromSrgb(baseColour),
      baseColorTexture: bind(base),
      metallic: metalRough != null ? 1.0 : metallic,
      roughness: metalRough != null ? 1.0 : 1.0 - smoothness,
      metallicRoughnessTexture: metalRough,
      occlusionTexture: occlusion,
      occlusionStrength: number(
        hdrp ? '_AORemapMax' : '_OcclusionStrength',
        1.0,
      ),
      normalTexture: bind(normalMap),
      normalScale: normalScale,
      emissive: peak > 0.0
          ? LinearColor(
              emissionColour!.x,
              emissionColour.y,
              emissionColour.z,
            ).scaled(1.0 / (peak > 1.0 ? peak : 1.0))
          : (emissionMap != null ? LinearColor.white : LinearColor.black),
      emissiveStrength: peak > 1.0 ? peak : 1.0,
      emissiveTexture: bind(emissionMap),
      alphaMode: alphaMode,
      alphaCutoff: cutoff,
      doubleSided: doubleSided,
    ),
    images: images,
  );
}

(SurfaceAlphaMode, double) _alpha(
  String pipeline,
  double Function(String, double) number,
) {
  final cutoff = number(
    pipeline.startsWith('hdrp') ? '_AlphaCutoff' : '_Cutoff',
    0.5,
  );
  if (pipeline.startsWith('hdrp')) {
    if (number('_AlphaCutoffEnable', 0) > 0) {
      return (SurfaceAlphaMode.mask, cutoff);
    }
    return (
      number('_SurfaceType', 0) > 0
          ? SurfaceAlphaMode.blend
          : SurfaceAlphaMode.opaque,
      cutoff,
    );
  }
  if (pipeline.startsWith('urp')) {
    if (number('_AlphaClip', 0) > 0) return (SurfaceAlphaMode.mask, cutoff);
    return (
      number('_Surface', 0) > 0
          ? SurfaceAlphaMode.blend
          : SurfaceAlphaMode.opaque,
      cutoff,
    );
  }
  return switch (number('_Mode', 0).toInt()) {
    1 => (SurfaceAlphaMode.mask, cutoff),
    2 || 3 => (SurfaceAlphaMode.blend, cutoff),
    _ => (SurfaceAlphaMode.opaque, cutoff),
  };
}

bool _isSet(Object? env) {
  if (env is! Map) return false;
  final ref = unityRef(env['m_Texture']);
  return ref != null && ref.fileId != 0;
}

double _num(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

/// Unity's `- _Name: value` lists, as one map.
Map<String, Object?> _namedList(Object? value) {
  final out = <String, Object?>{};
  if (value is List) {
    for (final entry in value) {
      if (entry is Map && entry.isNotEmpty) {
        out['${entry.keys.first}'] = entry.values.first;
      }
    }
  } else if (value is Map) {
    // serializedVersion 2 wrote a map rather than a list.
    for (final MapEntry(:key, :value) in value.entries) {
      out['$key'] = value;
    }
  }
  return out;
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
