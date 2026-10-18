/// The style family of post-processing: the high-contrast look, its
/// outlines, and the editor's viewport shading.
///
/// Each effect is a plugin — [HighContrastAddon], [OutlinesAddon] and
/// [ViewportShadingAddon], all in [styleAddons] — and each is the switch of
/// its own render step; the outlines', [outlinesStep], is this package's
/// own. The settings an application configures the family with are
/// `flutter3d_core`'s, which `flutter3d` re-exports by name; this library
/// does not.
///
/// The toon lighting model is this family's too: [toonLighting], registered
/// by [ToonLightingAddon] through `LightingModels` the way a third-party
/// model is. `LightingModel.toon` is the same constant, kept in the kernel
/// as a stable alias for 1.x.
///
/// **Each plugin adds the slots of the settings its steps read** —
/// `SettingsSlot.highContrast` and the rest — so
/// `renderer.renderSteps.settings` lists the family's while it is
/// installed, and `settings.extension(SettingsSlot.highContrast)` reads
/// them the way a third-party addon's own are read. The types themselves
/// are still defined in `flutter3d_core`: the kernel's passes read them as
/// fields of `RenderSettings`, and a field typed by a class of this
/// package's would make the kernel depend on its own addon. So they are
/// imported from where they are declared, and this library is where the
/// family's documentation sends a reader. An addon outside this repository
/// defines its settings in its own package and carries them in
/// `RenderSettings.extensions`; see `SettingsSlot`.
library;

export 'src/style/style_addon.dart';
