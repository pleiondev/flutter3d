/// A shading network's inputs — UsdPreviewSurface's or MaterialX
/// `standard_surface`'s — folded into the engine's metal-rough surface.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show SamplerAddressMode;
import 'package:vector_math/vector_math.dart';

import 'materials.dart';
import 'report.dart';

/// What a shader input is given.
sealed class InputValue {
  const InputValue();
}

/// A number or a tuple, as authored.
final class ConstantInput extends InputValue {
  /// The constant [values].
  const ConstantInput(this.values);

  /// The components as authored: one for a scalar, three for a colour or a
  /// vector.
  final List<double> values;

  /// The first of [values], in whatever unit the input was authored in; 0
  /// for none.
  double get first => values.isEmpty ? 0.0 : values.first;
}

/// An image, read through one channel or several.
final class TextureInput extends InputValue {
  /// The image [name] with its [bytes], read through [channel] (`rgb` by
  /// default) and repeating on both axes unless told otherwise.
  const TextureInput(
    this.name,
    this.bytes, {
    this.channel = 'rgb',
    this.scale,
    this.wrapS = SamplerAddressMode.repeat,
    this.wrapT = SamplerAddressMode.repeat,
  });

  /// The file name it is written under.
  final String name;

  /// Its bytes, or null when the file could not be found.
  final Uint8List? bytes;

  /// `rgb`, `rgba`, `r`, `g`, `b` or `a`.
  final String channel;

  /// A multiplier the network applies to it (UsdUVTexture's `scale`, a
  /// MaterialX `multiply` by a constant), folded into the factor.
  final List<double>? scale;

  /// How the image is addressed outside nought to one across (U).
  final SamplerAddressMode wrapS;

  /// How the image is addressed outside nought to one down (V).
  final SamplerAddressMode wrapT;
}

/// An input computed by nodes that are neither a constant nor an image.
final class GraphInput extends InputValue {
  /// The input [description] computes, standing in as [fallback] when
  /// there is one.
  const GraphInput(this.description, {this.fallback});

  /// What computes it, for the report.
  final String description;

  /// The nearest image or constant upstream of it, used when the material
  /// is written as parameters anyway.
  final InputValue? fallback;
}

/// The input names of a shading model.
final class ShadingVocabulary {
  const ShadingVocabulary._({
    required this.name,
    required this.baseColor,
    required this.baseWeight,
    required this.metallic,
    required this.roughness,
    required this.emissive,
    required this.emissiveWeight,
    required this.opacity,
    required this.opacityThreshold,
    required this.normal,
    required this.occlusion,
    required this.ior,
    required this.coat,
    required this.coatRoughness,
    required this.transmission,
    required this.sheen,
    required this.sheenColor,
    required this.sheenRoughness,
    required this.linearColours,
  });

  /// The shading model's name, for the report: `UsdPreviewSurface` or
  /// `standard_surface`.
  final String name;

  /// The input holding the base colour, a constant or the base image;
  /// light grey when it is absent.
  final String baseColor;

  /// The input that scales the base colour; null when the model has none.
  final String? baseWeight;

  /// The input holding metalness, a factor from nought to one.
  final String metallic;

  /// The input holding perceptual roughness, a factor from nought to one.
  final String roughness;

  /// The input holding the emitted colour.
  final String emissive;

  /// The input that scales [emissive]; null when the model has none.
  final String? emissiveWeight;

  /// The input holding opacity: a constant, or the base image's alpha.
  final String opacity;

  /// The input whose value above nought makes the material alpha-masked at
  /// that cutoff; null when the model has none.
  final String? opacityThreshold;

  /// The input holding the tangent-space normal image.
  final String normal;

  /// The input holding the ambient occlusion image; null when the model
  /// has none.
  final String? occlusion;

  /// The input holding the index of refraction, a ratio; 1.5 when absent.
  final String ior;

  /// The input holding the clear coat's weight, a factor from nought to
  /// one.
  final String coat;

  /// The input holding the clear coat's roughness, a factor from nought to
  /// one.
  final String coatRoughness;

  /// The input holding transmission, a factor from nought to one; null
  /// when the model has none.
  final String? transmission;

  /// The input holding the sheen's weight, which scales [sheenColor]; null
  /// when the model has none.
  final String? sheen;

  /// The input holding the sheen's colour; null when the model has none.
  final String? sheenColor;

  /// The input holding the sheen's roughness, 0.3 when absent; null when
  /// the model has none.
  final String? sheenRoughness;

  /// Whether its colours are linear, as both of these are.
  final bool linearColours;

  /// Every input this reads; any other input is reported as dropped.
  Set<String> get known => <String>{
    baseColor,
    ?baseWeight,
    metallic,
    roughness,
    emissive,
    ?emissiveWeight,
    opacity,
    ?opacityThreshold,
    normal,
    ?occlusion,
    ior,
    coat,
    coatRoughness,
    ?transmission,
    ?sheen,
    ?sheenColor,
    ?sheenRoughness,
  };

