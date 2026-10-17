/// A plugin that is the switch of one or more render steps.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import 'renderer.dart';

/// A view plugin that provides render steps: while it is on, they are drawn
/// as their settings say; switched off, they are withdrawn from every frame.
///
/// **What the post-processing addons are made of.** Each effect of the six
/// families of `flutter3d_post` — bloom in `flutter3d_post/light.dart`, the
/// occlusion in `flutter3d_post/shading.dart`, and so on — is one of these: an id,
/// the steps it [provides], and the steps of its own it [adds] first. Its
/// [install] asks the host for the renderer's [RendererSteps] and calls
/// `RendererSteps.provide` for each; the host withdraws them when the plugin
/// is switched off. See `RendererSteps.provide` for what that does to a
/// frame, and why a renderer with no addon installed draws the frame it
/// always drew.
///
/// **Taking over what the engine draws is declared here, and nowhere
/// else.** A plugin from outside the engine provides a built-in step only
/// when it lists it in [replaces], and hands the renderer a stage under one
/// of the engine's names (`Pbr`, a shadow pass's) only when it lists the
/// name in [replacesStages]; either puts `PluginPermission.replace` in its
/// [manifest], so a person installing it reads that it changes the
/// engine's frame. Everything else such a plugin adds stays in its own
/// namespace or is refused.
///
/// **An engine that draws nothing installs it as a plugin that does
/// nothing.** A server replaying a run has no renderer, so no
/// [RendererSteps]: the addon finds none and registers nothing, rather than
/// refusing the whole preset it came in.
///
/// ```dart
/// final class FrostAddon extends RenderStepAddon {
///   const FrostAddon()
///     : super(id: 'frost', adds: const <RenderStep>[frost],
///             provides: const <RenderStep>[frost]);
/// }
/// ```
abstract base class RenderStepAddon extends Flutter3dPlugin {
  const RenderStepAddon({
    required this.id,
    required this.provides,
    this.adds = const <RenderStep>[],
    this.replaces = const <RenderStep>[],
    this.replacesStages = const <String>[],
    this.dependsOn = const <String>[],
    this.description,
    this.settings = const <SettingsSlot<Object>>[],
  });

  /// The plugin's id — the package's name, a dot and the effect's:
  /// `flutter3d_post.bloom`.
  final String id;

  /// The steps this plugin is the switch of, built in or among [adds].
  final List<RenderStep> provides;

  /// Steps of its own, made the renderer's with `RendererSteps.addStep`
  /// before anything is provided.
  final List<RenderStep> adds;

  /// The engine's own steps this plugin takes over: it provides each, as
  /// [provides] does, and is their switch. A plugin from outside the engine
  /// provides a built-in step only through this list.
  final List<RenderStep> replaces;

  /// The engine's own shader stages, by name, that the libraries this
  /// plugin adds with `RendererSteps.addMaterials` may answer. A plugin from
  /// outside the engine replaces a stage outside its namespace only through
  /// this list.
  final List<String> replacesStages;

  /// The ids of the addons this one cannot run without — the lens flare's
  /// bloom, whose glow it is drawn from.
  final List<String> dependsOn;

  /// One sentence for a plugin list.
  final String? description;

  /// The settings slots this plugin's steps read, added to the renderer
  /// with `RendererSteps.addSettings` while it is on — the built-in ones
  /// for the kernel's effects (`SettingsSlot.bloom`), an addon's own for its
  /// own. What lets a settings screen, or a level's `renderSettings`
  /// section, find a third-party addon's settings by id.
  final List<SettingsSlot<Object>> settings;

  /// A view plugin on plugin API 1.0: nothing it does is in the step, so a
  /// replay does not record it being switched. With [replaces] or
  /// [replacesStages], it declares `PluginPermission.replace`.
  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    dependsOn: dependsOn,
    touches: PluginTouches.view,
    permissions: <PluginPermission>{
      if (replaces.isNotEmpty || replacesStages.isNotEmpty)
        PluginPermission.replace,
    },
    description: description,
  );

  @override
  void install(PluginHost host) {
    final steps = host.maybeRegistry<RendererSteps>();
    if (steps == null) return;
    steps.takeOver(steps: replaces, stages: replacesStages);
    for (final slot in settings) {
      steps.addSettings(slot);
    }
    for (final step in adds) {
      steps.addStep(step);
    }
    for (final step in <RenderStep>{...provides, ...replaces}) {
      steps.provide(step);
    }
  }
}
