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
    this.dependsOn = const <String>[],
    this.description,
    this.settings = const <SettingsSlot<Object>>[],
  });

  /// The plugin's id — the package's name, a dot and the effect's:
  /// `flutter3d_addon_light.bloom`.
  final String id;

  /// The steps this plugin is the switch of, built in or among [adds].
  final List<RenderStep> provides;

  /// Steps of its own, made the renderer's with `RendererSteps.addStep`
  /// before anything is provided.
  final List<RenderStep> adds;

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
  /// replay does not record it being switched.
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
    final steps = host.maybeRegistry<RendererSteps>();
    if (steps == null) return;
    for (final slot in settings) {
      steps.addSettings(slot);
    }
    for (final step in adds) {
      steps.addStep(step);
    }
    for (final step in provides) {
      steps.provide(step);
    }
  }
}
