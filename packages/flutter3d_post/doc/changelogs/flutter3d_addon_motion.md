## 1.0.0-rc.1

- **The motion family as plugins.** `DepthOfFieldAddon`, `MotionBlurAddon`
  and `TemporalAntiAliasingAddon`, all in `motionAddons`. Each is a view
  plugin on plugin API 1.0 and the switch of one render step.

- **Each plugin names the settings it reads.** The family's addons add
  `SettingsSlot.depthOfField`, `motionBlur` and `antiAlias` to the renderer
  while on, so `RendererSteps.settings` lists them, and this library exports
  `SettingsSlot`. The types stay defined in `flutter3d_core`, which reads
  them as fields of `RenderSettings`.

- **Installing them changes nothing.** The kernel still draws the passes,
  with the settings it always had. Switching a plugin off withdraws its step
  from every frame, and `FrameResult.skipped` reports it as switched off.
  A renderer with no addon installed draws what it always drew.

- **The family's settings in one import.** `DepthOfFieldSettings`,
  `MotionBlurSettings`, `TemporalSettings` and `TemporalClip` are exported
  here. They are still defined in `flutter3d_core`, so existing imports keep
  compiling.
