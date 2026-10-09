import 'package:flutter3d_core/flutter3d_core.dart';

// The style family: the looks a game or a tool lays over the finished
// picture. Each effect is a plugin of its own and the switch of its own
// render step.
//
// **The passes are still drawn by the kernel**, between
// `beforeHighContrast` and `afterViewportShading`, with the settings
// `RenderSettings` always had. Installed, nothing changes; switched off, the
// step is withdrawn from every frame and `FrameResult.skipped` names it. See
// `RendererSteps.provide`.

/// The high-contrast look: the picture flattened and toned around the nodes
/// a game marked — `RenderSettings.highContrast`.
final class HighContrastAddon extends RenderStepAddon {
  const HighContrastAddon()
    : super(
        id: 'flutter3d_addon_style.high_contrast',
        provides: const <RenderStep>[RenderStep.highContrast],
        settings: const <SettingsSlot<Object>>[SettingsSlot.highContrast],
        description: 'A flat, toned picture with the marked nodes ringed.',
      );
}

/// The rings the high-contrast look draws around every node with a
/// `MeshNode.outlineColor`, as a step of their own.
///
/// **Not one of the kernel's thirty steps**, so this package adds it. The
/// rings are drawn inside the high-contrast pass and own no pass of their
/// own; the switch is `HighContrastSettings.outlineWidth`, nought when off,
/// and the look stays. Needs [RenderStep.highContrast].
const RenderStep outlinesStep = RenderStep(
  'outlines',
  needs: <RenderStep>{RenderStep.highContrast},
  switchOff: _outlinesOff,
  isOn: _outlinesOn,
);

RenderSettings _outlinesOff(RenderSettings s) =>
    s.copyWith(highContrast: s.highContrast.copyWith(outlineWidth: 0.0));
bool _outlinesOn(RenderSettings s) => s.highContrast.outlineWidth > 0.0;

/// The outlines — [outlinesStep]. Needs [HighContrastAddon], which the
/// plugin host installs first.
final class OutlinesAddon extends RenderStepAddon {
  const OutlinesAddon()
    : super(
        id: 'flutter3d_addon_style.outlines',
        adds: const <RenderStep>[outlinesStep],
        provides: const <RenderStep>[outlinesStep],
        dependsOn: const <String>['flutter3d_addon_style.high_contrast'],
        description: 'Rings around the nodes a game marked.',
      );
}

/// The editor's normals, clay, outline and curvature views —
/// `RenderSettings.viewportShading`.
final class ViewportShadingAddon extends RenderStepAddon {
  const ViewportShadingAddon()
    : super(
        id: 'flutter3d_addon_style.viewport_shading',
        provides: const <RenderStep>[RenderStep.viewportShading],
        settings: const <SettingsSlot<Object>>[SettingsSlot.viewportShading],
        description: "The editor's normals, clay, outline and curvature.",
      );
}

/// Cel shading: the light in a few hard bands and a rim — the lighting
/// model a material picks by the name `Toon`.
///
/// **This package's, and the same constant as `LightingModel.toon`**, which
/// the kernel keeps as a stable alias for 1.x: its stages are still compiled
/// into every backend's engine bundle, so a material naming `Toon` draws
/// whether or not [ToonLightingAddon] is installed. The addon is the model
/// registered the way any plugin's is, through `LightingModels`.
const LightingModel toonLighting = LightingModel('Toon', 'Toon');

/// The toon lighting model — [toonLighting] — registered while on.
///
/// Not a render step and not in [styleAddons]: a lighting model is compiled
/// into the scene's own stages and picked per material, not switched per
/// frame. Its stages come with the backend's bundle, so [stagesFor] answers
/// null; a third-party model's addon answers with its own.
final class ToonLightingAddon extends LightingModelAddon {
  const ToonLightingAddon()
    : super(
        id: 'flutter3d_addon_style.toon',
        models: const <LightingModel>[toonLighting],
        description: 'Cel shading: the light in a few hard bands.',
      );
}

/// Every effect of the style family, the look before the outlines that need
/// it.
///
/// The toon look is [ToonLightingAddon], installed beside these: it is a
/// lighting model a material picks, not a step of the frame.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   registries: <PluginRegistry>[renderer.renderSteps],
///   plugins: styleAddons,
/// );
/// ```
const List<RenderStepAddon> styleAddons = <RenderStepAddon>[
  HighContrastAddon(),
  OutlinesAddon(),
  ViewportShadingAddon(),
];
