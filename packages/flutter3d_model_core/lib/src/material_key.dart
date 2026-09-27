/// What makes two materials the same material, as a string to compare.
///
/// **One statement of it, read by two callers that ask different questions.**
/// `importInto` merges an incoming material into the project's table when the
/// two would write the identical `.f3dproj` manifest entry, name included: a
/// file opened twice must not double the table, and two materials a person
/// named differently are two entries they meant to keep. `AssetAudit` asks
/// the looser question a generated asset needs asked — "Material" and
/// "Material.001" painting the same grey are one material exported twice — so
/// it leaves the name out. The fields are otherwise the same list, and keeping
/// them in one place is what stops the two answers drifting apart the first
/// time `SurfaceMaterial` gains a field.
///
/// **A parallel statement of `project_format.dart`'s own `_materialJson`/
/// `_bindingJson`, not a shared function.** Those are file-private to the
/// format; a wrong field here compiles, runs, and is wrong only for the
/// material that hits it, which is why both are covered by their own tests
/// rather than one standing in for the other.
///
/// Not exported from the package: it is a comparison key, not a format, and a
/// caller outside this package that stored one would be storing something
/// that changes meaning whenever the field list does.
library;

import 'dart:convert';

import 'package:flutter3d_core/formats.dart';

/// [surface] as a string equal for two materials that would write the
/// identical manifest entry and different otherwise; with [named] false, equal
/// for two such materials whatever each is called.
String materialKey(SurfaceMaterial surface, {bool named = true}) =>
    jsonEncode(<String, Object?>{
      if (named) 'name': surface.name,
      'baseColor': <double>[
        surface.baseColor.x,
        surface.baseColor.y,
        surface.baseColor.z,
        surface.baseColor.w,
      ],
      'metallic': surface.metallic,
      'roughness': surface.roughness,
      'baseColorTexture': _bindingKey(surface.baseColorTexture),
      'metallicRoughnessTexture': _bindingKey(surface.metallicRoughnessTexture),
      'normalTexture': _bindingKey(surface.normalTexture),
      'normalScale': surface.normalScale,
      'occlusionTexture': _bindingKey(surface.occlusionTexture),
      'occlusionStrength': surface.occlusionStrength,
      'emissiveTexture': _bindingKey(surface.emissiveTexture),
      'emissive': <double>[
        surface.emissive.x,
        surface.emissive.y,
        surface.emissive.z,
      ],
      'emissiveStrength': surface.emissiveStrength,
      'alphaMode': surface.alphaMode.name,
      'alphaCutoff': surface.alphaCutoff,
      'doubleSided': surface.doubleSided,
      'unlit': surface.unlit,
    });

Map<String, Object?>? _bindingKey(TextureBinding? binding) => binding == null
    ? null
    : <String, Object?>{
        'imageIndex': binding.imageIndex,
        'texCoordSet': binding.texCoordSet,
        'magLinear': binding.sampling.magLinear,
        'minLinear': binding.sampling.minLinear,
        'useMipmaps': binding.sampling.useMipmaps,
        'mipLinear': binding.sampling.mipLinear,
        'wrapS': binding.sampling.wrapS.name,
        'wrapT': binding.sampling.wrapT.name,
      };
