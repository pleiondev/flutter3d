import 'package:flutter3d_core/flutter3d_core.dart';

// The atmosphere family: the air between the camera and what it sees, and
// the sky behind it. Each effect is a plugin of its own and the switch of
// its own render step.
//
// **The passes are still drawn by the kernel.** The fog and the sky are
// arithmetic inside the scene pass; the volumetric fog and the light shafts
// stand between their anchors after the scene. Installed, nothing changes;
// switched off, the step is withdrawn from every frame and
// `FrameResult.skipped` names it. See `RendererSteps.provide`.

/// The distance and height fog the lit stages mix in —
/// `RenderSettings.fog`. Height fog is the same step: `FogSettings`
/// thins it upwards with `heightFalloff`.
final class FogAddon extends RenderStepAddon {
  const FogAddon()
    : super(
        id: 'flutter3d_addon_atmosphere.fog',
        provides: const <RenderStep>[RenderStep.fog],
        settings: const <SettingsSlot<Object>>[SettingsSlot.fog],
        description: 'Distance and height fog, mixed in where light is.',
      );
}

/// The fog marched through the light — `RenderSettings.volumetricFog`.
final class VolumetricFogAddon extends RenderStepAddon {
  const VolumetricFogAddon()
    : super(
        id: 'flutter3d_addon_atmosphere.volumetric_fog',
        provides: const <RenderStep>[RenderStep.volumetricFog],
        settings: const <SettingsSlot<Object>>[SettingsSlot.volumetricFog],
        description: 'Fog marched through the light, shadows and all.',
      );
}

/// Shafts of sunlight through the air — `RenderSettings.lightShafts`.
final class LightShaftsAddon extends RenderStepAddon {
  const LightShaftsAddon()
    : super(
        id: 'flutter3d_addon_atmosphere.light_shafts',
        provides: const <RenderStep>[RenderStep.lightShafts],
        settings: const <SettingsSlot<Object>>[SettingsSlot.lightShafts],
        description: 'Shafts of sunlight through the air.',
      );
}

/// The sky, as a step: `RenderSettings.sky`, physical unless it was given
/// colours or a cubemap (`SkySettings.resolvedPhysical`).
///
/// **Not one of the kernel's thirty steps**, so this package adds it. It is
/// drawn inside the scene pass and owns no pass of its own; its switch is
/// `SkySettings.enabled`. Off, the frame is cleared to the view's colour
/// where the sky was.
const RenderStep skyStep = RenderStep('sky', switchOff: _skyOff, isOn: _skyOn);

RenderSettings _skyOff(RenderSettings s) =>
    s.copyWith(sky: s.sky.copyWith(enabled: false));
bool _skyOn(RenderSettings s) => s.sky.enabled;

/// The sky — [skyStep], the physical sky by default.
final class SkyAddon extends RenderStepAddon {
  const SkyAddon()
    : super(
        id: 'flutter3d_addon_atmosphere.sky',
        adds: const <RenderStep>[skyStep],
        provides: const <RenderStep>[skyStep],
        settings: const <SettingsSlot<Object>>[SettingsSlot.sky],
        description: 'The sky: scattered sunlight, a gradient or a cubemap.',
      );
}

/// Every effect of the atmosphere family.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: atmosphereAddons,
/// );
/// ```
const List<RenderStepAddon> atmosphereAddons = <RenderStepAddon>[
  SkyAddon(),
  FogAddon(),
  VolumetricFogAddon(),
  LightShaftsAddon(),
];
