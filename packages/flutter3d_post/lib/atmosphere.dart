/// The atmosphere family of post-processing: distance and height fog,
/// volumetric fog, light shafts and the physical sky.
///
/// Each effect is a plugin — [FogAddon], [VolumetricFogAddon],
/// [LightShaftsAddon] and [SkyAddon], all in [atmosphereAddons] — and each
/// is the switch of its own render step; the sky's, [skyStep], is this
/// package's own. The settings an application configures the family with
/// are `flutter3d_core`'s, which `flutter3d` re-exports by name; this
/// library does not.
///
/// **Each plugin adds the slots of the settings its steps read** —
/// `SettingsSlot.fog` and the rest — so `renderer.renderSteps.settings`
/// lists the family's while it is installed, and
/// `settings.extension(SettingsSlot.fog)` reads them the way a third-party
/// addon's own are read. The types themselves are still defined in
/// `flutter3d_core`: the kernel's passes read them as fields of
/// `RenderSettings`, and a field typed by a class of this package's would
/// make the kernel depend on its own addon. So they are imported from where
/// they are declared, and this library is where the family's documentation
/// sends a reader. An addon outside this repository defines its settings in
/// its own package and carries them in `RenderSettings.extensions`; see
/// `SettingsSlot`.
library;

export 'src/atmosphere/atmosphere_addon.dart';
