import 'package:flutter3d_core/flutter3d_core.dart';

// The light family: the glow, the exposure, the lens and the film. Each
// effect is a plugin of its own and the switch of its own render step.
//
// **The passes are still drawn by the kernel**, at the anchors they always
// stood at (`beforeBloom`, `beforeAutoExposure` and the rest) and with the
// settings `RenderSettings` always had. What each plugin owns is the switch:
// installed, nothing changes; switched off, its step is withdrawn from every
// frame and `FrameResult.skipped` names it. See `RendererSteps.provide`, and
// `tasks/1.0-addons.md` for why the pass code has not moved yet.

/// The glow taken from the bright parts of the picture —
/// `RenderSettings.bloom`.
final class BloomAddon extends RenderStepAddon {
  const BloomAddon()
    : super(
        id: 'flutter3d_addon_light.bloom',
        provides: const <RenderStep>[RenderStep.bloom],
        settings: const <SettingsSlot<Object>>[SettingsSlot.bloom],
        description: 'The glow taken from the bright parts of the picture.',
      );
}

/// Ghosts and a halo drawn from the glow — `BloomSettings.lensFlare`. Needs
/// [BloomAddon], which the plugin host installs first.
final class LensFlareAddon extends RenderStepAddon {
  const LensFlareAddon()
    : super(
        id: 'flutter3d_addon_light.lens_flare',
        provides: const <RenderStep>[RenderStep.lensFlare],
        settings: const <SettingsSlot<Object>>[SettingsSlot.bloom],
        dependsOn: const <String>['flutter3d_addon_light.bloom'],
        description: 'Ghosts and a halo drawn from the glow.',
      );
}

/// The meter that adapts the exposure to the picture —
/// `RenderSettings.autoExposure`.
final class AutoExposureAddon extends RenderStepAddon {
  const AutoExposureAddon()
    : super(
        id: 'flutter3d_addon_light.auto_exposure',
        provides: const <RenderStep>[RenderStep.autoExposure],
        settings: const <SettingsSlot<Object>>[SettingsSlot.autoExposure],
        description: 'The meter that adapts the exposure to the picture.',
      );
}

/// Shadows lifted and highlights held, region by region —
/// `RenderSettings.localExposure`.
final class LocalExposureAddon extends RenderStepAddon {
  const LocalExposureAddon()
    : super(
        id: 'flutter3d_addon_light.local_exposure',
        provides: const <RenderStep>[RenderStep.localExposure],
        settings: const <SettingsSlot<Object>>[SettingsSlot.localExposure],
        description: 'Shadows lifted and highlights held, region by region.',
      );
}

/// Contrast, saturation, temperature, lift, gamma, gain and the colour
/// table — the grade's half of `RenderSettings.look`.
final class ColorGradeAddon extends RenderStepAddon {
  const ColorGradeAddon()
    : super(
        id: 'flutter3d_addon_light.colour_grade',
        provides: const <RenderStep>[RenderStep.colorGrade],
        settings: const <SettingsSlot<Object>>[SettingsSlot.look],
        description: 'Contrast, saturation, temperature and the colour table.',
      );
}

/// The lens's bend and its colour fringes — `LookSettings.distortion` and
/// `LookSettings.chromaticAberration`.
final class LensDistortionAddon extends RenderStepAddon {
  const LensDistortionAddon()
    : super(
        id: 'flutter3d_addon_light.lens_distortion',
        provides: const <RenderStep>[RenderStep.lensDistortion],
        settings: const <SettingsSlot<Object>>[SettingsSlot.look],
        description: "The lens's bend and its colour fringes.",
      );
}

/// The film: `LookSettings.vignette` and `LookSettings.grain`. They are one
/// step in the kernel, so one plugin switches both.
final class VignetteAndGrainAddon extends RenderStepAddon {
  const VignetteAndGrainAddon()
    : super(
        id: 'flutter3d_addon_light.vignette_and_grain',
        provides: const <RenderStep>[RenderStep.vignetteAndGrain],
        settings: const <SettingsSlot<Object>>[SettingsSlot.look],
        description: 'The film: a vignette and grain.',
      );
}

/// Every effect of the light family, the bloom before the flare that needs
/// it.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: lightAddons,
/// );
/// // From the next step boundary on, frames have no film.
/// loop.plugins.disable(const VignetteAndGrainAddon().id);
/// ```
const List<RenderStepAddon> lightAddons = <RenderStepAddon>[
  AutoExposureAddon(),
  LocalExposureAddon(),
  BloomAddon(),
  LensFlareAddon(),
  ColorGradeAddon(),
  LensDistortionAddon(),
  VignetteAndGrainAddon(),
];
