## 1.0.0-rc.1

- **The style family as plugins.** `HighContrastAddon`, `OutlinesAddon` and
  `ViewportShadingAddon`, all in `styleAddons`. Each is a view plugin on
  plugin API 1.0 and the switch of one render step. The outlines depend on
  the look.

- **Toon lighting is this package's.** `toonLighting` is the model, and
  `ToonLightingAddon` registers it through `LightingModels` the way a
  third-party model is registered. It is the same constant as the kernel's
  `LightingModel.toon`, which stays built in for 1.x because the stages are
  still in every engine bundle: a material naming `Toon` draws with or
  without the addon.

- **Each plugin names the settings it reads.** `HighContrastAddon` and
  `ViewportShadingAddon` add `SettingsSlot.highContrast` and
  `SettingsSlot.viewportShading` to the renderer while on, and this library
  exports `SettingsSlot`.

- **The outlines are a step.** `outlinesStep` is this package's own,
  switched by `HighContrastSettings.outlineWidth` and needing
  `RenderStep.highContrast`. Off, the look stays and the rings go.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `HighContrastSettings`,
  `ViewportShading` and `ViewportShadingSettings` are exported here. They
  are still defined in `flutter3d_core`, so existing imports keep
  compiling.
