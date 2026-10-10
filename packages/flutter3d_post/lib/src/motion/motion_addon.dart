import 'package:flutter3d_core/flutter3d_core.dart';

// The motion family: what a lens does with distance, what a shutter does
// with movement, and the frames blended across time. Each effect is a plugin
// of its own and the switch of its own render step.
//
// **The passes are still drawn by the kernel**, between `beforeVelocity`
// and `afterTemporalResolve`, with the settings `RenderSettings` always had.
// The velocity passes are not anybody's step: they run while the motion blur
// or the temporal resolve reads them. Installed, nothing changes; switched
// off, the step is withdrawn from every frame and `FrameResult.skipped`
// names it. See `RendererSteps.provide`.

/// The depth of field — `RenderSettings.depthOfField`.
final class DepthOfFieldAddon extends RenderStepAddon {
  const DepthOfFieldAddon()
    : super(
        id: 'flutter3d_addon_motion.depth_of_field',
        provides: const <RenderStep>[RenderStep.depthOfField],
        settings: const <SettingsSlot<Object>>[SettingsSlot.depthOfField],
        description: 'What is out of focus, blurred by its distance.',
      );
}

/// The motion blur — `RenderSettings.motionBlur`.
final class MotionBlurAddon extends RenderStepAddon {
  const MotionBlurAddon()
    : super(
        id: 'flutter3d_addon_motion.motion_blur',
        provides: const <RenderStep>[RenderStep.motionBlur],
        settings: const <SettingsSlot<Object>>[SettingsSlot.motionBlur],
        description: 'Movement smeared along its own velocity.',
      );
}

/// The jittered frames blended across time, with the reactive mask and the
/// two histories — `AntiAliasSettings.temporal`.
///
/// Switched off, a spatial upscale that was asked for appears in its place,
/// as it does when the setting is off: the kernel's upscale only runs
/// without the resolve.
final class TemporalAntiAliasingAddon extends RenderStepAddon {
  const TemporalAntiAliasingAddon()
    : super(
        id: 'flutter3d_addon_motion.temporal_anti_aliasing',
        provides: const <RenderStep>[RenderStep.temporalAntiAliasing],
        settings: const <SettingsSlot<Object>>[SettingsSlot.antiAlias],
        description: 'Jittered frames blended across time.',
      );
}

/// Every effect of the motion family.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: motionAddons,
/// );
/// ```
const List<RenderStepAddon> motionAddons = <RenderStepAddon>[
  DepthOfFieldAddon(),
  MotionBlurAddon(),
  TemporalAntiAliasingAddon(),
];
