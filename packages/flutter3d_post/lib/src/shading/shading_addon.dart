import 'package:flutter3d_core/flutter3d_core.dart';

// The shading family: the light that does not reach a crease, and the short
// shadows where things touch. Each effect is a plugin of its own and the
// switch of its own render step.
//
// **The passes are still drawn by the kernel**, between
// `beforeAmbientOcclusion` and `afterContactShadows`, with the settings
// `RenderSettings` always had. Installed, nothing changes; switched off, the
// step is withdrawn from every frame and `FrameResult.skipped` names it. See
// `RendererSteps.provide`.

/// The ambient occlusion and its blur, whichever method —
/// `RenderSettings.ambientOcclusion`.
///
/// Switched off, the temporal resolve's occlusion history has nothing to
/// blend and starves with it; the resolve itself stays.
final class AmbientOcclusionAddon extends RenderStepAddon {
  const AmbientOcclusionAddon()
    : super(
        id: 'flutter3d_addon_shading.ambient_occlusion',
        provides: const <RenderStep>[RenderStep.ambientOcclusion],
        settings: const <SettingsSlot<Object>>[SettingsSlot.ambientOcclusion],
        description: 'Screen-space ambient occlusion and its blur.',
      );
}

/// The short march towards the sun at every pixel, and its resolve —
/// `RenderSettings.contactShadows`.
final class ContactShadowsAddon extends RenderStepAddon {
  const ContactShadowsAddon()
    : super(
        id: 'flutter3d_addon_shading.contact_shadows',
        provides: const <RenderStep>[RenderStep.contactShadows],
        settings: const <SettingsSlot<Object>>[SettingsSlot.contactShadows],
        description: 'Short shadows where things touch, marched on screen.',
      );
}

/// Every effect of the shading family.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: shadingAddons,
/// );
/// ```
const List<RenderStepAddon> shadingAddons = <RenderStepAddon>[
  AmbientOcclusionAddon(),
  ContactShadowsAddon(),
];
