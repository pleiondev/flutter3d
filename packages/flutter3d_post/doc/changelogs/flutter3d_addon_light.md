## 1.0.0-rc.1

- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `ColourGradeAddon` is `ColorGradeAddon`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **The light family as plugins.** `BloomAddon`, `LensFlareAddon`,
  `AutoExposureAddon`, `LocalExposureAddon`, `ColorGradeAddon`,
  `LensDistortionAddon` and `VignetteAndGrainAddon`, all in `lightAddons`.
  Each is a view plugin on plugin API 1.0 and the switch of one render
  step. The lens flare depends on the bloom.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.bloom`, `look`, `autoExposure` and `localExposure` to the
  renderer while on, so `RendererSteps.settings` lists them, and this
  library exports `SettingsSlot`. The types stay defined in
  `flutter3d_core`, which reads them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `BloomSettings`,
  `LensFlareSettings`, `AutoExposureSettings`, `ExposureMeter`,
  `ExposureAdapter`, `LocalExposureSettings` and `LookSettings` are exported
  here. They are still defined in `flutter3d_core`, so existing imports keep
  compiling.
