/// The materials a bundle carries in the engine's material language — `P8`.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../format_exceptions.dart';
import '../lighting_model.dart';
import 'material_ast.dart';
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
/// `materials`; a `RenderMaterial` whose `lighting` is one of these draws the
/// stage of that name, on every backend that has a section for it.
final class BundledMaterials {
  BundledMaterials._(this.bundle, this._bindings, this.stages)
    : lighting = <String, LightingModel>{
        for (final MapEntry(key: name, value: bindings) in _bindings.entries)
          name: bindings.lightingModel(label: name, shaderName: name),
      };

  /// Reads [bytes], a bundle as `GraphicsDevice.loadShaders` takes it.
  ///
  /// Throws a [MaterialBundleException] for a bundle with no material in it — one
  /// compiled from hand-written GLSL, whose stages say nothing about how to
  /// bind them — and a `MaterialSyntaxException` for a source that does not
  /// parse, which a bundle the build made never has.
  ///
  /// **One entry per source, not per stage — version 2.** A material with a
  /// `vertex` block carries its source under its vertex stages' names too,
  /// so the backend that compiles nothing can answer them; those entries
  /// are the same material and are read once. A full-screen stage or a
  /// compute kernel is in [stages] and not in [lighting].
  factory BundledMaterials.read(ByteData bytes) {
    final bundle = ShaderBundle.decode(bytes);
    final sources = decodeMaterialSection(bundle);
    if (sources.isEmpty) {
      throw MaterialBundleException(
        'bundle "${bundle.name}" carries no material-language source, so '
        'nothing in it says how its stages bind: build it from a .f3dmat, or '
        'describe its LightingModel by hand',
      );
    }
    final described = <String, MaterialBindings>{
      for (final MapEntry(key: name, value: source) in sources.entries)
        if (parseMaterial(source) case final program when program.name == name)
          name: describeMaterial(program),
    };
    return BundledMaterials._(bundle, <String, MaterialBindings>{
      for (final MapEntry(key: name, value: bindings) in described.entries)
        if (bindings.kind == MaterialStageKind.surface) name: bindings,
    }, described);
  }

  /// The bundle, decoded.
  final ShaderBundle bundle;

  final Map<String, MaterialBindings> _bindings;

  /// Every source the bundle carries, by its name — a surface's, a
  /// full-screen stage's and a kernel's alike — version 2.
  final Map<String, MaterialBindings> stages;

  /// Each material's lighting model, by its name, which is also its stage's.
  final Map<String, LightingModel> lighting;

  /// What material [name]'s `state` block says — version 2.
  /// [MaterialFileState.none] for a source without one. Throws an
  /// [ArgumentError] naming the materials the bundle has.
  MaterialFileState state(String name) =>
      (_bindings[name] ??
              (throw ArgumentError.value(
                name,
                'name',
                'bundle "${bundle.name}" has the materials '
                    '${lighting.keys.join(', ')}',
              )))
          .state;

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

  /// What `RenderMaterial.parameters` starts as for material [name]: each
  /// `uniform` the source declares, at its default — `P8`. A fresh map every
  /// call, so one material's edits are not another's. Empty for a material
  /// with no uniform.
  ///
  /// A full-screen stage's or a kernel's too — version 2: what
  /// `FullscreenEffect.uniforms` holds under `MaterialParams`.
  Map<String, Float32List> parameters(String name) {
    final bindings =
        stages[name] ??
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
