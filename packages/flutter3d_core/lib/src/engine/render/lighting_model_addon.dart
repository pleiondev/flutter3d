/// A plugin that brings lighting models.
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart' show ShaderLibrary;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'render_step_addon.dart';
import 'renderer.dart';

/// A view plugin that registers lighting models, and the stages that draw
/// them, while it is on.
///
/// **How a way to light a surface becomes an addon.** Its [install] hands
/// the renderer [stages] through `RendererSteps.addMaterials` — the one way
/// stages come in — and registers each of [models] through the engine's
/// [LightingModels], `host.registry<LightingModels>()` — the one way models
/// come in — so a material file naming one reads as it and a picker walking
/// `LightingModels.all` offers it. Switched off, the stages and the names
/// are withdrawn together.
///
/// The stages are a bundle the build made, one section per backend: a
/// `.f3dmat` whose `light` and composite hooks are the model compiles into
/// one, and `BundledMaterials` reads the models back out of the same bytes,
/// so neither half is described twice:
///
/// ```dart
/// // Loading is asynchronous and installing is not, so the bundle is loaded
/// // before the plugin is made.
/// final ink = InkAddon(
///   await renderer.device.loadShaders(bytes),
///   BundledMaterials.read(bytes),
/// );
///
/// final class InkAddon extends LightingModelAddon {
///   InkAddon(ShaderLibrary stages, BundledMaterials materials)
///     : super(id: 'acme_ink.ink', stages: stages,
///             models: materials.lighting.values.toList());
/// }
/// ```
///
/// [stages] null says the backend's own bundle already carries them — how
/// `flutter3d_post/style.dart`'s toon is registered while its stages are
/// still compiled into the engine's. A model of a plugin's own is named in
/// its namespace (`acme_ink_Ink`), as [LightingModels] explains. An engine
/// with no renderer installs this as a plugin that does nothing, as a
/// [RenderStepAddon] does.
abstract base class LightingModelAddon extends Flutter3dPlugin {
  const LightingModelAddon({
    required this.id,
    required this.models,
    this.stages,
    this.dependsOn = const <String>[],
    this.description,
  });

  /// The plugin's id — the package's name, a dot and the model's:
  /// `flutter3d_addon_style.toon`.
  final String id;

  /// The models this plugin registers.
  final List<LightingModel> models;

  /// The stages [models] are drawn with, loaded before the plugin is made,
  /// or null when the device's own bundle has them.
  final ShaderLibrary? stages;

  /// The ids of the addons this one cannot run without.
  final List<String> dependsOn;

  /// One sentence for a plugin list.
  final String? description;

  /// A view plugin on plugin API 1.0: nothing it does is in the step.
  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    dependsOn: dependsOn,
    touches: PluginTouches.view,
    description: description,
  );

  @override
  void install(PluginHost host) {
    final lighting = host.maybeRegistry<LightingModels>();
    if (lighting == null) return;
    final library = stages;
    if (library != null) {
      host.maybeRegistry<RendererSteps>()?.addMaterials(library);
    }
    for (final model in models) {
      lighting.register(model);
    }
  }
}
