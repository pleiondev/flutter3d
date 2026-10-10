/// The light family of post-processing: bloom, the lens flare, auto and
/// local exposure, the colour grade, the lens's distortion, the vignette and
/// the grain.
///
/// Each effect is a plugin — [BloomAddon], [LensFlareAddon] and the rest,
/// all of them in [lightAddons] — and each is the switch of its own render
/// step. The settings an application configures the family with are
/// `flutter3d_core`'s, which `flutter3d` re-exports by name; this library
/// does not.
///
/// **Each plugin adds the slots of the settings its steps read** —
/// `SettingsSlot.bloom` and the rest — so `renderer.renderSteps.settings`
/// lists the family's while it is installed, and
/// `settings.extension(SettingsSlot.bloom)` reads them the way a
/// third-party addon's own are read. The types themselves are still defined
/// in `flutter3d_core`: the kernel's passes read them as fields of
/// `RenderSettings`, and a field typed by a class of this package's would
/// make the kernel depend on its own addon. So they are imported from where
/// they are declared, and this library is where the family's documentation
/// sends a reader. An addon outside this repository defines its settings in
/// its own package and carries them in `RenderSettings.extensions`; see
/// `SettingsSlot`.
library;

export 'src/light/light_addon.dart';