  /// `UsdPreviewSurface`.
  static const ShadingVocabulary previewSurface = ShadingVocabulary._(
    name: 'UsdPreviewSurface',
    baseColor: 'diffuseColor',
    baseWeight: null,
    metallic: 'metallic',
    roughness: 'roughness',
    emissive: 'emissiveColor',
    emissiveWeight: null,
    opacity: 'opacity',
    opacityThreshold: 'opacityThreshold',
    normal: 'normal',
    occlusion: 'occlusion',
    ior: 'ior',
    coat: 'clearcoat',
    coatRoughness: 'clearcoatRoughness',
    transmission: null,
    sheen: null,
    sheenColor: null,
    sheenRoughness: null,
    linearColours: true,
  );

  /// MaterialX `standard_surface`.
  static const ShadingVocabulary standardSurface = ShadingVocabulary._(
    name: 'standard_surface',
    baseColor: 'base_color',
    baseWeight: 'base',
    metallic: 'metalness',
    roughness: 'specular_roughness',
    emissive: 'emission_color',
    emissiveWeight: 'emission',
    opacity: 'opacity',
    opacityThreshold: null,
    normal: 'normal',
    occlusion: null,
    ior: 'specular_IOR',
    coat: 'coat',
    coatRoughness: 'coat_roughness',
    transmission: 'transmission',
    sheen: 'sheen',
    sheenColor: 'sheen_color',
    sheenRoughness: 'sheen_roughness',
    linearColours: true,
  );
}

