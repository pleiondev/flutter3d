/// The materials a bundle carries in the engine's material language — `P8`.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../lighting_model.dart';
import 'material_glsl.dart';
import 'material_parser.dart';

/// The lighting models of the materials a bundle was built from, read off
/// the sources the bundle carries — `P8`.
///
/// **What a game draws a built `.f3dmat` with.** The build compiles each
/// source into a stage of the bundle and keeps the source beside it; this
/// reads the source back and builds the [LightingModel] from the program
/// itself, through [MaterialBindings.lightingModel], so which maps it samples
/// and whether it reads the light list are the program's answers rather than
/// a second description by hand. Load the same bytes with
/// `GraphicsDevice.loadShaders` and hand the library to the renderer as its
/// `materials`; a `Material` whose `lighting` is one of these draws the
/// stage of that name, on every backend that has a section for it.
final class BundledMaterials {
  BundledMaterials._(this.bundle, this._bindings)
    : lighting = <String, LightingModel>{
        for (final MapEntry(key: name, value: bindings) in _bindings.entries)
          name: bindings.lightingModel(label: name, shaderName: name),
      };

  /// Reads [bytes], a bundle as `GraphicsDevice.loadShaders` takes it.
  ///
  /// Throws a [FormatException] for a bundle with no material in it — one
  /// compiled from hand-written GLSL, whose stages say nothing about how to
  /// bind them — and a `MaterialSyntaxError` for a source that does not
  /// parse, which a bundle the build made never has.
  factory BundledMaterials.read(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final sources = decodeMaterialSection(bundle);
    if (sources.isEmpty) {
      throw FormatException(
        'bundle "${bundle.name}" carries no material-language source, so '
        'nothing in it says how its stages bind: build it from a .f3dmat, or '
        'describe its LightingModel by hand',
      );
    }
    return BundledMaterials._(bundle, <String, MaterialBindings>{
      for (final MapEntry(key: name, value: source) in sources.entries)
        name: describeMaterial(parseMaterial(source)),
    });
  }

  /// The bundle, decoded.
  final ShaderBundle bundle;

  final Map<String, MaterialBindings> _bindings;

  /// Each material's lighting model, by its name, which is also its stage's.
  final Map<String, LightingModel> lighting;

  /// The lighting model of material [name]. Throws an [ArgumentError] naming
  /// the ones the bundle has, rather than handing back nothing to draw with.
  LightingModel operator [](String name) =>
      lighting[name] ??
      (throw ArgumentError.value(
        name,
        'name',
        'bundle "${bundle.name}" has the materials '
            '${lighting.keys.join(', ')}',
      ));

  /// What `Material.parameters` starts as for material [name]: each
  /// `uniform` the source declares, at its default — `P8`. A fresh map every
  /// call, so one material's edits are not another's. Empty for a material
  /// with no uniform.
  Map<String, Float32List> parameters(String name) {
    final bindings =
        _bindings[name] ??
        (throw ArgumentError.value(
          name,
          'name',
          'bundle "${bundle.name}" has the materials '
              '${lighting.keys.join(', ')}',
        ));
    return <String, Float32List>{
      for (final MapEntry(:key, :value) in bindings.uniforms.entries)
        key: Float32List.fromList(value),
    };
  }
}
