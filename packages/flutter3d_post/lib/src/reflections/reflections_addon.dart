import 'package:flutter3d_core/flutter3d_core.dart';

// The reflections family: what the picture shows of itself, what a mirror
// shows, and what a probe caught of the room. Each effect is a plugin of its
// own and the switch of its own render step.
//
// **The passes are still drawn by the kernel**: the probes and the planar
// pictures among the captures (`beforeCaptures`), the screen-space
// reflections after the scene (`beforeReflections`). Installed, nothing
// changes; switched off, the step is withdrawn from every frame and
// `FrameResult.skipped` names it. See `RendererSteps.provide`.

/// Screen-space reflections — `RenderSettings.reflections`.
final class ScreenSpaceReflectionsAddon extends RenderStepAddon {
  const ScreenSpaceReflectionsAddon()
    : super(
        id: 'flutter3d_addon_reflections.screen_space',
        provides: const <RenderStep>[RenderStep.reflections],
        settings: const <SettingsSlot<Object>>[SettingsSlot.reflections],
        description: 'Reflections traced through the picture itself.',
      );
}

/// The mirrored picture behind each `PlanarReflectorNode` —
/// `RenderSettings.planarReflections`.
final class PlanarReflectionsAddon extends RenderStepAddon {
  const PlanarReflectionsAddon()
    : super(
        id: 'flutter3d_addon_reflections.planar',
        provides: const <RenderStep>[RenderStep.planarReflections],
        settings: const <SettingsSlot<Object>>[SettingsSlot.planarReflections],
        description: 'A mirrored picture behind each flat reflector.',
      );
}

/// The scene's `ReflectionProbeNode`s recaptured —
/// `RenderSettings.reflectionProbes`.
///
/// Switched off, a probe keeps the last picture it took and the scene goes
/// on sampling it, as with the setting.
final class ReflectionProbesAddon extends RenderStepAddon {
  const ReflectionProbesAddon()
    : super(
        id: 'flutter3d_addon_reflections.probes',
        provides: const <RenderStep>[RenderStep.reflectionProbes],
        description: 'Reflection probes recaptured as the scene changes.',
      );
}

/// Every effect of the reflections family.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: reflectionsAddons,
/// );
/// ```
const List<RenderStepAddon> reflectionsAddons = <RenderStepAddon>[
  ReflectionProbesAddon(),
  PlanarReflectionsAddon(),
  ScreenSpaceReflectionsAddon(),
];