/// Folds [inputs] of a [vocabulary] surface into a [MaterialSource] called
/// [id]. A [GraphInput] is replaced by its fallback, with a warning: this is
/// the "nearest PBR" path a network that cannot be a program takes.
MaterialSource surfaceFromInputs(
  String id,
  Map<String, InputValue> inputs,
  ShadingVocabulary vocabulary,
  ConvertReport report,
) {
  final images = <MaterialImage>[];
  final resolved = <String, InputValue>{};
  for (final MapEntry(:key, :value) in inputs.entries) {
    if (!vocabulary.known.contains(key)) {
      report.drop(
        'material "$id" input "$key"',
        'the engine\'s surface has no counterpart in ${vocabulary.name}\'s '
            'terms',
      );
      continue;
    }
    if (value case GraphInput(:final description, :final fallback)) {
      report.warn(
        'material "$id" input "$key" is computed by $description; '
        '${fallback == null ? 'its default is used' : 'the nearest image or constant upstream is used'}',
      );
      if (fallback != null) resolved[key] = fallback;
    } else {
      resolved[key] = value;
    }
  }

  int? imageOf(TextureInput texture) {
    final bytes = texture.bytes;
    if (bytes == null) {
      report.drop(
        'material "$id" image "${texture.name}"',
        'the file was not found',
      );
      return null;
    }
    final at = images.indexWhere((MaterialImage i) => i.name == texture.name);
    if (at >= 0) return at;
    images.add(MaterialImage(texture.name, bytes));
    return images.length - 1;
  }

  TextureBinding? bind(TextureInput texture) {
    final index = imageOf(texture);
    if (index == null) return null;
    return TextureBinding(
      imageIndex: index,
      sampling: TextureSampling(wrapS: texture.wrapS, wrapT: texture.wrapT),
    );
  }

  double number(String? name, double fallback) => switch (resolved[name]) {
    ConstantInput(:final first) => first,
    TextureInput(:final scale?) when scale.isNotEmpty => scale.first,
    _ => fallback,
  };

  Vector3 color(String name, Vector3 fallback) => switch (resolved[name]) {
    ConstantInput(:final values) when values.length >= 3 => Vector3(
      values[0],
      values[1],
      values[2],
    ),
    ConstantInput(:final values) when values.length == 1 => Vector3.all(
      values[0],
    ),
    TextureInput(:final scale?) when scale.length >= 3 => Vector3(
      scale[0],
      scale[1],
      scale[2],
    ),
    TextureInput() => Vector3.all(1.0),
    _ => fallback,
  };

  // Base colour: the weight multiplies it, as `standard_surface` defines.
  final weight = number(vocabulary.baseWeight, 1.0);
  final linearBase = color(vocabulary.baseColor, Vector3.all(0.8)) * weight;
  final base = vocabulary.linearColours
      ? Vector3(
          linearToSrgb(linearBase.x),
          linearToSrgb(linearBase.y),
          linearToSrgb(linearBase.z),
        )
      : linearBase;
  final baseTexture = switch (resolved[vocabulary.baseColor]) {
    final TextureInput t => bind(t),
    _ => null,
  };

  // Opacity: a constant, or the alpha of the base colour's own image.
  final opacityInput = resolved[vocabulary.opacity];
  final opacity = switch (opacityInput) {
    ConstantInput(:final values) when values.isNotEmpty =>
      values.length >= 3
          ? (values[0] + values[1] + values[2]) / 3.0
          : values.first,
    _ => 1.0,
  };
  final threshold = number(vocabulary.opacityThreshold, 0.0);
  final alphaFromImage =
      opacityInput is TextureInput &&
      resolved[vocabulary.baseColor] is TextureInput &&
      (resolved[vocabulary.baseColor]! as TextureInput).name ==
          opacityInput.name &&
      opacityInput.channel == 'a';
  if (opacityInput is TextureInput && !alphaFromImage) {
    report.drop(
      'material "$id" opacity image',
      'the engine reads opacity from the base colour image\'s alpha only',
    );
  }
  final alphaMode = threshold > 0.0
      ? SurfaceAlphaMode.mask
      : (opacity < 1.0 || alphaFromImage
            ? SurfaceAlphaMode.blend
            : SurfaceAlphaMode.opaque);

  // Metal and roughness: one image only when it is laid out as glTF's,
  // roughness in green and metal in blue.
  final metalInput = resolved[vocabulary.metallic];
  final roughInput = resolved[vocabulary.roughness];
  TextureBinding? metalRough;
  if (metalInput is TextureInput || roughInput is TextureInput) {
    final sameImage =
        metalInput is TextureInput &&
        roughInput is TextureInput &&
        metalInput.name == roughInput.name &&
        metalInput.channel == 'b' &&
        roughInput.channel == 'g';
    if (sameImage) {
      metalRough = bind(metalInput);
    } else {
      report.drop(
        'material "$id" metal/roughness images',
        'the engine reads one image with roughness in green and metal in '
            'blue; these are laid out otherwise, so their factors are used',
      );
    }
  }
  final metallic = switch (metalInput) {
    ConstantInput(:final first) => first,
    TextureInput(:final scale?) when scale.isNotEmpty => scale.first,
    TextureInput() when metalRough == null => 0.0,
    TextureInput() => 1.0,
    _ => 0.0,
  };
  final roughness = switch (roughInput) {
    ConstantInput(:final first) => first,
    TextureInput(:final scale?) when scale.isNotEmpty => scale.first,
    TextureInput() when metalRough == null => 0.5,
    TextureInput() => 1.0,
    _ => vocabulary == ShadingVocabulary.standardSurface ? 0.2 : 0.5,
  };

  final normalTexture = switch (resolved[vocabulary.normal]) {
    final TextureInput t => bind(t),
    _ => null,
  };
  final occlusionTexture = switch (resolved[vocabulary.occlusion]) {
    final TextureInput t => bind(t),
    _ => null,
  };

  final emissiveWeight = number(vocabulary.emissiveWeight, 1.0);
  final emissiveInput = resolved[vocabulary.emissive];
  final emissive = switch (emissiveInput) {
    null => Vector3.zero(),
    _ => color(vocabulary.emissive, Vector3.zero()) * emissiveWeight,
  };
  final emissiveTexture = switch (emissiveInput) {
    final TextureInput t => bind(t),
    _ => null,
  };

  final ior = number(vocabulary.ior, 1.5);
  final coat = number(vocabulary.coat, 0.0);
  final coatRoughness = number(vocabulary.coatRoughness, 0.0);
  final transmission = number(vocabulary.transmission, 0.0);
  final sheen = number(vocabulary.sheen, 0.0);
  final sheenColor = vocabulary.sheenColor == null
      ? Vector3.zero()
      : color(vocabulary.sheenColor!, Vector3.all(1.0)) * sheen;
  final sheenRoughness = number(vocabulary.sheenRoughness, 0.3);
  final layered =
      (ior - 1.5).abs() > 1e-6 ||
      coat > 0.0 ||
      transmission > 0.0 ||
      sheen > 0.0;
  for (final (name, inputName) in <(String, String?)>[
    ('clear coat', vocabulary.coat),
    ('index of refraction', vocabulary.ior),
    ('transmission', vocabulary.transmission),
    ('sheen', vocabulary.sheen),
  ]) {
    if (resolved[inputName] is TextureInput) {
      report.drop('material "$id" $name image', 'only its factor is read');
    }
  }

  final surface = SurfaceMaterial(
    name: id,
    baseColor: LinearColor.fromSrgb(base.x, base.y, base.z, opacity),
    metallic: metallic.clamp(0.0, 1.0),
    roughness: roughness.clamp(0.0, 1.0),
    baseColorTexture: baseTexture,
    metallicRoughnessTexture: metalRough,
    normalTexture: normalTexture,
    occlusionTexture: occlusionTexture,
    emissiveTexture: emissiveTexture,
    emissive: emissiveTexture != null && emissive.length2 == 0.0
        ? LinearColor.white
        : LinearColor(emissive.x, emissive.y, emissive.z),
    alphaMode: alphaMode,
    alphaCutoff: threshold > 0.0 ? threshold : 0.5,
    extensions: layered
        ? MaterialExtensions(
            ior: ior,
            clearcoat: coat,
            clearcoatRoughness: coatRoughness,
            transmission: transmission,
            sheenColor: LinearColor(sheenColor.x, sheenColor.y, sheenColor.z),
            sheenRoughness: sheenRoughness,
          )
        : null,
  );
  report.map(
    'material "$id" (${vocabulary.name}) -> metal-rough'
    '${layered ? ' with layers' : ''}',
  );
  return MaterialSource(id, surface, images: images);
}
